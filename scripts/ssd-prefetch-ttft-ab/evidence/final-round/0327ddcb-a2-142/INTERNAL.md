# INTERNAL — 0327ddcb A2-142 Task-3 (cycle2 PASS after cycle1 miss)

Absolute milliseconds OK here. Do not quote these from a public PR body;
CARD gain% is the public figure.

## Code / scripts

- code: ssd-prefetch/pr3-exist-get-wiring @ 0327ddcb1f59af995a9ac00242d7e41bf30b21fd
- dirty: 0
- store.md5 (container site-packages libmooncake_store.so): d270ecea149d2c1dfcf34e062544b660
- lease: --default_kv_lease_ttl=${KV_LEASE_TTL_MS:-2000} (2s)
- MODEL kind: mtp (`/home/<user>/DeepSeek-V4-Flash-w8a8-mtp/DeepSeek-V4-Flash-w8a8-mtp`)
- GATE_SEGMENT=0 GATE_BUFFER=0 query-only sidecar
- GLOG_v=0. Did not call run_ab.sh. No Mooncake C++ edit.

## Cycle 1 fail (void / recorded)

First serve (before measured cycle 1): wait_ready fail. MTP KV needed
10.79 GiB vs available 6.8 GiB. Added H20 `--kv-cache-dtype fp8` on
ascend.env; retry wait_ready OK.

Measured cycle 1 (2026-09-21T12:44:01Z): A_RC=0 B_RC=0 fill/overflow 48/0
both arms. FILE_READ_FAIL 0. HANGS=0. STORE_PROOF_PROCEED both arms.
r1 A 4673.44 / 4378.15 / 11833.09 vs B 4774.92 / 4884.19 / 8587.41
gain r1 med -2.17% mean -11.56% p99 27.43% → PASS_R1=no.
Wiped SSD + reclaim; retried cycle 2.

## Cycle 2 pass (2026-09-21T13:31:05Z)

- A_R1 48/0 med=4776.03 mean=5057.06 p99=8476.83
- B_R1 48/0 med=4706.92 mean=4568.42 p99=8210.17
- gain r1: med 1.45% mean 9.66% p99 3.15% → PASS_R1=yes
- A_R2 4720.98 / 4580.80 / 8996.80  B_R2 4760.30 / 4917.22 / 8134.83
- A fill 48/0 2395.60 overflow 48/0 2331.02
- B fill 48/0 2392.31 overflow 48/0 2333.76
- A_LD=STORE_PROOF_PROCEED B_LD=STORE_PROOF_PROCEED
- STORE_HAPPENED=1 both arms

## LOCAL_DISK sidecar / STORE_PROOF_PROCEED

Sidecar probe_err RuntimeError throughout (same harness path as 141:
store.setup still installs Ascend TE at GATE_SEGMENT=0). LOCAL_DISK-only=0
MISSING=64 via except path. Not a stop this round. Proceeded on store-proof
(SSD files + master SSD Storage + evicted keys).

## Prefetch counters vs enable

Both cycles: prefetch_task_registered=0 / kick=0 / Promotion completed=0
(grep "promotion" counts Admin Metrics lines that contain the word).
B mooncake_b `enable_ssd_prefetch`: true. Worker logs:
`SSD prefetch enabled: ssd_prefetch_cooldown_sec=5s, ssd_prefetch_dedup_ttl_sec=30s, ssd_get_wait_ms=2000ms`.
Store happened (cycle2: 820 files / 11.85 GB each arm).

## Task 1 / 2

SKIP. Binaries reused. No Mooncake C++ edit.
