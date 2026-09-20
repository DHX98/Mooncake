# A2 final-gate 21d8f1aa — architect brief

Audience: architect agent. This is **not** a FINAL_ROUND evidence
pack (Task 2 smoke failed; per fail policy nothing was pushed as
`evidence/final-round/`). Absolute TTFT milliseconds stay out of this
note. Host names, employee IDs, container names, and intranet paths
are replaced with placeholders.

## 0. One-paragraph verdict

The A2 “open-PR” gate on `ssd-prefetch/pr3-exist-get-wiring` @
`21d8f1aa3e86faecea6f6b6e526bf90e5f9cece2` stopped at **Task 2
smoke**. Compile, prefetch-path warnings, format, and the six ctest
targets (including the three tests that failed on `8bfb5130`) all
passed. `test_prefetch_on_exist` failed **before**
`is_exist(..., prefetch_to_memory=True)`: the fixture never produced a
LOCAL_DISK-only key; the negative case then PUT 0 times on the same
full 32 MiB segment. That is the same fixture chain as `8bfb5130` on
this host family. It is **not** a vLLM / vLLM-ascend / DSV4-Flash
implementation delta, and it is **not** the H20 clean-gate (that gate
never ran this unittest). Do not treat this red as proof that the
prefetch product path is broken — that path was not entered.

## 1. Gate the field was scored against

Source: operator brief for “A2 最终验证轮” plus
`scripts/ssd-prefetch-ttft-ab/FINAL_ROUND.md` @ `2fc8981` (points at
`21d8f1aa`). Fail-fast confirmed by operator: Task 1 or 2 red → stop,
do not run Task 3, do not push FINAL_ROUND evidence.

| # | Criterion | Hard bar |
|---|---|---|
| 1 | cmake + ninja Release `BUILD_UNIT_TESTS=ON`; prefetch-path 0 warning; `code_format.sh --check` + pre-commit on a **clean** worktree | fail → stop |
| 2 | ctest `-R prefetch_throttle_test\|prefetch_task_master_test\|client_readonly_query_test\|promotion_on_hit_test\|file_storage_promotion_test\|file_storage_test`. Must pass the three that died on `8bfb5130`; no regression on the other three | fail → stop |
| 3 | `bash scripts/ci/run_ssd_offload_smoke.sh`. `test_prefetch_on_exist` **both** cases: promote succeeds, no-promote holds | fail → stop |
| 4 | A/B `CONC=4`: median/mean/p99 gains all **> 0** (+85% is reference only; p99 < 0 is fail) | not reached |
| 5 | Backfill: `prefetch_task_registered`, DRAM saturated/backing off, get-side kick counts; scrub every file | not reached |

Operator also required: worktree clean before format; kill occupier
NPU jobs; restart existing bench container (no pull/rm); stop container
after the round.

## 2. Scorecard @ 21d8f1aa (this round)

| Item | Result | Notes |
|---|---|---|
| Code HEAD | `21d8f1aa3e86faecea6f6b6e526bf90e5f9cece2` | `[Store] Apply clang-format and ruff-format to prefetch changes` (mechanical; no behavior change vs `eabc511f`) |
| Branch | `ssd-prefetch/pr3-exist-get-wiring` | not `v3-verify`, not `all-in-one` |
| Scripts | `ssd-prefetch/v3-verify` ttft-ab overlay | FINAL_ROUND names `21d8f1aa` |
| Worktree | dirty = 0 before format and after | Phase 0 `git clean` had wiped FetchContent trees; vendors restored **outside** product files |
| Task 1 compile | PASS, `CMAKE_RC=0` `BUILD_RC=0` jobs=64 | unit-test `build/` and deploy `build-deploy/` both finished |
| prefetch warnings | **0** | `task1_warn.txt` empty |
| other warnings | 16 informational | TE/HA/`store_py_internal.h`; not a gate fail |
| format | PASS | Windows worktree, clang-format **20.1.8**, `code_format.sh --check` RC=0, dry-run 0/30, diff 0 bytes. `pre-commit` RC=1 only because hook `mooncake-code-format` could not find `/bin/bash` on Windows; ruff / ruff-format / cmake-format / codespell passed |
| Task 2 ctest | **6/6**, `CTEST_RC=0`, 117.21 s | see §3 |
| Task 2 smoke | **FAIL**, `SMOKE_RC=1` | offload + promotion_on_hit sections OK; prefetch section both cases FAIL; see §4 |
| Task 3 A/B | not run | fail-fast |
| Evidence push | not done | fail-fast |
| Container | stopped, not removed | after red |

