# INTERNAL — 0327ddcb a2-clean (no r1 measure)

Do not quote Task 3 r1 milliseconds from this directory. There are none.
Fill/overflow bench logs are write-path only. Host-log A_R1/B_R1 lines are
leftover older-mtime parses, not this-run measure.

## Code / scripts

- code: ssd-prefetch/pr3-exist-get-wiring @ 0327ddcb1f59af995a9ac00242d7e41bf30b21fd
- dirty: 0
- store.md5 (container site-packages libmooncake_store.so): d270ecea149d2c1dfcf34e062544b660
- lease: --default_kv_lease_ttl=${KV_LEASE_TTL_MS:-2000} (2s)
- MODEL fallback: /data/weights/DeepSeek-V4-Flash-0731-w8a8 (historical mtp path gone)
- GATE_SEGMENT=0 GATE_BUFFER=0 query-only sidecar
- GLOG_v=0. Did not call run_ab.sh.
- a2_clean_ab.sh lived only under experiment logs (perf/logs / live pull);
  not product code on this branch.

## Task 1 / 2

SKIP. Binaries reused. No Mooncake C++ edit.

## Task 3 r1 / r2

N/A. No measure.

## Fill / overflow (this run only)

- A fill 48/0 med=3128.56 mean=3157.17 p99=3831.27 duration 272.51s
- A overflow 48/0 med=3049.44 mean=3045.18 p99=3093.82 duration 267.39s
- no overflow enlarge
- B fill/overflow not run

## Gate A (10:25:35Z–10:26:02Z)

SSD_GATE list hit port=9021 n=3840.
SSD_GATE store setup segment=0 protocol=tcp master=127.0.0.1:50111
AscendDirectTransport: cannot allocate local segment, ret: -1 (20 retries)
Failed to install Ascend transport / init transfer engine
RuntimeError store.setup ret=-1
n_fill_keys=3840 n_sampled=64 MEMORY=0 LOCAL_DISK=0 LOCAL_DISK-only=0
MISSING=64 GATE_PASS=0 attempt=1 reason=probe_err RuntimeError
MISSING=64 is the except path, not a replica-desc sample.
FILE_READ_FAIL=0 (no measure entered).

## Master at gate (10:25:58Z)

Mem Storage: 1.01 GB / 2.00 GB (50.5%)
SSD Storage: 21.28 GB / 18.00 TB
Keys: 3840 (soft-pinned: 0)
Eviction: Success/Attempts=39/367 keys=3478 size=9.70 GB
Promotion: all 0
Offload happened; replica query did not.

## Gate B

WAIT_READY_RC=1. Serve start returned 0 (master :50111, vllm :8271).
EngineCore WorkerProc init failed ~10:29:46Z; APIServer RuntimeError
Engine core initialization failed. wait_ready sat until 900s NOT_READY.
ssd_ab2_b stayed empty. FILE_READ_FAIL 0 on that serve.

## Classification

- A: HARNESS (sidecar still installs Ascend TE at GATE_SEGMENT=0)
- B: runtime (wait_ready / EngineCore fail after A stop + B start)
- Product A/B gain: N/A
