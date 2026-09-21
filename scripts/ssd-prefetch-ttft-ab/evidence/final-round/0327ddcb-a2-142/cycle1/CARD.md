# 142 Task-3 cycle 1 (VOID / FAIL)

PASS_R1=no. Recorded then wiped SSD + reclaim; cycle 2 is the official
PASS. Do not treat this directory as the Task-3 gain.

GLOG_v=0. GATE_SEGMENT=0 GATE_BUFFER=0. store.so d270ecea. LOCAL_DISK
sidecar not a stop. STORE_PROOF_PROCEED both arms.

## TTFT

| arm | success/fail | median | mean | p99 |
|---|---|---:|---:|---:|
| A_R1 | 48/0 | 4673.44 | 4378.15 | 11833.09 |
| A_R2 | 48/0 | 4774.67 | 5114.17 | 8905.05 |
| B_R1 | 48/0 | 4774.92 | 4884.19 | 8587.41 |
| B_R2 | 48/0 | 4657.23 | 4326.98 | 8251.56 |

| round | median gain | mean gain | p99 gain |
|---|---:|---:|---:|
| r1 | -2.17% | -11.56% | 27.43% |
| r2 | 2.46% | 15.39% | 7.34% |

PASS_R1=no

## Fill / overflow

| arm | fill | overflow |
|---|---|---|
| A | 48/0 2391.67 | 48/0 2335.24 |
| B | 48/0 2390.10 | 48/0 2330.73 |

FILE_READ_FAIL all gates 0. HANGS=0.

## First serve (before this measured cycle)

wait_ready fail: MTP KV 10.79 GiB needed vs 6.8 GiB available.
`--kv-cache-dtype fp8` added on ascend.env; retry OK. See
`wait_ready_fail.txt` + `diagnosis.txt`.

## Prefetch (B)

prefetch_task_registered=0 promotion=138 (metrics-line hits)
kick=0 Promotion completed=0. B enable_ssd_prefetch true +
SSD prefetch enabled logs. STORE_HAPPENED=1.