## 3. ctest (green) — the 8bfb5130 holes are closed

| Target | 8bfb5130 | 21d8f1aa |
|---|---|---|
| `client_readonly_query_test` | FAIL, `InitGoogleLogging()` twice | **Passed 13.04 s** |
| `prefetch_task_master_test` | FAIL, same | **Passed 5.02 s** |
| `PrefetchThrottleTest.FailedKeyRetriesAfterBackoffNotFullTtl` | FAIL, reserve 0 vs 1 | **Passed** (parent binary 0.03 s, no Failed dump) |
| `promotion_on_hit_test` | Passed | Passed 76.07 s |
| `file_storage_promotion_test` | Passed | Passed 0.08 s |
| `file_storage_test` | Passed | Passed 22.95 s |

So the C++ regressions named in FINAL_ROUND are **not** why this gate is red.

## 4. Why `test_prefetch_on_exist` did not pass

### 4.1 What the script actually runs

`scripts/ci/run_ssd_offload_smoke.sh` is three isolated master lives:

1. **ssd / offload** — `test_ssd_offload_in_evict.py` (this run: client
   mounted **512 MiB**; Ran 3, OK, ~69 s).
2. **promotion** — master `--enable_offload --offload_on_evict
   --promotion_on_hit=true`. `test_promotion_on_hit.py` (32 MiB,
   96×1 MiB). Ran 3, OK skipped=1, ~41 s. Printed
   `replica-type histogram after phase 2: {'DISK,LOCAL_DISK': 5,
   'DISK,LOCAL_DISK,MEMORY': 25, 'DISK,MEMORY': 2}`.
3. **prefetch** — new master `--enable_offload --offload_on_evict
   --promotion_on_hit=false`. Pins:
   `MASTER_SERVER=127.0.0.1:50051`, `SEGMENT_SIZE_BYTES=33554432`,
   `LOCAL_BUFFER_SIZE_BYTES=67108864`, offload path
   `/tmp/mooncake_ci_prefetch`, heartbeat 2 s. Then
   `python mooncake-wheel/tests/test_prefetch_on_exist.py`.

Step 3 is the only red. FINAL_ROUND’s “钉死环境变量” only pins
address/size so a leftover A/B `MOONCAKE_GLOBAL_SEGMENT_SIZE` cannot
silently attach the client to the wrong master. It does **not** change
the overflow/offload contract.

### 4.2 Positive case — PUT worked; cold-key fixture did not

`test_exist_with_prefetch_promotes_ssd_only_key`:

1. `setUpClass` one shared `MooncakeDistributedStore`.
2. `_make_cold_keys("promote")`: 96 keys × 1 MiB. Assertion is only
   `len(reference) > 0`.
3. This run: puts succeeded until the tail
   (`prefetch_promote_88` … `_95`) logged
   `Failed to start put operation ... insufficient space` in
   `client_service.cpp` (same warning as 8bfb5130, which started at
   `_32`). Overflow is **intended**.
4. `_find_cold_key` polls 25 s for a key whose replica tags contain
   `LOCAL_DISK` and contain **no** `MEMORY`. On timeout the detail is
   `None` — the probe does **not** record a type histogram (unlike
   `test_promotion_on_hit`).
