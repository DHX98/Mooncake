# INTERNAL — final-round absolute numbers @ 104153ab

Do not quote these milliseconds from a public PR. Use percentages.

## Code / scripts

- code: ssd-prefetch/pr3-exist-get-wiring @ 104153ab9207e0bab8ae39adfe6260d4b0ddfaaa
- scripts: v3-verify ttft-ab overlay (FINAL_ROUND names 104153ab)
- store overlay md5 after install: d270ecea149d2c1dfcf34e062544b660
- master overlay md5: 3fbef11a55bd49da52ab5af0db1918b0
- CONC=4 MEASURE_CONCURRENCY=4 MAX_NUM_SEQS=4 GLOG_v=1
- segment 256MB, ssd_get_wait_ms 2000, 48 prefixes x 16385, settle 90s
- HCCL_SOCKET_IFNAME pinned (empty value broke EngineCore)

## Task 1

CMAKE_RC=0 BUILD_RC=0 both unit-test and deploy (USE_ASCEND_DIRECT=ON).
Prefetch-path warnings: 0. One informational LTO serial-jobs warning.
HEAD dirty=0. Six unit binaries present.
FORMAT_CHECK_RC=0 DIFF_BYTES=0 clang-format 20.1.8.

## Task 2

ctest 6/6 in 116s. CTEST_RC=0.
Official smoke SMOKE_RC=1:
  ERROR test_exist_with_prefetch_promotes: TypeError unhashable dict
  (wait_until returns (key, type_hist); caller used it as a key).
  FAIL test_exist_without_prefetch: timeout 25s last={'DISK,MEMORY': 5}.
Retry 1 env PREFETCH_POLL_INTERVAL_SECONDS=2 EVICTION_WAIT_SECONDS=40:
  same TypeError / FAIL. Product test default still 1.0s.
Retry 2 gate-local unpack wrapper + poll=2/wait=40: Ran 2 tests OK.
  PR3 dirty stayed 0.

## Task 3 r1 (PRIMARY)

A r1: median 2226.33 / mean 2509.56 / p99 8677.44
B r1: median 2018.02 / mean 2383.14 / p99 9343.87
gain: median 9.4% / mean 5.0% / p99 -7.7%

## Task 3 r2 (contamination)

A r2: median 1842.75 / mean 1836.95 / p99 2474.03
B r2: median 1713.12 / mean 1649.62 / p99 1943.46

## Fill / overflow

A fill 48/48, A overflow 48/48
B fill 48/48, B overflow 48/48

## Greps (arm B logs only)

prefetch_task_registered: 1386
DRAM saturated, backing off: 165 (vllm)
get-side kick: 592
in_cooldown=0: 390
in_cooldown=1: 202
