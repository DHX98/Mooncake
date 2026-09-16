# SSD Prefetch-on-Exist

Related: RFC #2213, PR #2071 (promotion-on-hit).

## Goal

`exists()` on an SSD-only key (`LOCAL_DISK`, no MEMORY) may start a best-effort
SSD→DRAM promotion so a later `get()` can read DRAM. Prefetch must not change
exist/get semantics, must not block scheduling, and may be dropped on failure.
If the disk replica is remote, the holder reads its own SSD into its own DRAM.

## Path

```
is_exist(..., prefetch_to_memory=true)
  → triggerSsdPrefetch → prefetch_pool_ (size 4)
    → 128-key chunks: BatchQueryForPrefetch
      → ClassifySsdPrefetchRoute (SSD-only, size>0)
        → local: RegisterPrefetchTask + PrefetchKeys
        → remote: prefetch_offload_object → holder runLocalPrefetch
```

`PrefetchKeys` reuses only the promotion execution chain (`PromotionAllocStart`
→ `AllocateBatch` → `BatchLoad` → `PromotionWrite` → `NotifyPromotionSuccess`).
It does not reuse promotion-on-hit admission, sketch, lease-on-query, metrics,
or the heartbeat queue. Dedicated RPCs: `GetReplicaListForPrefetch` /
`BatchGetReplicaListForPrefetch` (read-only metadata) and `RegisterPrefetchTask`
(no admission enqueue). Reserve after BatchQuery confirms SSD-only.

## Throttle, threads, get-wait

`ssd_prefetch_dedup_ttl_sec` (default 30): same key once per window.
`ssd_prefetch_cooldown_sec` (default 5): backoff after DRAM saturation.
`submitPrefetchJob` uses a fixed `ThreadPool`; if the pool is down, drop the
task. Do not spawn a thread per probe.

`ssd_get_wait_ms` (default 10; `0` off) in `batch_get_into_multi_buffers_internal`:
local throttle wait if this process triggered prefetch, else poll master Query
until MEMORY appears or the budget ends. Then DRAM if present, else SSD read.

Config: `enable_ssd_offload`, `ssd_offload_path`, `enable_ssd_prefetch`, the two
throttle fields, `ssd_get_wait_ms`.

## Lease after promote

`NotifyPromotionSuccess` with `from_prefetch` grants the same hard/soft lease as
exist/get. Prefetch metadata RPCs grant no lease.
`MOONCAKE_SSD_PREFETCH_PROTECT_SEC` is unused. If exist→get exceeds the hard
lease, raise `--default_kv_lease_ttl`. Larger leases can raise Put
`NO_AVAILABLE_HANDLE` under a high DRAM watermark (capacity, not a prefetch bug).

## Offload commit order (independent)

`BatchOffload` commits `object_bucket_map_` before `NotifyOffloadSuccess`.
Notify fail: `RollbackCommittedBucket` + `CleanupOrphanedBucket`. Already in the
NEW tree. Not part of the prefetch path. Phase 4 does not change it.

## Code

`types.h` knobs. `real_client.*` throttle/pool/trigger/get-wait.
`master_service.*` prefetch RPCs + `from_prefetch` lease.
`master_client.*` / `rpc_service.*` / `client_service.*` RPC wiring.
`file_storage.*` `PrefetchKeys` (tenant-scoped staging keys).
`storage_backend.*` offload commit-before-notify (independent).
`store_c` / `pyclient` / `dummy_client` / `store_py` `ExistOptions.prefetch_to_memory`.
