#!/bin/bash
# Get-side decomposition matrix: 6 arms x {pure, mixed} batch shapes.
#
#   docker exec <bench-container> bash --noprofile --norc \
#     /path/to/scripts/ssd-prefetch-ttft-ab/matrix.sh
#
# Arms (answer: which get-side mechanism earns what):
#   1  prefetch=off, on_hit=off          baseline (offload only)
#   2  prefetch=on,  wait=0              exist-side prefetch only (no kick, no wait)
#   3  prefetch=on,  wait=0, DECOUPLED   kick on, no wait   (needs OVERLAY_DIR_3)
#   4  prefetch=on,  wait=$SSD_GET_WAIT_MS  kick + wait (current PR head)
#   5  prefetch=off, on_hit=on           promotion-on-hit only
#   6  prefetch=on,  wait=$SSD_GET_WAIT_MS, on_hit=on  both
#
# Shapes:
#   pure   = the existing A/B form (every measured batch is all-SSD at pass start)
#   mixed  = each measured request reads ~WARM_FRAC of its blocks from DRAM and
#            the rest SSD-only (warm-half pass right before the measure pass,
#            over a small prefix subset that fits in the churned DRAM)
#
# Pairwise reads (see MATRIX.md):
#   3v4 = isolated wait benefit;  2v3 = isolated kick benefit;
#   5v4 = kick path vs promotion-on-hit;  5v6 = value of enabling both;
#   1v2 = exist-side prefetch base.
#
# Env on top of env.sh:
#   ARMS="1 2 3 4 5 6"  SHAPES="pure mixed"
#   OVERLAY_DIR_<n>     directory of store libs for arm n (arm 3 REQUIRED)
#   MIXED_PREFIXES=6    prefixes in the mixed subset (must fit DRAM as heads)
#   WARM_FRAC=0.45      fraction of each prompt warmed into DRAM
#   MIXED_REPS=2        warm+measure repetitions (mini-overflow between reps)
#   MATRIX_SETTLE_SEC   override env.sh SETTLE_SEC (escalate to 700 if the
#                       master shows REPLICA_IS_NOT_READY on prefetch register)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"

ARMS="${ARMS:-1 2 3 4 5 6}"
SHAPES="${SHAPES:-pure mixed}"
MIXED_PREFIXES="${MIXED_PREFIXES:-6}"
WARM_FRAC="${WARM_FRAC:-0.45}"
MIXED_REPS="${MIXED_REPS:-2}"
SETTLE_SEC="${MATRIX_SETTLE_SEC:-$SETTLE_SEC}"
export SETTLE_SEC

arm_cfg() { # sets PREFETCH / WAIT / ONHIT for arm $1
  case "$1" in
    1) PREFETCH=false; WAIT=0;                ONHIT=false ;;
    2) PREFETCH=true;  WAIT=0;                ONHIT=false ;;
    3) PREFETCH=true;  WAIT=0;                ONHIT=false ;;
    4) PREFETCH=true;  WAIT=$SSD_GET_WAIT_MS; ONHIT=false ;;
    5) PREFETCH=false; WAIT=0;                ONHIT=true  ;;
    6) PREFETCH=true;  WAIT=$SSD_GET_WAIT_MS; ONHIT=true  ;;
    *) echo "BAD_ARM $1"; exit 2 ;;
  esac
}

apply_overlay() { # OVERLAY_DIR_<n> -> $PKG, recorded with md5
  local arm="$1" var="OVERLAY_DIR_$1" dir="${!var:-}"
  if [ "$arm" = 3 ] && [ -z "$dir" ]; then
    echo "ARM3_NEEDS_OVERLAY: set OVERLAY_DIR_3 to the kick-decoupled build's"
    echo "store libs, or arm 3 silently duplicates arm 2 (the exact coupling"
    echo "this matrix exists to break). Refusing to run."
    exit 1
  fi
  [ -z "$dir" ] && return 0
  [ -d "$dir" ] || { echo "OVERLAY_MISSING $dir"; exit 1; }
  cp -a "$dir"/. "$PKG"/
  md5sum "$PKG"/libmooncake_store.so* 2>/dev/null \
    | tee "$LOGDIR/overlay_arm${arm}.md5.log"
}

collect_counters() { # $1=out file; greps master+vllm logs of the arm just run
  {
    echo "LEASE_EXPIRED_master=$(grep -ac LEASE_EXPIRED "$MASTER_LOG" || true)"
    echo "LEASE_EXPIRED_vllm=$(grep -ac LEASE_EXPIRED "$VLLM_LOG" || true)"
    echo "promotion_lines:"
    grep -a "Promotion: completed=" "$MASTER_LOG" | tail -n 3 || true
    echo "kick_lines:"
    grep -a "get-side kick" "$VLLM_LOG" | tail -n 3 || true
  } >"$1"
  # Hard gate: any LEASE_EXPIRED invalidates the arm (the round-2 lease fix
  # must hold under load).
  if grep -aq "LEASE_EXPIRED" "$MASTER_LOG" "$VLLM_LOG"; then
    echo "LEASE_EXPIRED_NONZERO arm context in $1 — INVESTIGATE BEFORE TRUSTING"
  fi
}