5. Fail:

   ```
   AssertionError: timeout (25s) waiting for a LOCAL_DISK-only key
   after eviction - is offload_on_evict=true and the segment small
   enough to overflow?; last=None
   ```

6. The next line in the test (`is_exist(cold_key, prefetch=True)`)
   **never ran**. Prefetch product behavior is untested this round.

Mount line for this client (same log):
`Mounting segment: 33554432 bytes, 33554432 of 33554432`.
Prep: `NO_LEFTOVER_MOONCAKE_ENV`. `ExistOptions.prefetch_to_memory`
imported from the unit-test `store.so`.

### 4.3 Negative case — 0 PUTs is a follow-on, not a dead PUT API

`test_exist_without_prefetch_does_not_promote` shares the same
`setUpClass` store / 32 MiB segment. The positive case left objects in
place and did not free the segment. All 96 control PUTs failed →
`AssertionError: 0 not greater than 0 : No PUTs succeeded`.
`is_exist` without prefetch was also never evaluated.

`test_promotion_on_hit` documents why `tearDownClass` must
`store.close()`: an unmounted leftover segment inflates master
`mem_total_capacity` and makes watermark timing flaky. Prefetch tests
close only at class teardown, **after both cases**.

### 4.4 Same-host, same script: promotion overflow works

On the **same** smoke invocation, section 2 already produced five
`DISK,LOCAL_DISK` keys under `promotion_on_hit=true` and the older
positional `setup()`. Section 3 (`promotion_on_hit=false` + dict
`setup()` with `enable_ssd_prefetch=true`, `LOCAL_HOSTNAME=127.0.0.1`)
did not produce a LOCAL_DISK-only key in 25 s.

So “cannot PUT / cannot overflow” is false as a host-level claim.
The gap is **section-3 fixture vs section-2 fixture**, not “A2 cannot
offload”.

### 4.5 What this is not

| Hypothesis | Why rejected |
|---|---|
| Leftover A/B env / wrong master | Pins applied; leftover Mooncake env unset; mount is 32 MiB; RPC 50051 |
| Wrong `.so` (image wheel) | Isolated `PYTHONPATH` → unit-test `store.cpython-312-aarch64-linux-gnu.so`; `HAS_PREFETCH True` |
| InitGoogleLogging / throttle reserve | Those ctests passed |
| vLLM vs vLLM-ascend DSV4-Flash | No `vllm serve`, no weights, no connector in this process |
| PUT API broken | Positive case put tens of 1 MiB objects before space warnings |
| Prefetch `is_exist` regression | Call not reached |

### 4.6 Open (for architect — not proven)

- Does `enable_ssd_prefetch=true` or `promotion_on_hit=false` change
  eviction so MEMORY replicas are not dropped? Promotion histogram
  shows most keys stay `*,MEMORY`; prefetch probe needs **zero**
  MEMORY. A ratio of 5/32 disk-only under promotion_on_hit=true could
  become 0/N under prefetch flags.
- Dict `setup()` + `127.0.0.1` vs positional `localhost` — segment
  identity / double-count?
- 25 s vs offload heartbeat when promotion_on_hit is off.
- Shared store between the two prefetch cases (isolation).
- 32 MiB + 96×1 MiB vs the older H20 store gate that used **16 MiB**
  and **512 KiB** values (see §7).

## 5. Evidence chain (this host family)

Replace placeholders when reading raw logs on the bench box.

