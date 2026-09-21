# 141 A2 clean-gate official SSD-prefetch TTFT A/B (draft)

This round stopped before measure. Do not read leftover `*_r1.bench.log` /
`*_r2.bench.log` (older mtimes) as this-run TTFT.

GLOG_v=0 serve+measure. GATE_SEGMENT=0 GATE_BUFFER=0 query-only.
per-arm SSD ssd_ab2 / ssd_ab2_b. Did not call run_ab.sh. store.so stock
d270ecea149d2c1dfcf34e062544b660. PR3 0327ddcb dirty=0.

## TTFT

| arm | success/fail | median | mean | p99 |
|---|---|---|---|---|
| A_R1 | N/A (not measured; LOCAL_DISK harness fail) | | | |
| A_R2 | N/A | | | |
| B_R1 | N/A (wait_ready fail; no fill this arm) | | | |
| B_R2 | N/A | | | |

gain% r1: N/A (neither arm measured)

## Fill / overflow (this run only)

| arm | fill | overflow |
|---|---|---|
| A | 48/0 med=3128.56 mean=3157.17 p99=3831.27 | 48/0 med=3049.44 mean=3045.18 p99=3093.82 |
| B | not run (wait_ready fail) | not run |

## Gates

| gate | result |
|---|---|
| A LOCAL_DISK | FAIL harness. list 3840 keys @9021. probe store.setup segment=0 tcp still AscendDirectTransport cannot allocate local segment ret=-1. LOCAL_DISK-only=0 MISSING=64 via except path. No overflow enlarge. No measure. |
| A FILE_READ_FAIL | 0/0 on live logs at gate time (no measure entered) |
| B LOCAL_DISK | not reached |
| B FILE_READ_FAIL | n/a (wait_ready fail) |

## Hang / remesure

None. Fill/overflow A progressed; no 120s stall. No remesure.

## A master at gate (10:25:58Z)

Mem 1.01 GB / 2.00 GB (50.5%). SSD 21.28 GB. Keys 3840. Eviction Success/Attempts=39/367 keys=3478 size=9.70 GB. Promotion all 0. Disk after A: 7595 files / 11G on ssd_ab2. Offload happened; replica query did not.

## B wait_ready

WAIT_READY_RC=1. Serve start returned 0 (master :50111, vllm :8271). EngineCore WorkerProc init failed ~10:29:46Z; APIServer RuntimeError Engine core initialization failed. wait_ready then sat until 900s NOT_READY. ssd_ab2_b stayed empty (0 files). FILE_READ_FAIL 0 on that serve.

## Prefetch B

N/A (B never filled/measured). prefetch_task_registered / promotion / cooldown / get-side kick not collected.

## Classification

- A gate: **HARNESS** (sidecar MooncakeDistributedStore.setup still installs Ascend TE even with GATE_SEGMENT=0 / GATE_BUFFER=0). Not a product LOCAL_DISK-only=0 from a successful replica query.
- B: **runtime/harness** wait_ready fail after A stop + B start. Not a measured product fail.
- Product A/B gain: **N/A**

## Evidence on 141

- /home/<user>/prefetch_916/920_pre_pr/perf/logs/a2_clean_ab.host.log
- /home/<user>/prefetch_916/920_pre_pr/perf/logs/a2_clean_ab.CARD.md
- /home/<user>/prefetch_916/920_pre_pr/perf/logs/a2_clean_ab.progress
- /home/<user>/prefetch_916/920_pre_pr/ttft-ab/results/a_ssd_gate.txt
- /home/<user>/prefetch_916/920_pre_pr/ttft-ab/results/a_ssd_gate_fail/
- /home/<user>/prefetch_916/920_pre_pr/ttft-ab/results/a_{fill,overflow}.bench.log
- /home/<user>/prefetch_916/920_pre_pr/perf/logs/a2_clean_ab.gate_b_wait_fail.txt
