# B 臂 prefetch 零触发诊断（不改代码）

被测库 `ssd-prefetch/review-4272-r1` @ `98d9002face6aaf6dbda9df493a27710146347bd`。
c=2 A/B 见同目录 `CARD.md`。本文件只记录零触发排查。产品代码未改。

结论：worker 里的 prefetcher 已经建起来，connector 也声明把 `prefetch_to_memory=True` 传进了 `batch_is_exist`。测量日志和随后的 `GLOG_v=1` 探针里都没有投递、注册或 get-side kick。单独跑 `test_prefetch_on_exist.py` 在 `setup()` 就失败，没有执行到 exist。

## 1. 加载的 wheel

site-packages 里的 `libmooncake_store.so` md5 为 `33130c318dc1647ce3ef0c056514daf9`，与这次 `98d9002f` 安装记录一致。

`inspect.signature()` 对 pybind 内置方法报 `ValueError: no signature found for builtin`。`__doc__` 里的签名是：

```text
batch_is_exist(self, keys: list[str], options: ExistOptions = ...) -> list[int]
is_exist(self, key: str, options: ExistOptions = ...) -> int
setup(*args, **kwargs)  # 关键字重载，以及 setup(config: dict)
```

`ExistOptions.prefetch_to_memory` 存在。绑定层签名没有缺这个参数。

## 2. 闸门 `setup` 失败

不是 Python API 漂移。`ssd_gate` 用 dict 调 `setup()`，返回 `-1`，脚本再抛 `RuntimeError: store.setup ret=-1`。C++ 原文：

```text
Invalid_Argument(EE1001): rtGetDevMsg execution failed, the context is a null pointer
ctx is NULL
E ascend_direct_transport.cpp:127  AscendDirectTransport: cannot allocate local segment, ret: -1
E transfer_engine_impl.cpp:280     Failed to install Ascend transport
E client_service.cpp:822           Failed to initialize transfer engine, rc=-1
E client_service.cpp:1092          Failed to initialize transfer engine
W real_client.cpp:939              Failed to create client, retry 20/20
E real_client.cpp:947              Failed to create client after 20 retries
```

这是 `USE_ASCEND_DIRECT` 构建。闸门写了 `protocol=tcp`，传输层仍然去装 Ascend transport。闸门进程不在 vLLM worker 里，没有 device context，分不到 local segment。两臂都是这条路径，之后才用 HTTP `batch_query_keys` 把 LOCAL_DISK 闸门补上。它不能解释 B 臂 worker 里为什么没有 prefetch 投递：那些 worker 的 `setup` 是成功的。

## 3. connector

worker / EngineCore 日志里没有 `TypeError`，也没有 `batch_is_exist` 异常。

容器里有两份 `mooncake_backend.py`：

- 镜像里的 `vllm_ascend` 包。`exists()` 只调用 `batch_is_exist(keys)`，不传 `ExistOptions`。文件日期早于这次运行，且不含 `prefetch on exist enabled` 这句日志。
- `runtime/mooncake_backend.py`。`_resolve_ssd_prefetch()` 在 offload 与 prefetch 都打开、且 `ExistOptions` 可用时打 `Mooncake SSD prefetch on exist enabled.`（该文件第 352 行），`exists()` 改为 `batch_is_exist(keys, ExistOptions(prefetch_to_memory=True))`。

B 臂日志对上的是第二份：8 个 worker 加 EngineCore，这句各出现 9 次（`GLOG_v=0` 的测量进程，以及后来的 `GLOG_v=1` 重启）。

## 4. prefetcher 已初始化

B 臂每个 worker 都有 INFO：

```text
ssd_prefetcher.cpp:134  SSD prefetch runtime: pool_size=4, ssd_get_wait_ms=2000
real_client.cpp:1252    SSD prefetch enabled: ssd_prefetch_cooldown_sec=5s, ssd_prefetch_dedup_ttl_sec=30s, ssd_get_wait_ms=2000ms
```

测量日志（`GLOG_v=0`）和 `GLOG_v=1` 探针日志里，下面这些计数都是 0：

| 字符串 | 测量日志 | v=1 探针 |
|---|---:|---:|
| PrefetchKeys | 0 | 0 |
| get-side kick | 0 | 0 |
| delegating | 0 | 0 |
| RegisterPrefetch | 0 | 0 |
| DRAM saturated | 0 | 0 |
| backing off | 0 | 0 |

测量期间 master 指标保持 `Promotion admitted=0, completed=0, failed=0`。`prefetch_task_registered` 行数是 0。`slot_exhaust` 是 0。

`GLOG_v=1` 的 8 条探针是 master 重启之后打的。exist 结果为假时，`isExist` / `batchIsExist` 不会调用 `TriggerPrefetch`。所以这 8 条不能证明测量窗口里也没有投递。测量窗口是 `GLOG_v=0`，远程 delegate 和 `RegisterPrefetchTask` 失败都是 `VLOG(1)`，本来就不会出现。`DRAM saturated` / `backing off` 是 INFO，测量窗口里也是 0。

`TriggerPrefetch` 里还有两条不打 INFO 的出口：replica 被判成已在 DRAM 时 `markAlreadyResident`；本进程被当成 holder 但 `LookupLocalObjectSize` 失败时 `markFailed`。远程 delegate 才打 `VLOG(1) SSD prefetch: delegating`。EngineCore 的 segment 是 0，代码注释写明只有真正持有 SSD 对象的进程可以 `RegisterPrefetchTask`，否则会留下 PROCESSING 的 MEMORY replica。

## 5. `test_prefetch_on_exist.py`

在 vLLM 容器里、用这份 wheel 跑分支上的测试。master 为同一 SHA，`--enable_offload=true --offload_on_evict=true --promotion_on_hit=false`。测试默认 `protocol=tcp`。

`setUpClass` 失败，`Ran 0 tests`，`TEST_RC=5`：

```text
test_prefetch_on_exist.py setup_store
RuntimeError: Failed to setup store client. Return code: -1
```

栈与第 2 节相同（`cannot allocate local segment`）。没有执行到 `is_exist(prefetch_to_memory=True)`。因此这次失败不能区分「connector 没把选项传下去」和「绑定层 exist 路径坏了」。第 1 节已经说明绑定签名在；第 3 节说明运行中的 connector 打了 enabled 日志。缺的是一次能过 `setup` 的 exist 行为测试。裸 Python 进程没有 NPU context，过不了 Ascend segment 分配。

## 给架构师

测量窗口里可以确定的是：prefetcher 初始化成功，运行中的 connector 走了带 `prefetch_to_memory=True` 的 `batch_is_exist`，但没有任何 INFO 级投递或 promotion 计数。不能从 `GLOG_v=0` 断定 `TriggerPrefetch` 完全没被调用。值得对一下的是：

- exist 查询落在 EngineCore（segment 0）还是 worker；segment 0 不能 `RegisterPrefetchTask`。
- 本进程 holder 分支上 `LookupLocalObjectSize` 失败会静默 `markFailed`。
- 已在 DRAM 的 key 静默 `markAlreadyResident`，exist 路径本身不知道 replica 层级。
- `GLOG_v=1` 探针重启了 master，exist 为假时不会投递，不能当作测量窗口的反证。
