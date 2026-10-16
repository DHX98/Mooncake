#!/bin/bash
# Follow-up verification for r3 @ 2fc4ebe2 — two parts, no full re-run.
#
#   PART 1  Re-run the SSD-offload smoke. The mixed-batch case
#           (test_get_wait_mixed_batch_serves_memory_and_ssd_keys) must
#           EXECUTE (not skip): it prints "waitmix probe" lines when it runs
#           and "mixed batch_get results" on success. The other two smoke
#           groups must stay green.
#   PART 2  Bisect client_tcp_local_memcpy_test (the one newly failing case
#           in the 208 ctest) across two commits:
#             35199bd5 = post-upstream-merge, pre get-path restructure
#             986f385c = pre-upstream-merge (previous r3 head)
#           35199bd5 FAIL + 986f385c PASS => upstream's 34 commits;
#           both PASS (with the failure stable on 052aa8d4) => report, do
#           NOT attempt a semantic fix.
#
# Env:
#   MC_SRC          checkout of the r3 tree (at or containing 2fc4ebe2)
#   BUILD_DIR       existing build tree for PART 1 ($MC_SRC/build default)
#   BISECT_ROOT     work dir for bisect worktrees (/tmp/mc-bisect default)
#   CMAKE_FLAGS     configure flags for bisect builds (defaults match the
#                   208 card; vendor paths may need machine-specific tweaks)
#   JOBS            build parallelism (nproc default)
set -euo pipefail
MC_SRC="${MC_SRC:?set MC_SRC to the mooncake source tree}"
BUILD_DIR="${BUILD_DIR:-$MC_SRC/build}"
BISECT_ROOT="${BISECT_ROOT:-/tmp/mc-bisect}"
JOBS="${JOBS:-$(nproc)}"
CMAKE_FLAGS="${CMAKE_FLAGS:--DUSE_ASCEND_DIRECT=ON -DBUILD_UNIT_TESTS=ON -DBUILD_SHARED_LIBS=ON -DUSE_CUDA=OFF -DUSE_ASCEND=OFF -DWITH_EP=OFF -DWITH_STORE_RUST=OFF}"
OUT="${OUT:-$BISECT_ROOT/out}"
mkdir -p "$OUT"

# Progress heartbeat (optional; no-op if progress.sh is absent).
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HERE/progress.sh" ]; then
  # shellcheck disable=SC1091
  . "$HERE/progress.sh"
  progress_init "followup-verify" "$OUT"
  progress_start
  trap 'progress_stop 2>/dev/null || true' EXIT
else
  progress_state() { :; }
fi

echo "########## PART 1: smoke re-run (mixed-batch case must execute) ##########"
progress_state "part1: smoke re-run"
# A mixed-case skip must not halt the memcpy bisect. Unittest prints a
# blank line before OK, so count groups on the status word.
set +e
( cd "$MC_SRC" && bash scripts/ci/run_ssd_offload_smoke.sh ) \
  2>&1 | tee "$OUT/smoke-followup.log" | tail -n 20
smoke_rc=${PIPESTATUS[0]}
set -e
python3 - "$OUT/smoke-followup.log" "$smoke_rc" <<'PY'
import re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
smoke_rc = int(sys.argv[2])
ran = t.count("waitmix probe")
got = re.findall(r"mixed batch_get results \[(\d+), (\d+)\]", t)
groups = re.findall(
    r"Ran (\d+) tests in [0-9.]+s\s+(OK(?: \(skipped=\d+\))?|FAILED(?: \([^)]*\))?)",
    t,
)
print(f"SMOKE_SCRIPT_RC={smoke_rc}")
print(f"MIXED_CASE_PROBE_LINES={ran}")
print(f"MIXED_CASE_RESULTS={got}")
ok = 0
failed = 0
for i, (n, status) in enumerate(groups, 1):
    print(f"SMOKE_GROUP_{i} tests={n} status={status}")
    if status.startswith("OK"):
        ok += 1
    else:
        failed += 1
print(f"SMOKE_GROUPS_OK={ok} FAILED_SEEN={str(failed > 0)}")
for line in t.splitlines():
    if (
        "waitmix probe" in line
        or "replica-type" in line
        or "mixed batch_get results" in line
    ):
        print("PROBE_LINE", line)
if failed or len(groups) < 3:
    print("VERDICT=FAIL")
elif ran == 0:
    print("VERDICT=MIXED_SKIPPED")
elif not got:
    print("VERDICT=MIXED_INCONCLUSIVE")
else:
    print("VERDICT=PASS")
PY

echo
echo "########## PART 2: bisect client_tcp_local_memcpy_test ##########"
for c in ${BISECT_COMMITS:-"35199bd5 986f385c"}; do
  wt="$BISECT_ROOT/$c"
  echo "----- $c -----"
  progress_state "part2: bisect building $c"
  if [ ! -d "$wt" ]; then
    git -C "$MC_SRC" worktree add --detach "$wt" "$c"
    ( cd "$wt" && git submodule update --init --recursive )
  fi
  cmake -S "$wt" -B "$wt/build" -G Ninja $CMAKE_FLAGS >"$OUT/cfg-$c.log" 2>&1
  cmake --build "$wt/build" --target client_tcp_local_memcpy_test -j "$JOBS" \
    >"$OUT/build-$c.log" 2>&1 || { echo "$c BUILD_FAIL see $OUT/build-$c.log"; continue; }
  set +e
  ( cd "$wt/build" && ctest -R '^client_tcp_local_memcpy_test$' \
      --output-on-failure ) >"$OUT/ctest-$c.log" 2>&1
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then echo "$c CTEST=PASS"; else echo "$c CTEST=FAIL see $OUT/ctest-$c.log"; fi
done

echo
echo "########## follow-up verification done; artifacts in $OUT ##########"
