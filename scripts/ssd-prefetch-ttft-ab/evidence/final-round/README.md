# final-round evidence (PR3 exist-get-wiring @ 8bfb5130)

Code under test: `ssd-prefetch/pr3-exist-get-wiring` @ `8bfb5130`
(no get-kick, no ignore_cooldown).

Replay scripts: `ssd-prefetch/v3-verify` `scripts/ssd-prefetch-ttft-ab/`
(hardened serve/run_ab: orphan Worker pkill, fill-0 abort).

Measure: CONC=4, MAX_NUM_SEQS=4, GLOG_v=1. Primary = r1.

## Task 1 / 2 (gate)

- build: PASS, 0 error, no prefetch-path warning
- format/pre-commit: FAIL (18 C++ clang-format wraps + 1 ruff-format on
  `test_prefetch_on_exist.py`). Diff not committed on the PR branch.
- ctest: 3/6
- smoke: FAIL (`test_prefetch_on_exist` both cases)

## Task 3 A/B gain (r1, (A-B)/A)

- median: 7.2%
- mean: 6.3%
- p99: -4.0%

Absolute milliseconds are in `INTERNAL.md` only.

## Arm-B log greps (serve.sh truncates logs on each arm start)

- prefetch_task_registered: 593 (master)
- DRAM saturated, backing off: 45 (vllm)
- memory-pressure cooldown: 669 (vllm)
- get-side kick: 0 (expected: PR3 deleted it)

Full master/vllm logs stay on the bench host (too large to push).
