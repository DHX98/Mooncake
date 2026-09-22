# 142 Task-3 PROCESS (single rerun)

Host <host-ip> container <bench-container>. One cycle. Pass = r1 med/mean/p99 gain all > 0.
LOCAL_DISK sidecar is not a stop (user lock-in). store.so stock. No Mooncake C++ edit.
Single rerun. Preflight reused (SHA 0327ddcb dirty=0, store.md5 d270ecea, lease 2s, fp8 already present).

Harness notes: sidecar LOCAL_DISK probe_err throughout; proceeded on store-proof. Both arms `prefetch_task_registered=0` / kick=0; Promotion completed=0 (grep "promotion" counts Admin Metrics lines). B `enable_ssd_prefetch=true`. r1 passed the only cycle. No further A/B.

## Cycle 1 2026-09-22T01:46:35Z

- A_RC=0 B_RC=0
- A_R1 success=48 fail=0 med=4849.73 mean=5268.96 p99=8484.43
- B_R1 success=48 fail=0 med=4668.72 mean=4397.65 p99=8201.51
- A_R2 success=48 fail=0 med=4686.95 mean=4317.35 p99=8040.91
- B_R2 success=48 fail=0 med=4635.91 mean=4516.76 p99=8221.65
- gain r1 med=3.73% mean=16.54% p99=3.33% PASS
- gain r2 med=1.09% mean=-4.62% p99=-2.25%
- A_FILL success=48 fail=0 med=2389.98 mean=2421.61 p99=2901.42 OVERFLOW success=48 fail=0 med=2332.56 mean=2351.29 p99=2617.37
- B_FILL success=48 fail=0 med=2390.32 mean=2421.50 p99=2900.60 OVERFLOW success=48 fail=0 med=2330.53 mean=2351.18 p99=2636.61
- A_LD=STORE_PROOF_PROCEED B_LD=STORE_PROOF_PROCEED
- STORE_PROOF A=STORE_HAPPENED=1 files=836 evicted=179 11.86GB B=STORE_HAPPENED=1 files=818 evicted=202 11.85GB
- FILE_READ_FAIL 0/0 all four gates
- HANGS=0
- PASS. Stop.

## Orch 2026-09-22T10:37:02+0800

orch collect+stop_serve done
STOP_SERVE_OK
PR3_HEAD=0327ddcb1f59af995a9ac00242d7e41bf30b21fd DIRTY=0