fill_overflow_settle() {
  echo "----- fill -----"
  DATASET="$DATADIR/prompts.jsonl" CONC="$FILL_CONCURRENCY" \
    "$HERE/bench.sh" "${tag}_fill.json"
  python3 - "$RESULTDIR/${tag}_fill.bench.log" <<'CHK'
import sys
t = open(sys.argv[1], encoding='utf-8', errors='replace').read()
n = 0
for line in t.splitlines():
    if 'Successful requests:' in line:
        n = int(line.split(':')[-1].strip() or 0)
print('fill success', n)
if n <= 0:
    print('FILL_ZERO_ABORT'); raise SystemExit(1)
CHK
  echo "----- overflow -----"
  DATASET="$DATADIR/overflow.jsonl" CONC="$FILL_CONCURRENCY" \
    NPROMPTS="$OVERFLOW_PREFIXES" BSEED="$OVERFLOW_SEED" \
    "$HERE/bench.sh" "${tag}_overflow.json"
  echo "----- settle ${SETTLE_SEC}s -----"
  sleep "$SETTLE_SEC"
}

gen_mixed_data() {
  python3 - "$DATADIR/prompts.jsonl" "$MIXED_PREFIXES" "$WARM_FRAC" \
      "$DATADIR/mixed_prompts.jsonl" "$DATADIR/mixed_warm.jsonl" <<'PY'
import json, sys
src, n, frac, outp, outw = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), sys.argv[4], sys.argv[5]
lines = [json.loads(l) for l in open(src, encoding='utf-8')][:n]
with open(outp, 'w', encoding='utf-8') as f:
    for row in lines:
        f.write(json.dumps({"prompt": row["prompt"]}) + "\n")
with open(outw, 'w', encoding='utf-8') as f:
    for row in lines:
        p = row["prompt"]
        # Character truncation: the warmed text tokenizes to a prefix of the
        # full prompt (tokenizer is sequential), so head blocks hit exactly;
        # a mid-word cut only loses the one boundary token.
        f.write(json.dumps({"prompt": p[: int(len(p) * frac)]}) + "\n")
print(f"mixed data: {len(lines)} prefixes, warm frac {frac}")
PY
}

one_arm() {
  local arm="$1" shape="$2"
  arm_cfg "$arm"
  tag="m${arm}_${shape}"
  echo
  echo "########## ARM $arm shape=$shape prefetch=$PREFETCH wait=$WAIT on_hit=$ONHIT ##########"
  apply_overlay "$arm"
  PREFETCH_OVERRIDE="$PREFETCH" PROMOTION_ON_HIT="$ONHIT" \
    SSD_GET_WAIT_MS="$WAIT" ARM="$tag" "$HERE/serve.sh" start
  "$HERE/wait_ready.sh"

  fill_overflow_settle

  if [ "$shape" = pure ]; then
    echo "----- measure r1 c=$MEASURE_CONCURRENCY (PRIMARY) -----"
    DATASET="$DATADIR/prompts.jsonl" CONC="$MEASURE_CONCURRENCY" \
      "$HERE/bench.sh" "${tag}_r1.json"
    echo "----- measure r2 (contamination check) -----"
    DATASET="$DATADIR/prompts.jsonl" CONC="$MEASURE_CONCURRENCY" \
      "$HERE/bench.sh" "${tag}_r2.json"
  else
    gen_mixed_data
    local rep
    for rep in $(seq 1 "$MIXED_REPS"); do
      if [ "$rep" -gt 1 ]; then
        echo "----- mini-overflow between reps (re-evict the subset) -----"
        DATASET="$DATADIR/overflow.jsonl" CONC="$FILL_CONCURRENCY" \
          NPROMPTS="$OVERFLOW_PREFIXES" BSEED="$OVERFLOW_SEED" \
          "$HERE/bench.sh" "${tag}_rep${rep}_ovf.json"
      fi
      echo "----- warm heads (rep $rep, c=1, NOT measured) -----"
      DATASET="$DATADIR/mixed_warm.jsonl" CONC=1 NPROMPTS="$MIXED_PREFIXES" \
        "$HERE/bench.sh" "${tag}_rep${rep}_warm.json"
      echo "----- measure mixed r1 (rep $rep, c=$MEASURE_CONCURRENCY) -----"
      DATASET="$DATADIR/mixed_prompts.jsonl" CONC="$MEASURE_CONCURRENCY" \
        NPROMPTS="$MIXED_PREFIXES" \
        "$HERE/bench.sh" "${tag}_rep${rep}_r1.json"
    done
  fi

  ARM="$tag" "$HERE/serve.sh" stop
  collect_counters "$RESULTDIR/${tag}.counters.log"
}

# datasets (shared across arms; same seeds = same data as run_ab.sh)
if [ ! -f "$DATADIR/prompts.jsonl" ]; then
  python3 "$HERE/gen_dataset.py" \
    --num-prefixes "$NUM_PREFIXES" --prefix-tokens "$PREFIX_TOKENS" \
    --seed "$SEED" --out-prefix "$DATADIR/prompts"
fi
if [ ! -f "$DATADIR/overflow.jsonl" ]; then
  python3 "$HERE/gen_dataset.py" \
    --num-prefixes "$OVERFLOW_PREFIXES" --prefix-tokens "$PREFIX_TOKENS" \
    --seed "$OVERFLOW_SEED" --out-prefix "$DATADIR/overflow"
fi

empty_ssd() {
  case "$SSD" in
    *ssd_dsv4*|*ssd_8b*|*prefetch_2646*|*prefetch-2646*)
      echo "REFUSING_OTHER_SSD $SSD"; exit 1 ;;
    /tmp|/tmp/*) echo "SSD_IS_TMP $SSD"; exit 1 ;;
  esac
  mkdir -p "$SSD"
  find "$SSD" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  echo "emptied $SSD"
}

"$HERE/serve.sh" stop || true
for arm in $ARMS; do
  for shape in $SHAPES; do
    empty_ssd
    one_arm "$arm" "$shape"
  done
done

echo
echo "########## matrix done — summary ##########"
python3 "$HERE/summarize_matrix.py" "$RESULTDIR" "${ARMS}" "${SHAPES}" "${MIXED_REPS}"
