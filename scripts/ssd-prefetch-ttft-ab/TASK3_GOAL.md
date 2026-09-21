# 任务 3：A/B 性能验证（目标制）

**回答一个问题**：在 `ssd-prefetch/pr3-exist-get-wiring`（@ `0327ddcb`）上，
开 prefetch 相比只开 SSD offload，prefix 命中 SSD-only 数据时 TTFT 是否
显著改善。

代码与参考：
- 被测库：上述分支构建（v3-verify 的 harness 仅作参考，可用可改，
  路径 `scripts/ssd-prefetch-ttft-ab/`）。

## 指引（非规定）

1. **核心前提**：measure 时被测 key 必须在 SSD 上（LOCAL_DISK-only，
   不在 DRAM）。造这个状态的方法（fill/overflow/segment/lease/等待）
   由你定；measure 前验证前提真的成立并留档证据。前提不成立的数据
   无效。
2. A/B 两臂除 prefetch 开关外，其余配置一致。
3. 已知翻车点（仅供参考，不必照抄参数）：串行无排队窗口；lease 过长
   导致驱逐不动；SSD 层读失败（FILE_READ_FAIL）；n 太小时 p99 是
   单请求统计。
4. **异常先归因再动手**：产品 bug / 环境问题 / harness 工具错误，
   三类分开写。harness 错误不得记成产品失败，也不许为数字好看绕过
   异常。重试与作废由你判断并记录理由。
5. 主数字：两臂 r1 的 median/mean/p99 + gain%，附
   prefetch_task_registered、promotion completed/failed、cooldown 次数。
   r2 作参照。

## 合格标准

证据链完整：前提已验证 + 两臂同配置 + 归因清晰。数字大小不重要，
可信最重要。

## 纪律

不改产品代码（dirty = 0）；提交证据前 `scrub.sh`；绝对毫秒数只进
内部证据，对外只报百分比。
