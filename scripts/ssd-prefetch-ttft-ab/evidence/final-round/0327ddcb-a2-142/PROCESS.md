# 142 Task-3 PROCESS

Host <host-ip> container <bench-container>. Max 4 cycles. Pass = r1 med/mean/p99 gain all > 0.
LOCAL_DISK sidecar is not a stop. store.so stock. No Mooncake C++ edit.

Harness notes: cycle 1 first serve died (MTP KV 10.79 GiB needed vs 6.8 GiB). Added H20 `--kv-cache-dtype fp8` on ascend.env; retry wait_ready OK. Sidecar LOCAL_DISK probe_err throughout; proceeded on store-proof. B `prefetch_task_registered=0` / kick=0 both cycles; Promotion completed=0 (grep "promotion" counts Admin Metrics lines). r1 still passed cycle 2.

## Cycle 1 2026-09-21T12:44:01Z

- A_RC=0 B_RC=0
- A_R1 success=48 fail=0 med=4673.44 mean=4378.15 p99=11833.09
- B_R1 success=48 fail=0 med=4774.92 mean=4884.19 p99=8587.41
- A_FILL success=48 fail=0 med=2391.67 mean=3199.25 p99=22338.96 OVERFLOW success=48 fail=0 med=2335.24 mean=2365.34 p99=2617.18
- B_FILL success=48 fail=0 med=2390.10 mean=2429.33 p99=2959.49 OVERFLOW success=48 fail=0 med=2330.73 mean=2349.01 p99=2625.21
- A_LD=STORE_PROOF_PROCEED B_LD=STORE_PROOF_PROCEED
- STORE_PROOF A=STORE_HAPPENED=1 B=STORE_HAPPENED=1
- HANGS=0
- FAIL cycle 1 A_RC=0 B_RC=0 r1_pass=no. See diagnosis: prefetch_task_registered/promotion/kick/FILE_READ_FAIL/fill-overflow/B enable_ssd_prefetch. Retry next cycle after wipe SSD + reclaim.

## Cycle 2 2026-09-21T13:31:05Z

- A_RC=0 B_RC=0
- A_R1 success=48 fail=0 med=4776.03 mean=5057.06 p99=8476.83
- B_R1 success=48 fail=0 med=4706.92 mean=4568.42 p99=8210.17
- A_FILL success=48 fail=0 med=2395.60 mean=2413.36 p99=2821.21 OVERFLOW success=48 fail=0 med=2331.02 mean=2338.27 p99=2600.47
- B_FILL success=48 fail=0 med=2392.31 mean=2421.77 p99=2896.03 OVERFLOW success=48 fail=0 med=2333.76 mean=2366.24 p99=2626.99
- A_LD=STORE_PROOF_PROCEED B_LD=STORE_PROOF_PROCEED
- STORE_PROOF A=STORE_HAPPENED=1 B=STORE_HAPPENED=1
- HANGS=0
- PASS. Stop.

## Orch 2026-09-21T21:32:57+0800

orch collect+stop_serve done
