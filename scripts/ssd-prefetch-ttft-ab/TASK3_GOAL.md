# 任务 3：A/B 性能验证（统一协议，与 H20 clean-gate 同构）

**目标**：`ssd-prefetch/pr3-exist-get-wiring`（@ `0327ddcb`）上，
offload+prefetch vs 仅 offload 的 TTFT 增益（fill → overflow →
settle → measure）。

**方法学 = H20 clean-gate 那一套，逐条照搬**。参照实现与证据格式：
`evidence/h20-clean/`（CARD.md、gate 文件、configs）。本文件只列
协议项与平台差异，不再另行发明流程。

## 流程（与 H20 一致）

每臂：起 master+vLLM → fill（48 prefix，c=1）→ overflow（48 个新
prefix）→ settle 90s → **前提闸门** → **FILE_READ_FAIL 闸门** →
measure r1/r2（c=4）→ 停。A 臂 prefetch OFF，B 臂 ON，其余配置逐字
相同；两臂各用全新 SSD 目录。

## 旋钮（与 H20 相同）

`PREFIX_TOKENS=16385` · `NUM_PREFIXES=48` · `OVERFLOW=48` ·
`FILL_C=1` · `MEASURE_C=4` · `MAX_NUM_SEQS=4` · `SETTLE=90` ·
`SEGMENT=256MB` · `SSD_GET_WAIT_MS=2000` · `promotion_on_hit=false` ·
`GLOG_v=0`（measure 期间）。

## 闸门（与 H20 相同，全部必过）

1. **前提闸门**：settle 后、measure 前，抽查 fill keys 必须采到
   LOCAL_DISK-only（无 MEMORY）副本；不通过 → 作废，不进 measure。
2. **FILE_READ_FAIL 闸门**：每次 measure 前 grep vllm + master 日志，
   必须 = 0。
3. **挂死处理**：bench successful 停滞 ~120s → 该次 measure 作废，
   ≤30s 的 `GLOG_v=1` 取证窗口后**同盘重测一次**；再挂 → 停轮贴日志。
   store.so 用 stock（被测分支原编），不换现场修版。

## 平台差异（只允许这些不同）

| 项 | A2 / Ascend | H20 / NVIDIA |
|---|---|---|
| 模型构建 | DSV4-Flash w8a8-mtp | NVIDIA FP8/BF16 构建 |
| connector | AscendStoreConnector | MooncakeStoreConnector（按部署核对） |
| 可见卡/网络 | ASCEND_RT_VISIBLE_DEVICES + HCCL_* | CUDA_VISIBLE_DEVICES + NCCL_* |
| TP | 8 | 8（按显存调） |
| mooncake protocol | ascend | tcp（或 rdma） |

## 产出（格式照 h20-clean/CARD.md）

- 两臂 r1/r2 TTFT 表（median/mean/p99）+ gain%（r1 为主）；
- fill/overflow 成功数（48/0）；
- 三个闸门的通过记录（含 grep 计数 = 0）；
- `prefetch_task_registered`、promotion completed/failed、cooldown
  次数、get-side kick 计数（B 臂）。

## 纪律

产品代码 dirty=0；证据先 `scrub.sh`；绝对毫秒只进内部证据；
作废与重测必须写理由；harness 错误 ≠ 产品失败，分开记。
