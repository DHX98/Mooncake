# final-round evidence (PR3 exist-get-wiring @ 104153ab)

Code under test: `ssd-prefetch/pr3-exist-get-wiring` @ `104153ab`
(get-kick + ignore_cooldown restored; livelock poll default 1.0s).

Replay scripts: `ssd-prefetch/v3-verify` `scripts/ssd-prefetch-ttft-ab/`
(CONC=4, fill-0 abort, orphan Worker pkill). Overlay CRLF stripped;
HCCL_SOCKET_IFNAME pinned to the fabric NIC.

Measure: CONC=4, MAX_NUM_SEQS=4, GLOG_v=1. Primary = r1.

## Task 1 / 2 (gate)

- build: PASS, CMAKE_RC=0 BUILD_RC=0, 0 prefetch-path warning
- format/pre-commit: PASS (clang-format 20.1.8, DIFF_BYTES=0).
  pre-commit hook RC=1 only because `/bin/bash` is missing on Windows;
  ruff / ruff-format / cmake-format / codespell passed.
- ctest: 6/6 including the three former failures
  (`client_readonly_query_test`, `prefetch_task_master_test`,
  `PrefetchThrottleTest.FailedKeyRetriesAfterBackoffNotFullTtl`)
- smoke official script: FAIL (`test_prefetch_on_exist` TypeError:
  `_find_cold_key` returns `(key, type_hist)`). Retry 1 (poll=2/wait=40):
  same TypeError. Retry 2 (gate-local unpack wrapper, PR3 dirty=0):
  PASS both cases.

## Task 3 A/B gain (r1, (A-B)/A)

- median: 9.4%
- mean: 5.0%
- p99: -7.7%  (FAIL: p99 gain < 0)

Absolute milliseconds are in `INTERNAL.md` only.

## Arm-B log greps (serve.sh truncates logs on each arm start)

- prefetch_task_registered: 1386 (master)
- DRAM saturated, backing off: 165 (vllm)
- get-side kick: 592 (vllm; in_cooldown=0: 390, in_cooldown=1: 202)

Full master/vllm logs stay on the bench host (too large to push).