| When | SHA | What | Where |
|---|---|---|---|
| 2026-09-20 ~04:40Z | `8bfb5130` | Same smoke: offload OK, promotion OK; prefetch both FAIL; space warnings from `prefetch_promote_32`; `last=None`; then 0 PUTs | `evidence/final-round/INTERNAL.md`, `evidence/final-round/gate/task2_smoke.extract.txt` |
| 2026-09-20 | `8bfb5130` | ctest 3/6 (glog twice + throttle); format FAIL; A/B still run that day: r1 gain +7.2 / +6.3 / **−4.0%**; get-side kick 0 (PR3 had deleted it) | `evidence/final-round/README.md` |
| later | `eabc511f` | format-only precursor; A2 format FAIL on that SHA; Task 2/3 skipped | `ssd-prefetch/v3-verify-a2` pack |
| 2026-09-20T06:54:56Z | `21d8f1aa` | format commit on GitHub | DHX98/Mooncake |
| 2026-09-20T15:23:52Z | `21d8f1aa` | smoke start; metadata :8080 | `$REAL/gate/task2_smoke.log` |
| 15:25:03Z | same | promotion master: offload-on-evict **and** promotion-on-hit enabled | same log |
| 15:25:03–15:25:35Z | same | promotion client 32 MiB; histogram 5 disk-only | same log |
| 15:25:45Z | same | **new** prefetch master: offload-on-evict, promotion-on-hit **false** | same log |
| 15:25:46Z | same | prefetch client mount 32 MiB; space warnings `_88`–`_95` | same log |
| +25 s | same | `last=None`; then 0 PUTs; `Ran 2 tests in 29.734s FAILED (failures=2)` | same log |
| after | same | container stopped, not removed; no FINAL_ROUND push | operator fail-fast |

On-box logs (not in this commit):

- `$REAL/gate/task2_ctest.log`
- `$REAL/gate/task2_smoke.log` (~1.6 MiB)
- `$REAL/gate/task2_host.log`
- `$REAL/gate/task1_build.log`, `task1_warn.txt` (empty)

`$REAL` = `<user>/prefetch_*/920_pre_pr` on the A2 bench host.

## 6. “Old could run” — three different passing contracts

`test_prefetch_on_exist` has **no recorded PASS** on this PR3 tree on
A2 (`8bfb5130` and `21d8f1aa` both red). Things that **did** pass are
other contracts:

### 6.1 Same smoke file, older section — `test_promotion_on_hit`

Still green today on A2 @ 21d8f1aa. Same 32 MiB / 96×1 MiB, but:

- master `promotion_on_hit=true` (prefetch section must turn this
  **off** or the negative case is meaningless);
- positional `setup()`, hostname `localhost`, offload only;
- poll interval 1.0 s **and** a printed type histogram;
- `close()` in `tearDownClass` to unmount.

### 6.2 Service-level v3-verify A/B (A2, +85% class)

`evidence/v3-verify/RESULT.md`, branch `ssd-prefetch/v3-verify` @
`8cdcc10f`. `vllm serve`, segment **256 MiB**, 48×16385 prefixes,
settle 90 s, `promotion_on_hit=false`, measure CONC=4. Pass bar:
fill/overflow 48/48 and r1 median/mean/p99 all B<A. Not a 25 s
LOCAL_DISK-only unittest. Kick/register greps are from this world.

### 6.3 Earlier GPU store gate (`prefetch_gate.py`)

Semantic cousin of `test_prefetch_on_exist`, and it **did** pass
(ON: LOCAL_DISK→MEMORY + PrefetchKeys=1; OFF: stayed LOCAL_DISK).
Knobs were not the CI unittest:

| | GPU `prefetch_gate.py` (PASS) | CI `test_prefetch_on_exist` (FAIL) |
|---|---|---|
| segment | **16 MiB** | 32 MiB |
| value | **512 KiB** | 1 MiB |
| keys | 32–64, separate ON/OFF setups | 96, **one shared store** |
| local buffer | 8 MiB | 64 MiB |
| after overflow | **lease wait 6 s** | none |
| histogram | printed put_ok / disk_only | `last=None` |

## 7. H20 vs A2 — the tests are not the same

H20 “clean-gate” evidence (`evidence/h20-clean/`, commit `e83fc1b`)
contains **zero** `run_ssd_offload_smoke.sh` / `test_prefetch_on_exist`
hits. What passed on H20:

- `PLATFORM=h20` `run_ab.sh`: NVIDIA DSV4-Flash, TP=8, segment
  **256 MiB**, 48 prefixes, settle 90 s, measure CONC=4;
