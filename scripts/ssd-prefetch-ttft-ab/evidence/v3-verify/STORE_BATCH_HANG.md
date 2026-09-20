# overflow 后 SSD GET 批等待（H20，2026-09-20）

全文和摘录：`../h20-round1/STORE_BATCH_HANG.md`、
`../h20-round1/store-batch-hang/`。

141 上那轮 c=4 过线**没有**改 Mooncake C++。H20 官方 A/B 在 overflow 之后
撞上了 **main 已有的** store 批等待。prefetch PR 没带上这段修复。

## 现象

measure 卡在 45/48、47/48。`FILE_READ_FAIL`（现场有 `Read size mismatch`）
之后，同批其它 task 一直 PENDING。主干要等全部终态才返回（`freeBatchID`），
于是空转到 60s。`FilereadOperationState` 无限等。`GLOG_v=1` 把
`still pending` 打到约 111G。

A 臂 `enable_ssd_prefetch: false` 同样发生（`FILE_READ_FAIL=2875`）。
不是 exist prefetch 引入的。

只编译 PR / 跑单测 / exist 升档 **不会**触发。
复现：`run_verify.sh` 或 H20 官方 fill→overflow→measure c=4，且 SSD 读真失败。

## 上游怎么修（单独 store issue）

1. 一个 task FAILED 时，把还在 PENDING 的兄弟 cancel/标失败，再 `set_result`。
   保留 wait-all，不要提前 `freeBatchID`。
2. Fileread wait 加超时。
3. `FILE_READ_FAIL` 打出 errno / expected / actual size。
4. 不要每圈 `VLOG(1) still pending`；复现时 `GLOG_v=0`。

现场在 box 上做过立刻 fail-fast + 3s + 5ms sleep，只重编 `store.so`。
那是权宜，**不要合进 prefetch PR**（和 main 的 wait-all 注释冲突）。

过线数字仍在 `../h20-round1/CARD.md`。那轮用的是现场 so，不是 PR 树原样。
