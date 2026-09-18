# v3-verify 验证交接单（内网测试 agent）

分支：`ssd-prefetch/v3-verify`（= v2 折叠代码 + get-kick 打点 +
`scripts/ssd-prefetch-ttft-ab/` 回放脚本与 v3 证据）

目标：用**一轮测试**同时完成 (a) c=4 数据补测、(b) 判定 get-kick /
`ignore_cooldown` 是否真正起过作用（决定上游 PR 是否保留该行为）。

## 阶段 0：零成本日志考古（先做，不用跑测试）

v3（2026-09-17 那轮）的 master.log / vllm.log 还在的话，先 grep：

```bash
grep -c "DRAM saturated, backing off" <v3 logs>
grep -c "memory-pressure cooldown"   <v3 logs>
grep -c "prefetch_task_registered"   <v3 master.log>
```

判读：
- `prefetch_task_registered` ≈ 166 → exist 触发链路在 v3 是工作的（预期如此）。
- 前两项 = 0 → cooldown 在 v3 从未开启 → `ignore_cooldown` 从未被行使，
  上游直接删除该 flag（决策已预定，见阶段 2）。
- 前两项 > 0 → 阶段 1 的打点结果决定 flag 去留。

## 阶段 1：一轮 v3-verify 测试（含 c=4）

用 `scripts/ssd-prefetch-ttft-ab/run_ab.sh` 原流程，**两处变化**：

1. 日志级别：master 和 vllm 都用 `GLOG_v=1`（或等效方式）启动，确保
   `VLOG(1)` 可见；
2. measure 阶段并发：`--max-concurrency 4`（bench.sh 的 `CONC=4`）。

跑完后收集：

| 证据 | 命令 | 预期 / 判读 |
|---|---|---|
| get-kick 次数 | `grep -c "get-side kick" logs/vllm.log` | > 0 即证明 get-kick 执行过 |
| **关键判定** | `grep "get-side kick" logs/vllm.log \| grep -c "in_cooldown=true"` | **> 0 → 保留 ignore_cooldown；= 0 → 上游删除** |
| cooldown 开启次数 | `grep -c "DRAM saturated, backing off" logs/*.log` | 应 ≈ 0（DRAM 余量已修） |
| 注册数 | `grep -c "prefetch_task_registered" logs/master.log` | ≈ fill keys 数 |
| 失败 vs 完成 | SsdMetric `prefetch_complete_total` / `prefetch_fail_total` | fail 应远小于 complete |
| TTFT 表 | bench result json × 4（A/B × r1/r2） | c=4 主结论：median/p99 降幅 |

## 阶段 2：回填格式

1. 阶段 0 的三个 grep 计数；
2. 阶段 1 的六项证据（数值）；
3. c=4 TTFT 对比表（A/B × median/mean/p99 + gain%）；
4. 异常时的 master/client 日志关键段。

## 注意

- 两组（A/B）之间必须重启 master + vllm 并清空本实验 SSD 目录
  （脚本已内置保护，不会动 ssd_dsv4 / ssd_8b / 2646 的盘）。
- 打点日志是 `VLOG(1)`，不开 v=1 看不到，但不影响功能；
  忘了开也能用 SsdMetric 计数器兜底判断。
- 这轮同时是 c=4 数据轮，**TTFT 表和 kick 判定同等重要**，别只交一个。
