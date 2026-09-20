# INTERNAL — final-round absolute numbers

Do not quote these milliseconds from a public PR. Use percentages.

## Code / scripts

- code: ssd-prefetch/pr3-exist-get-wiring @ 8bfb5130
- scripts: v3-verify hardened ttft-ab (local tree @ 81c3c912 plus FINAL_ROUND/scrub)
- store overlay md5 after install: 146a54392ba6311073d88bf5af7e88a7
- master overlay md5: 90e9552c004301113af2ca6ccf25ba91
- CONC=4 MEASURE_CONCURRENCY=4 MAX_NUM_SEQS=4 GLOG_v=1
- segment 256MB, ssd_get_wait_ms 2000, 48 prefixes x 16385, settle 90s

## Task 3 r1 (PRIMARY)

A r1: median 2169.93 / mean 2552.21 / p99 8959.92
B r1: median 2012.79 / mean 2392.17 / p99 9319.55
gain: median 7.2% / mean 6.3% / p99 -4.0%

## Task 3 r2 (contamination)

A r2: median 1734.07 / mean 1766.42 / p99 2267.46
B r2: median 1645.32 / mean 1611.15 / p99 1881.62

## Fill / overflow

A fill 48/48, A overflow 48/48
B fill 48/48, B overflow 48/48

## Greps (arm B logs only)

prefetch_task_registered: 593
DRAM saturated, backing off: 45
memory-pressure cooldown: 669
get-side kick: 0

## Task 2 failures

ctest 3/6:
- client_readonly_query_test: InitGoogleLogging() twice
- prefetch_task_master_test: InitGoogleLogging() twice
- prefetch_throttle_test: FailedKeyRetriesAfterBackoffNotFullTtl reserve size 0 vs 1

smoke: test_prefetch_on_exist both cases
- no LOCAL_DISK-only key / No PUTs succeeded (32MB segment, insufficient space)
