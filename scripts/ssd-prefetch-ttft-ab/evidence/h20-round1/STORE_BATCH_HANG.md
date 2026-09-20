# H20：overflow 后 SSD GET 批等待（store，不是 prefetch）

日期：2026-09-20。机：H20 `<host-ip>`，容器 `<bench-container>`。
被测代码：`ssd-prefetch/pr3-exist-get-wiring` @ `eabc511f`。
Harness：本目录脚本，`PLATFORM=h20`，`MEASURE_CONCURRENCY=4`，`MAX_NUM_SEQS=4`。

**这段不在即将合入的 prefetch commit 里。** `kvcache-ai/Mooncake` main 上
`transfer_task.cpp` 仍是同一套 wait-all。现场为了收尾 measure，在 box 上
只重编过 `store.so`；`engine.so` 未动（md5 `275b0687e217c9013f527e3e5faf980a`）。

编译 PR、跑单测、exist 升档 gate **不会**走到这里。
复现要跑官方 fill → overflow → settle → measure c=4，并且 SSD GET 真的读失败。

## 现象

overflow 之后，measure 前几十条能回来，最后停在 45/48、47/48，bench 720s 超时。
serve 还活着，`/v1/models` 正常，GPU 占满。`batch_get_into_multi_buffers` 不返回，
vLLM `kv_load_failure_policy=recompute` 拿不到 `invalid_block_ids`。

两层：

1. **`FILE_READ_FAIL`**：SSD offload GET 读对象失败。
   `file_storage.cpp` → `real_client.cpp` `SSD read failed` /
   `Batch get offload object failed`。现场还看到
   `storage_backend.cpp` **`Read size mismatch`**（读出来的长度和对象对不上）。
2. **批不收尾**：同一 batch 里已有 task `FAILED`，其余一直 `PENDING`。
   主干 `check_task_status` 故意等全部到终态才 `set_result`（怕析构
   `freeBatchID` 踩还在飞的 transfer）。有人一直 PENDING，就空转到 60s。
   `FilereadOperationState::wait_for_completion` 是无限 `cv_.wait`。
   默认 poll **无 sleep**。`run_verify.sh` 钉了 `GLOG_v=1`，每圈
   `VLOG(1) still pending` 把 `vllm.log` 打到约 111G，盘 100%。

prefetch 开关不决定这两层。A 臂 `enable_ssd_prefetch: false` 同样
`FILE_READ_FAIL`，同样卡 measure。

## 怎么触发

和 `run_verify.sh` / 官方 H20 A/B 同一条路：

1. `enable_ssd_offload=true`，`global_segment_size=256MB`，DRAM 很快满。
2. fill 48 → overflow 48。KV 在盘上，lookup 仍报存在。
3. settle 90s，measure `c=4` / `max-num-seqs=4`，`batch_get` 从 SSD 读。
4. 部分 key 短读 / 读失败 → `FILE_READ_FAIL`；同批兄弟停在 PENDING。
5. client `GLOG_v=1` 时 pending 日志爆炸。

A/B 都开 SSD offload。B 只多 `ExistOptions.prefetch_to_memory`。
GET-from-SSD 是 offload 老路径。

只 `cmake && ctest`、只跑 exist `LOCAL_DISK→MEMORY` gate，走不到。
没有 `FILE_READ_FAIL` 时，旧 `store.so` 也能把 leftover r1 跑到 48/48。

## 和 prefetch PR 的关系

| 问题 | 是这条 PR 引入的吗 |
|---|---|
| exist 上 SSD→DRAM promotion | 是，这就是功能 |
| `FILE_READ_FAIL` / Read size mismatch | 否。A 臂 prefetch OFF 一样有 |
| FAILED+PENDING 等到 60s / Fileread 无限等 | 否。main 现网语义 |
| 111G pending 日志 | 否。`GLOG_v=1` × tight poll × `VLOG(1)` |

