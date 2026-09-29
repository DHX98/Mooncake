# settle=700：B 臂单跑

代码 `98d9002face6aaf6dbda9df493a27710146347bd`，dirty=0。产品代码未改。只把 settle 从 90s/300s 改成 700s，越过默认 `put_start_release_timeout_sec=600`。`GLOG_v=0`，`GLOG_vmodule=ssd_prefetcher=1,real_client=1`。master 中途未重启。只跑 B 臂（prefetch 开）。

流程：fill 48/0 → overflow 48/0 → settle 700s → HTTP 闸门 → measure r1 c=2。

## 任务 1 结论

判读 ①。测量窗口里 `RegisterPrefetchTask failed` 从上一轮的 1920 变成 **0**。同一窗口 master 的 Promotion `completed` 从 r1 前的 0 变成 **1920**，`failed=0`，`bytes=5.35 GB`。1920 仍等于 48 prefix × 40 个 SSD-only key。

r1 前（settle 已满 700s、measure 还没开始）Promotion 全 0，PutStart/PutEnd 速率 0.00。promotion 是在 r1 里做完的，不是 settle 期间做完的。和「600s reaper 把卡在 `processing_keys` 里的 Put 放掉，之后 RegisterPrefetchTask 才能成功」一致。

日志里没有名为 `Promotion completed` 或 `prefetch_task_registered` 的行（两处都是 0）。完成数来自 master admin 指标，不是那两句 INFO。

## 任务 1 证据

| | settle 90s | settle 300s | settle 700s |
|---|---:|---:|---:|
| RegisterPrefetchTask failed | 1920 | 1920 | 0 |
| 其中 REPLICA_IS_NOT_READY | 1920 | 1920 | 0 |
| distinct key | 1920 | 1920 | 0 |
| delegating 行 | 2959 | 2971 | 652 |
| get-side kick | 384 | 384 | 0 |
| DRAM saturated | 0 | 0 | 0 |
| Promotion completed（r1 前 → r1 后） | 0 | 0 | 0 → 1920 |
| Promotion failed | 0 | 0 | 0 |

测量窗口原文：

```
fail_lines=0
distinct_keys=0
keys_once=0
keys_multi=0
max_repeats=0
errors={}
COUNT delegating = 652
COUNT RegisterPrefetchTask failed = 0
COUNT get-side kick = 0
COUNT DRAM saturated = 0
```

delegating 样例（host 已抹掉）：

```
SSD prefetch: delegating 4 key(s) to remote holder <host-ip>:<port>
```

r1 前：

```
Promotion: in_flight=0, admitted=0, completed=0, failed=0, cancelled=0, expired=0, bytes=0 B
PutStart=0.00/0.00, PutEnd=0.00/0.00
```

r1 后：

```
Promotion: in_flight=0, admitted=0, completed=1920, failed=0, cancelled=0, expired=0, bytes=5.35 GB, rejected(freq/wm/cap)=0/0/0
PutStart=0.00/0.00, PutEnd=0.00/0.00
SSD Storage: 10.70 GB
Mem Storage: 1.05 GB / 2.00 GB (52.6%)
```

窗口内抽到的 admin 行，PutStart/PutEnd 都是 0.00。

HTTP 闸门：抽 64 个 fill key，`LOCAL_DISK-only=55`，`MISSING=0`，`GATE_PASS=1`，`HTTP_GATE_RC=0`。client 侧探针仍报 Ascend context 为空（`LOCAL_DISK-only=0`），脚本没有拿它当闸门。

本轮没有重跑 A 臂。B 臂 r1（48/0）：median 1220.78 ms，mean 1293.58 ms，p99 2214.90 ms。上一轮同协议 B 臂 r1（settle 90s，prefetch 未执行）：median 1507.70，mean 1466.80，p99 2361.33。A 臂那轮是 median 1511.47，mean 1468.26，p99 2391.86。

## 任务 2 结论

上一轮（b8177d40 那轮）留存的 master 日志里，下面 4 个串都是 0。没有样例行。

搜过：当时的 `master.log`（s300）、`master.log.s300.bak`、`master.log.vlog_b_*`、`master.log.pre_vlog_b_*`，以及更早的 `before_a` / `before_b`。每一份都是：

```
COUNT[settle_primary_write]=0
COUNT[tenant quota]=0
COUNT[LogTenantQuotaLedgerError]=0
COUNT[was removed while in processing]=0
```

## 任务 3 结论

上一轮 master 没有打开 `--enable_multi_tenants`。`serve.sh` 的 argv 是：

```
mooncake_master --rpc_port --metrics_port --enable_offload=true --offload_on_evict=true --promotion_on_hit=false --default_kv_lease_ttl=2000 --root_fs_dir --eviction_high_watermark_ratio=0.6 --eviction_ratio=0.4 --memory_allocator=offset --logtostderr=true
```

代码默认 `enable_multi_tenants=false`。启动 banner 没有这个开关，但有：

```
put_start_discard_timeout_sec=30, put_start_release_timeout_sec=600, enable_offload=1, offload_on_evict=1, enable_ha=0
```

quota settle 把 key 永久卡死，只在 multi-tenant 打开时才走得到。这次启动方式走不到。

## 任务 4 结论

容器里正在用的 runtime `mooncake_backend.py`（不是镜像里的旧文件）：

- `create_scheduler_client` 固定 `contribute_memory=False`。`global_segment_size` 和 `local_buffer_size` 在这条路径上是 0。scheduler 只用这个 client。
- scheduler 的 store 调用是 `batch_is_exist` 和 `batch_get_key_info`。没有 `put` / `upsert` / `put_from`。
- `put()` 只有一处，里面是 `batch_put_from_multi_buffers`。调用点在 worker 的 KV 发送线程和按层保存线程。那两个进程贡献显存，不是 segment=0 的 EngineCore。
- per-rank SSD 目录只在 `_contribute_memory` 为真时创建。镜像里的旧文件还会在 scheduler client 上把 SSD 参数清掉；正在跑的这份没有这句，但 scheduler 的调用点仍然没有写 API。

segment=0 的 EngineCore/scheduler 上没找到 PutStart 路径。

```python
def create_scheduler_client(cls, parallel_config: ParallelConfig):
    torch.npu.set_device(0)
    return cls(parallel_config, contribute_memory=False)
```

```python
"global_segment_size": self.config.global_segment_size if self._contribute_memory else 0,
```

```python
def exists(self, keys: list[str]) -> list[int]:
    if self._ssd_prefetch_enabled and self._exist_prefetch_options is not None:
        return self.store.batch_is_exist(keys, self._exist_prefetch_options)
    return self.store.batch_is_exist(keys)

def put(self, keys, addrs, sizes):
    res = self.store.batch_put_from_multi_buffers(keys, addrs, sizes, config)
```

worker 侧两处 `self.m_store.put(...)`：发送线程，以及按层保存里 `if keys_to_put: self.m_store.put(...)`。
