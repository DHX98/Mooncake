# B 臂测量窗口 VLOG（GLOG_vmodule）

代码 `98d9002face6aaf6dbda9df493a27710146347bd`。产品代码未改。
B 臂一次 serve 内完成 fill → overflow → settle → 闸门 → measure r1。master 中途没有重启。

环境：`GLOG_v=0`，`GLOG_vmodule=ssd_prefetcher=1,real_client=1`。
vLLM 进程 environ 里能看到这个 `GLOG_vmodule`。`c=2`，r1 为 48 条。

## 流程

| 步骤 | 结果 |
|---|---|
| fill | 48/0 |
| overflow | 48/0 |
| settle | 90s |
| 客户端闸门 | `GATE_PASS=0`，`probe_err`（无 NPU context 的 Ascend segment 分配失败，与上一份诊断相同） |
| HTTP 闸门 | `GATE_PASS=1`，LOCAL_DISK-only 54/64，MISSING=0 |
| FILE_READ_FAIL | vLLM 0，master 0 |
| r1 | 48/0 |

第一次 fill 被 harness 误判挂死（进度条已在走，脚本只认结束行 `Successful requests`）。作废后用认进度条的脚本重跑。上表是重跑。

## 测量窗口计数（只含 r1 开始之后新增的日志）

| 字符串 | vLLM | master |
|---|---:|---:|
| skipped (memory-pressure cooldown) | 0 | 0 |
| BatchQueryReadOnly | 0 | 0 |
| skip remote key | 0 | 0 |
| delegating | 2970 | 0 |
| RegisterPrefetchTask failed | 1920 | 0 |
| get-side kick | 384 | 0 |
| DRAM saturated | 0 | 0 |

`BatchQueryReadOnly` 只在返回长度不匹配时打 WARNING。计数 0 表示没有 mismatch，不表示没调用。

抽到的 `RegisterPrefetchTask failed` 样例全部是 `error=REPLICA_IS_NOT_READY`（`ssd_prefetcher.cpp:89`）。抽到的 `get-side kick` 样例全部是 `disk_keys=40, in_cooldown=0`（`real_client.cpp:7411`）。`delegating` 样例是把若干 key 委派给远端 holder（`ssd_prefetcher.cpp:259`）。

```text
SSD prefetch: delegating 3 key(s) to remote holder <host-ip>:<port>
SSD prefetch: RegisterPrefetchTask failed for key=<kv-key>, error=REPLICA_IS_NOT_READY
SSD prefetch: get-side kick, disk_keys=40, in_cooldown=0
```

没有 `DRAM saturated`，没有 memory-pressure cooldown，没有 `skip remote key`。

## SSD 读指标

master `:9021/metrics` 里没有 `ssd_read` / `mooncake_ssd_read_*`。这些计数在 client 的 `SSD Read:` 行上。测量窗口内 vLLM 和 master 日志都没有 `SSD Read:` 行，所以拿不到 ops/bytes 的数字增量。

同一窗口 master 管理指标：

| | before r1 | after r1 |
|---|---|---|
| Mem | 1.12 GB / 2.00 GB (55.8%) | 同左 |
| SSD Storage | 21.06 GB / 18.00 TB | 同左 |
| Promotion admitted/completed/failed | 0/0/0 | 0/0/0 |

窗口里有 384 次 get-side kick 和 2970 次 delegating，说明 measure 走到了 prefetch 代码。不能从「master 上没有 ssd_read 序列」推出「没走 store 读路径」：这个序列不在 master 上。client 的 `SSD Read:` 在窗口内没刷出来，增量未知。

## test_prefetch_on_exist.py（先设 NPU context）

`import torch, torch_npu; torch.npu.set_device(0)` 之后再 `store.setup`。setup 不再返回 -1，两个测试都跑了。`Ran 2 tests`，`FAILED (failures=2)`。

- `test_exist_with_prefetch_promotes_ssd_only_key`：25s 内没有 LOCAL_DISK-only key。最后直方图 `DISK,LOCAL_DISK,MEMORY=30`，`DISK,MEMORY=2`。对象仍带着 MEMORY。
- `test_exist_without_prefetch_does_not_promote`：`No PUTs succeeded`。

这和上次「裸进程没有 device context」不是同一个失败。