- per-arm pre-measure gate: `FILE_READ_FAIL` vllm=0 and master=0
  (`GATE_PASS a_before_r1` …);
- store.so stock `eabc511f` (`668c0f08…`); engine.so
  `275b0687…` required;
- r1 gain median 27.41% / mean 6.70% / p99 0.32% (all > 0).

H20 `_h20_smoke.sh` in the GPU refactor tree is also **`vllm serve`
:8271**, not the wheel unittest.

`H20_NOTES.md` already warns: A2 connector 16k hit granularity must
not be copied blindly to NVIDIA; H20 first r1 hung 46/48 on
`FILE_READ_FAIL` / still-pending and was voided + remesured. That is a
transfer/read-size problem, not the 32 MiB cold-key fixture.

| | H20 clean-gate (green) | A2 Task 2 this round (red) |
|---|---|---|
| Binary | `run_ab.sh` + `vllm serve` | `run_ssd_offload_smoke.sh` + unittest |
| Objects | model KV prefixes (~16k tok) | 96 × 1 MiB `urandom` |
| DRAM | 256 MiB | 32 MiB |
| Wait | settle 90 s | poll 25 s |
| Pass bar | FILE_READ_FAIL=0 + 48/48 + TTFT sign | both prefetch cases + LOCAL_DISK-only |
| Code under test | serve + connector + store overlay | store client/master only |
| DSV4 / vLLM-ascend | in path | **not in path** |

Conclusion for the architect: **do not explain the A2 unittest red
by “H20’s DSV4 stack differs from vLLM-ascend”.** H20 never executed
this unittest. The A2 red also never entered DSV4. If the architect
wants a same-test comparison, re-run
`scripts/ci/run_ssd_offload_smoke.sh` on H20 at `21d8f1aa` (or run
`prefetch_gate.py` knobs on A2). Those experiments have not been done
in this brief.

## 8. Suggested analysis questions

1. Is section-3’s “LOCAL_DISK-only and no MEMORY” the right store
   invariant when `promotion_on_hit=false`, or should the test accept
   `DISK+LOCAL_DISK+MEMORY` and only assert prefetch adds a *new*
   promote path?
2. Should CI copy the GPU gate knobs (16 MiB, 512 KiB, lease wait,
   two isolated clients) instead of 32 MiB / 96×1 MiB / shared
   `setUpClass`?
3. Why does `test_promotion_on_hit` get 5 disk-only keys and
   `test_prefetch_on_exist` get `last=None` on the same box, same
   32 MiB, minutes apart? Flag the master/client deltas in §4.4.
4. Keep Task 3 (service A/B, H20-like) gated behind this unittest, or
   split “store fixture” vs “serve TTFT” so a fixture miss cannot
   hide a +85%-class measurement?

## 9. Pointers in this repo

| Path | Role |
|---|---|
| `scripts/ssd-prefetch-ttft-ab/FINAL_ROUND.md` | field one-pager (SHA 21d8f1aa) |
| `scripts/ci/run_ssd_offload_smoke.sh` | Task 2 smoke |
| `mooncake-wheel/tests/test_prefetch_on_exist.py` | failing cases |
| `mooncake-wheel/tests/test_promotion_on_hit.py` | passing cousin + histogram |
| `scripts/ssd-prefetch-ttft-ab/evidence/final-round/` | 8bfb5130 pack (same smoke red) |
| `scripts/ssd-prefetch-ttft-ab/evidence/v3-verify/` | A2 service A/B +85% class |
| `scripts/ssd-prefetch-ttft-ab/evidence/h20-clean/` | H20 service A/B + FILE_READ_FAIL gate |
| `scripts/ssd-prefetch-ttft-ab/H20_NOTES.md` | platform delta / hang |
| `scripts/ssd-prefetch-ttft-ab/METHOD.md` | how `run_ab.sh` is supposed to run |

End of brief.
