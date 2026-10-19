# e2c: kick's first register does not run the promotion

Tree that produced the arm: `2fc4ebe2`. Store library md5
`a588165909244cc3c52d73b075514454`. Arm flags: prefetch on, `ssd_get_wait_ms`
500, `promotion_on_hit` true, threshold 2. No product change.

## What the 15-trial master metrics already showed

`master_e2c.log` is INFO level, so it has no `RegisterPrefetchTask` or
`PROMOTION_ALREADY_EXISTS` text. Those are VLOG(1), and the
`PROMOTION_ALREADY_EXISTS` skip in `RegisterAndPromote` is not logged at
all. The admin metrics are the record:

- e2a (kick, on_hit off): admitted 0, completed 15, rejected 0/0/0.
  Kick completions do not increment `admitted`. `RegisterPrefetchTask`
  only increments in-flight; `inc_promotion_admitted` is the on-hit
  queue path (`promotion_queued`).
- e2b (on_hit only, threshold 2): admitted 15, completed 2, cancelled 13,
  rejected freq/wm/cap 15/2/0.
- e2c (both): admitted 14, completed 2, cancelled 12, rejected 14/2/0.

e2c tracks e2b. The kick completion counter does not climb.

`cancelled` is `NotifyPromotionSuccess` with `committed=false`, not the
expiry counter. The on-hit task is admitted and then closed without a
MEMORY replica. Same pattern with kick absent.

## What a 2-trial v=1 rerun showed

Same binary, same flags, `TRIALS=2`, master `--v=1`, client `GLOG_v=1`.
Logs under `twotier-208/e2c-v1/`. Both trials: touch 1/2/3 stayed
`['LOCAL_DISK', 'DISK']`.

Trial 0, key `e2c_t0_target`, one get, two `BatchGetReplicaList` RPCs
0.4 ms apart:

```
01:51:05.289037 BatchGetReplicaList request keys_count=1
01:51:05.289103 BatchGetReplicaList response success=1 latency=67us
01:51:05.289489 BatchGetReplicaList request keys_count=1
01:51:05.289534 promotion_queued key=e2c_t0_target size=67108864
01:51:05.289548 BatchGetReplicaList response success=1 latency=58us
01:51:05.289619 client: SSD prefetch: get-side kick, disk_keys=1
01:51:05.289974 RegisterPrefetchTask request
01:51:05.290028 RegisterPrefetchTask response status=failed error=PROMOTION_ALREADY_EXISTS latency=21us
```

Trial 1 is the same pair at 01:51:21. `prefetch_task_registered` count is
0. `PrefetchKeys failed` count is 0. Six `get-side kick` lines (3 touches
times 2 trials) and only two `RegisterPrefetchTask` responses: touches 2
and 3 are inside the client dedup TTL, so they log the kick and do not
register again.

The first of those two replica-list RPCs is the eviction probe.
`replica_types` calls `batch_get_replica_desc`, which is `BatchQuery`,
which is the mutating `BatchGetReplicaList` (it grants a lease; the
harness comment already says so). With on_hit on and threshold 2, that
probe is frequency 1 and does not queue. The timed get is frequency 2.
`TryPushPromotionQueue` records `promotion_task` before the RPC returns.
The kick then calls `RegisterPrefetchTask`, which returns
`PROMOTION_ALREADY_EXISTS` when `promotion_task` is already set, and
`RegisterAndPromote` `continue`s without `PrefetchKeys`.

On e2a, on_hit is off, so `TryPushPromotionQueue` returns before the
sketch increment. The same get's kick registers and completes.

`master_service.cpp` is not in the `d11b41f8` diff. The gate is unchanged
on the tree that was just built.
