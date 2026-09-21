# 142 Task-3 SSD-prefetch TTFT A/B (cycle 2 PASS)

GLOG_v=0 serve+measure. GATE_SEGMENT=0 GATE_BUFFER=0 query-only sidecar.
per-arm SSD ssd_ab2 / ssd_ab2_b. Did not call run_ab.sh. store.so stock
d270ecea149d2c1dfcf34e062544b660. LOCAL_DISK sidecar is not a stop.
Proceed on store-proof. No quota enlarge. SHA 0327ddcb.

PASS: r1 median 1.45% mean 9.66% p99 3.15% (all > 0).

## TTFT

| arm | success/fail | median | mean | p99 |
|---|---|---:|---:|---:|
| A_R1 | 48/0 | 4776.03 | 5057.06 | 8476.83 |
| A_R2 | 48/0 | 4720.98 | 4580.80 | 8996.80 |
| B_R1 | 48/0 | 4706.92 | 4568.42 | 8210.17 |
| B_R2 | 48/0 | 4760.30 | 4917.22 | 8134.83 |

gain% = (A-B)/A*100  (PASS = r1 median/mean/p99 all > 0)

| round | median gain | mean gain | p99 gain |
|---|---:|---:|---:|
| r1 | 1.45% | 9.66% | 3.15% |
| r2 | -0.83% | -7.34% | 9.58% |

PASS_R1=yes

## Fill / overflow (must 48/0)

| arm | fill | overflow |
|---|---|---|
| A | 48/0 2395.60 | 48/0 2331.02 |
| B | 48/0 2392.31 | 48/0 2333.76 |

## FILE_READ_FAIL gates

| gate | vllm | master |
|---|---:|---:|
| A before r1 | 0 | 0 |
| A before r2 | 0 | 0 |
| B before r1 | 0 | 0 |
| B before r2 | 0 | 0 |

## Hang / remesure

- hangs counted this process: 0
- A hang log present: False
- B hang log present: False

## Prefetch counts (B)

```
prefetch_task_registered=0
promotion=137  (admin-metrics line hits; Promotion completed=0)
cooldown=0
kick_vllm=0
kick_master=0
FILE_READ_FAIL_VLLM=0
FILE_READ_FAIL_MASTER=0
```

B `enable_ssd_prefetch=true` in mooncake_b + worker
`SSD prefetch enabled: ssd_prefetch_cooldown_sec=5s, ... ssd_get_wait_ms=2000ms`.
Store happened (SSD files 820 / 11.85 GB). See `greps/b_greps.txt`.

## Store proof

- A: SSD=ssd_ab2 FILES=820 BYTES=1228059738 EVICTED_KEYS=136
  SSD_STORAGE=11.85 GB / 18.00 TB STORE_HAPPENED=1
  Mem 933.41 MB / 2.00 GB (45.6%) Keys=3840
- B: SSD=ssd_ab2_b FILES=820 BYTES=1227579254 EVICTED_KEYS=172
  SSD_STORAGE=11.85 GB / 18.00 TB STORE_HAPPENED=1
  Mem 734.61 MB / 2.00 GB (35.9%) Keys=3840

## LOCAL_DISK note

- A label: **STORE_PROOF_PROCEED** sidecar n_fill_keys=458 n_sampled=64
  MEMORY=0 LOCAL_DISK=0 LOCAL_DISK-only=0 MISSING=64 GATE_PASS=0
  attempt=1 reason=probe_err RuntimeError
- B label: **STORE_PROOF_PROCEED** sidecar n_fill_keys=425 n_sampled=64
  MEMORY=0 LOCAL_DISK=0 LOCAL_DISK-only=0 MISSING=64 GATE_PASS=0
  attempt=1 reason=probe_err RuntimeError

Sidecar replica query failed (harness). Offload/store proof used instead.

A_RC=0 B_RC=0 CYCLE=2 HANGS=0 PASS_R1=yes
