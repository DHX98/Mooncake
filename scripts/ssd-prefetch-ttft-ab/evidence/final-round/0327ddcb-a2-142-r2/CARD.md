# 142 Task-3 SSD-prefetch TTFT A/B (single rerun PASS)

GLOG_v=0 serve+measure. GATE_SEGMENT=0 GATE_BUFFER=0 query-only sidecar.
per-arm SSD ssd_ab2 / ssd_ab2_b. Did not call run_ab.sh. store.so stock
d270ecea149d2c1dfcf34e062544b660. LOCAL_DISK sidecar is not a stop.
Proceed on store-proof. No quota enlarge. SHA 0327ddcb dirty=0. Lease 2s.
Single rerun 2026-09-22. Preflight reused.

PASS: r1 median 3.73% mean 16.54% p99 3.33% (all > 0).

## TTFT

| arm | success/fail | median | mean | p99 |
|---|---|---:|---:|---:|
| A_R1 | 48/0 | 4849.73 | 5268.96 | 8484.43 |
| A_R2 | 48/0 | 4686.95 | 4317.35 | 8040.91 |
| B_R1 | 48/0 | 4668.72 | 4397.65 | 8201.51 |
| B_R2 | 48/0 | 4635.91 | 4516.76 | 8221.65 |

gain% = (A-B)/A*100  (PASS = r1 median/mean/p99 all > 0)

| round | median gain | mean gain | p99 gain |
|---|---:|---:|---:|
| r1 | 3.73% | 16.54% | 3.33% |
| r2 | 1.09% | -4.62% | -2.25% |

PASS_R1=yes

## Fill / overflow (must 48/0)

| arm | fill | overflow |
|---|---|---|
| A | 48/0 2389.98 | 48/0 2332.56 |
| B | 48/0 2390.32 | 48/0 2330.53 |

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

A arm the same on the counters that matter: prefetch_task_registered=0
kick_vllm=0 kick_master=0 Promotion completed=0 (promotion line hits=138).

B `enable_ssd_prefetch=true` in mooncake_b + worker
`SSD prefetch enabled: ssd_prefetch_cooldown_sec=5s, ssd_prefetch_dedup_ttl_sec=30s, ssd_get_wait_ms=2000ms`.
Store happened (SSD files 818 / 11.85 GB). See `greps/b_greps.txt`.

## Store proof

- A: SSD=ssd_ab2 FILES=836 BYTES=1246259698 EVICTED_KEYS=179
  SSD_STORAGE=11.86 GB / 18.00 TB STORE_HAPPENED=1
  Mem 891.52 MB / 2.00 GB (43.5%) Keys=3840
- B: SSD=ssd_ab2_b FILES=818 BYTES=1226552602 EVICTED_KEYS=202
  SSD_STORAGE=11.85 GB / 18.00 TB STORE_HAPPENED=1
  Mem 785.85 MB / 2.00 GB (38.4%) Keys=3840

## LOCAL_DISK note

- A label: **STORE_PROOF_PROCEED** sidecar n_fill_keys=487 n_sampled=64
  MEMORY=0 LOCAL_DISK=0 LOCAL_DISK-only=0 MISSING=64 GATE_PASS=0
  attempt=1 reason=probe_err RuntimeError
- B label: **STORE_PROOF_PROCEED** sidecar n_fill_keys=471 n_sampled=64
  MEMORY=0 LOCAL_DISK=0 LOCAL_DISK-only=0 MISSING=64 GATE_PASS=0
  attempt=1 reason=probe_err RuntimeError

Sidecar replica query failed (harness). Offload/store proof used instead.
User lock-in: sidecar probe_err is not a stop.

A_RC=0 B_RC=0 CYCLE=1 HANGS=0 PASS_R1=yes
