# INTERNAL — 0327ddcb A2-142 Task-3 single rerun (2026-09-22 PASS)

Absolute milliseconds OK here. Do not quote these from a public PR body;
CARD gain% is the public figure.

## Code / scripts

- code: ssd-prefetch/pr3-exist-get-wiring @ 0327ddcb1f59af995a9ac00242d7e41bf30b21fd
- dirty: 0
- store.md5 (container site-packages libmooncake_store.so): d270ecea149d2c1dfcf34e062544b660
- lease: --default_kv_lease_ttl=${KV_LEASE_TTL_MS:-2000} (2s)
- MODEL kind: mtp (bench tokenizer under `/home/<user><user>/DeepSeek-V4-Flash-w8a8-mtp/DeepSeek-V4-Flash-w8a8-mtp`)
- GATE_SEGMENT=0 GATE_BUFFER=0 query-only sidecar
- GLOG_v=0. Did not call run_ab.sh. No Mooncake C++ edit.
- FP8 already present (preflight reused; KV_FP8_ALREADY). NPU empty before measure.

## This pack

Single A/B rerun, one measured cycle, recorded under `0327ddcb-a2-142-r2`.
The 2026-09-21 cycle1-miss / cycle2-pass pack remains in `0327ddcb-a2-142`.
Preflight reused: same SHA, dirty=0, store.md5 d270ecea, lease 2s, fp8 already on.
User lock-in: LOCAL_DISK sidecar probe_err is not a stop. Proceeded on store-proof.
Stopped after this pass. No second A/B.

## Cycle 1 pass (2026-09-22T01:46:35Z .. 2026-09-22T02:33:15Z)

- A_R1 48/0 med=4849.73 mean=5268.96 p99=8484.43
- B_R1 48/0 med=4668.72 mean=4397.65 p99=8201.51
- gain r1: med 3.73% mean 16.54% p99 3.33% → PASS_R1=yes
- A_R2 4686.95 / 4317.35 / 8040.91  B_R2 4635.91 / 4516.76 / 8221.65
- gain r2: med 1.09% mean -4.62% p99 -2.25%
- A fill 48/0 2389.98 overflow 48/0 2332.56
- B fill 48/0 2390.32 overflow 48/0 2330.53
- A_LD=STORE_PROOF_PROCEED B_LD=STORE_PROOF_PROCEED
- STORE_HAPPENED=1 both arms
- A files=836 evicted=179 11.86 GB; B files=818 evicted=202 11.85 GB
- FILE_READ_FAIL 0/0 on all four gates
- HANGS=0

## LOCAL_DISK sidecar / STORE_PROOF_PROCEED

Sidecar probe_err RuntimeError throughout (harness path, query-only sidecar).
A n_fill_keys=487 n_sampled=64 MEMORY=0 LOCAL_DISK=0 LOCAL_DISK-only=0
MISSING=64 GATE_PASS=0 attempt=1. B n_fill_keys=471, same zeros and
probe_err. User lock-in: this is not a stop. Proceeded on store-proof
(SSD files + master SSD Storage + evicted keys).

## Prefetch counters vs enable

Both arms: prefetch_task_registered=0 / kick=0 / Promotion completed=0
(grep "promotion" counts Admin Metrics lines: A=138 B=137).
B mooncake_b `enable_ssd_prefetch`: true. Worker logs:
`SSD prefetch enabled: ssd_prefetch_cooldown_sec=5s, ssd_prefetch_dedup_ttl_sec=30s, ssd_get_wait_ms=2000ms`.
Store happened (A 836 files / 11.86 GB, evicted 179; B 818 files / 11.85 GB, evicted 202).

## Configs

Serve configs (mooncake json, ascend.env, env.sh, serve.sh) were not in the
collected live directory. This pack does not copy them from the prior directory.

## Task 1 / 2

SKIP. Binaries reused. No Mooncake C++ edit.
