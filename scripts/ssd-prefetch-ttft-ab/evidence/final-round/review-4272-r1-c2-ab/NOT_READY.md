# REPLICA_IS_NOT_READY：D 还是 F

代码 `98d9002face6aaf6dbda9df493a27710146347bd`。产品代码未改。
`RegisterPrefetchTask` 里两条都会返回 `REPLICA_IS_NOT_READY`：

- D：`InProcessing()`，key 上还有未完成的 Put/Upsert。
- F：没有 COMPLETE 的 LOCAL_DISK 源副本。

admin `GET /batch_query_keys` 走 `GetReadableReplicaDescriptors`，只收 `is_completed()` 的副本。响应里的 `local_disk_values` 就是 COMPLETE 的 LOCAL_DISK。没有单独的 status 字段；PROCESSING 副本不会出现在这个列表里。

## 现场副本

settle 90s 和 300s 两轮，都是在 worker 打出 `RegisterPrefetchTask failed ... REPLICA_IS_NOT_READY` 之后立刻查该 key。各抽 6 个，形状相同：

| 字段 | 值 |
|---|---|
| ok | true |
| values（MEMORY） | 空 |
| disk_values | null |
| local_disk_values | 恰好 1 条，object_size 为 3101952 或 2621440 |
| nof_values | null |

有 COMPLETE 的 LOCAL_DISK，所以当时不是「没有可读的 LOCAL_DISK」。F 对不上这 12 个样本。和代码里先检查 `InProcessing()` 的顺序一起看，失败落在 D。

查询在日志行之后，不在 master 那把锁里。12 个样本一致，不像是查的时候 offload 刚翻成 COMPLETE。

## 广度

两轮测量窗口都是：

| | settle 90s | settle 300s |
|---|---:|---:|
| RegisterPrefetchTask failed | 1920 | 1920 |
| 其中 REPLICA_IS_NOT_READY | 1920 | 1920 |
| distinct key | 1920 | 1920 |
| 同一 key 重复失败 | 0 | 0 |

1920 个不同 key，每个一次。不是少数卡死 key。

同一窗口还有 delegating（90s 为 2959，300s 为 2971）和 get-side kick 384。`DRAM saturated`、memory-pressure cooldown、`skip remote key` 都是 0。

## put 计数

master 给出的是每秒速率，不是累计值。r1 前和 r1 后的快照，以及窗口内抽到的 admin 行，单次和 batch 的 `PutStart` / `PutEnd` 都是 0.00。r1 进行时 ExistKey 和 Get 非 0，Put 仍是 0。

测量窗口里没有「put_start 还在涨、put_end 跟不上」的速率差。Put 在 r1 之前已经停了。

## 长 settle

协议相同，只把 settle 从 90s 改成 300s，再单跑 B 臂。`REPLICA_IS_NOT_READY` 仍是 1920 / 1920 distinct。副本形状不变。

不是再等几分钟就能翻完的时序。至少在 overflow 之后 300s，这些 key 仍会让 `RegisterPrefetchTask` 走 D 那条 `InProcessing()` 返回。