更早的主干曾经 fail-fast（有失败立刻 `TRANSFER_FAIL`）。现在 main 改成
wait-all。[#2478](https://github.com/kvcache-ai/Mooncake/pull/2478) 想给
poll 加 backoff，**关掉未合**（延迟）。event-driven completion 宏默认 OFF。

## 主干代码（PR 树 = main，2026-09-20 核对）

`mooncake-store/src/transfer_task.cpp` `check_task_status`：

```
// Wait for ALL tasks to reach a terminal state before setting the result,
// even if some have already failed. This prevents the caller from seeing
// "completed" while background transfers are still in progress, which
// could cause issues when freeBatchID is called in the destructor.

if (!all_terminated) {
    // Do NOT set result yet, even if some tasks have already failed.
    return;
}
```

`wait_for_completion`：`timeout_milliseconds = 60 * 1000`，poll 圈打
`still pending`，无 sleep。

`include/transfer_task.h` `FilereadOperationState`：

```
cv_.wait(lock, [this] { return result_.has_value(); });
```

无超时。

## 现场证据（2026-09-20，CST）

摘录：`store-batch-hang/`。过线数字：`CARD.md` / `greps.txt`。
A 臂配置：`configs/mooncake_a.json`（`enable_ssd_prefetch: false`）。

先排除另一件事：首轮官方 A/B r1 **0/48** 是 vLLM 0.23 hybrid
`get_block_ids` 解包把 EngineCore 打崩，不是本文件这条路径。

| 时刻 | 臂 | store.so | 结果 | 计数 |
|---|---|---|---|---|
| leftover ~17:56 | B | 旧（未打 fail-fast） | r1 48/48 | 无 FILE_READ 时 batch GET 能结束 |
| 18:14 / 18:16 | B | 旧 | fill/overflow 48/48 | serve 能起，灌盘正常 |
| 18:17–18:41 | B 全量 refill | 旧 | r1/r2 bench 720s 超时 | 卡在尾巴请求 |
| 19:07 | B | 旧 | 挂死 | `FILE_READ_FAIL=1006`，`still pending=31222`，`vllm.log=118969908733`（约 111G），盘 100%（33G），SSD 文件 10691 |
| 19:22 | — | **只重编 store.so** | — | engine.so 未动 |
| 19:29 | B | 现场 so | r2 仍 47/48 | `FILE_READ_FAIL=1110`，`Failed to get=16`，出现 `Read size mismatch`；pending 日志已停 |
| 随后 | B | 现场 so + connector `batch_remove` 失败 key | r1/r2 48/48 | `.bpass` |
| 20:03–20:16 | **A** prefetch OFF | 现场 so | r1/r2 超时 | `FILE_READ_FAIL=2875`，`DROPPED=38`，`PENDING=0` |
| 20:29 | A | 现场 so | r2 47/48 | `FILE_READ_FAIL=921`，dropped 16 |
| attempt2 同盘重启 | A | 现场 so | r1/r2 48/48 | 截断后的 log：`FILE_READ_FAIL=616`，`PENDING=0`，`DROPPED=8` |

过线那轮（attempt2 / `.bpass`）仍有 SSD 读失败，只是 GET 能返回，recompute 接得住。

日志形态（已 scrub）：

```
E0920 file_storage.cpp:1111] Batch load object failed,err_code = FILE_READ_FAIL
E0920 file_storage.cpp:251] Batch load object failed,err_code = FILE_READ_FAIL
E0920 real_client.cpp:7320] Batch get offload object failed,err_code = FILE_READ_FAIL
E0920 real_client.cpp:6830] SSD read failed for key 'DeepSeek-V4-Flash@tp_rank:0@...': FILE_READ_FAIL
E0920 storage_backend.cpp:1859] Read size mismatch for key: default?DeepSeek-V4-Flash@...
```

`FILE_READ_FAIL` 的 errno 没打出来。能确定的最近因是 **SSD 对象短读**。
当时盘满 + 111G 日志是加重因素，不是 prefetch。

## 修复方案（给上游，单独 store issue）

不要把现场三刀塞进 prefetch PR。那是权宜，而且和 main「等全部终态再
`freeBatchID`」对着干。

### 1. 让失败的 batch 能到终态（挂死本身）

wait-all 可以留。缺的是：一个 task 已经 `FAILED` 时，把还在
`PENDING`/`WAITING` 的兄弟 **cancel 或标 FAILED**，再 `set_result`。
这样析构时没有在飞的 transfer，调用方也能在秒级拿到 `TRANSFER_FAIL`。

不要：看见一个 FAILED 就 `set_result` 并 `freeBatchID`（现场做过，能收尾，
和当前 main 注释冲突）。

`FilereadOperationState` 给 `wait` 加超时，和 TE 的 60s 对齐或做成配置。
现在无限等，worker 若没 `set_completed`，GET 永远不回。

### 2. 先把 `FILE_READ_FAIL` 变成可诊断错误

`file_storage.cpp` / `storage_backend.cpp` 打出：path、errno、expected size、
actual size、file 是否还在。现场已有 `Read size mismatch`，要对 overflow
并发读、evict 半截文件、盘满（ENOSPC）分开计数。

### 3. 日志和 harness

`still pending` 不要每圈 `VLOG(1)`。复现 A/B 把 `GLOG_v` 降到 0
（`run_verify.sh` 现在写死 1）。#2478 式 poll sleep 被拒过；
若继续默认 busy-poll，至少别打每圈 pending。

### 4. 调用方（vLLM，不进 Mooncake）

connector 已有 `value<0` → `invalid_block` → recompute。C++ 不返回时这条是死的。
现场加过 8s GET 超时和 `batch_remove` 失败 key，属于 vLLM connector，
不要放进 Mooncake prefetch PR。

DSV4-Flash + vLLM 0.23 hybrid 的 `get_block_ids` 解包是另一处 vLLM bug，
首轮 0/48 走那条，不要和本 hang 混在一个 issue。

## 现场权宜（已发生，不提交源码）

box 上改了 `transfer_task.cpp` / `transfer_task.h`，只重编覆盖 `store.so`：

- 一批已有 FAILED、别的还 PENDING 时立刻 `TRANSFER_FAIL`
- 等待 60s → 3s
- poll 加 5ms sleep
- Fileread 无限等 → 3s

3s / 5ms 是收尾参数，不是给 main 的方案。

## Maintainer 怎么用这份 PR

1. 编这份 prefetch PR，exist 升档和 happy-path GET 可用。
2. 按 `run_verify.sh` 或 H20 官方 A/B 压 overflow+c=4 时，A/B 都可能
   在尾巴请求上碰到本文件。先降 `GLOG_v`，看是否出现 `FILE_READ_FAIL` /
   `Read size mismatch` / `still pending`。
3. 功能 review 不要绑定这条 store 修复。另开 store issue，带本目录摘录。
