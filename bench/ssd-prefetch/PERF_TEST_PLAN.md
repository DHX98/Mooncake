# Prefetch TTFT 收益验证方案（DSv4-Flash + vllm-ascend + A2，vllm bench 版）

目标：在 Ascend A2 上回答一个问题——**开 SSD offload vs 开 SSD offload +
prefetch，TTFT 降多少（%）**。驱动工具用 `vllm bench serve`（社区通用，
结果可直接贴进 RFC/PR），固定数据集文件保证 fill 和 measure 是同一批
prompt。

## 1. 原理（收益从哪来）

```
请求进入 → vLLM prefix cache lookup（batch_is_exist）
  → prefix 命中但只剩 SSD 副本
     A组（无 prefetch）：get 在关键路径上读 SSD → TTFT 含 SSD 读时间
     B组（prefetch）  ：exist 探测即触发 SSD→DRAM 异步提升，
                       调度/排队窗口内完成 → get 命中 DRAM
```

DSv4-Flash 是 MLA 架构，单 token KV 很小；更重要的是**当前实现的
prefix cache 命中粒度是 16K tokens——prefix 短于 16K 根本不会命中
缓存**。规则：**prefix 固定 16385**（一个完整 16K 可缓存块 + 1 token
尾部避免边界歧义；尾部重算可忽略）。不要用 32K：16K 块的 KV 已有
~GB 级，信号远超噪声，更长的 prefix 只会通过 max_model_len 多吃 HBM。
约束：`16385 ≤ max_model_len − suffix − output_len`。

## 2. 对照设计（唯一变量原则）

| | A 组 | B 组 |
|---|---|---|
| master | `enable_offload=true, offload_on_evict=true, promotion_on_hit=false, default_kv_lease_ttl=60000` | 同左（**逐字相同**） |
| client（connector 侧配置） | `enable_ssd_offload=true, ssd_offload_path=<NVMe dir>` | A 组 + `enable_ssd_prefetch=true, ssd_get_wait_ms=2000` |

**关键控制**：
- `promotion_on_hit=false` —— 否则 promotion-on-hit 会污染对照。
- lease TTL 调大到 60s —— 覆盖 exist→get 窗口，排除 lease 过期的假阴性。
- SSD 落在真实 NVMe（不要 tmpfs），否则 A/B 无差异。
- 两组用**同一个数据集文件、同一个 --seed**；fill/measure 也是同一文件。
- **measure 阶段用 `--max-concurrency 2`，不是串行**（v2 修正，见 §5.1）：
  串行时请求的 lookup（exist 探测）和 get 前后脚发生，probe→get 窗口≈0，
  prefetch 根本来不及完成。c=2 让请求 N+1 的探测/提升与请求 N 的 prefill
  （~5.5s）重叠——这正是 prefetch 设计要利用的排队窗口（RFC #3417 的核心
  前提）。fill 阶段仍串行。
- **DRAM 必须留出提升空间**（v2 修正）：store 总容量 ≥ fill 集 + overflow
  集 + 一份 fill 集的提升空间（约 3× 单组工作集）。否则 promotion 全部
  NO_AVAILABLE_HANDLE 失败并触发 cooldown 退让（机制按设计工作，但实验
  什么都测不到）。16MB segment 配置下 mem_cache 只有 ~26 个 key 就是
  太挤的信号。
- **ssd_get_wait_ms 要匹配 promotion 时长**：10ms 对 GB 级 promotion
  （秒级）毫无意义，B 组设 2000。

## 3. 前置检查（跑数前必做）

1. **connector 接入确认**：vllm-ascend 的 Mooncake connector lookup 路径
   调用 `batch_is_exist(keys, options)` 且 B 组时
   `options.prefetch_to_memory=true`。若未接入，B 组不会生效。
2. **SSD-only 确认**：fill + settle 后，通过 master admin HTTP
   （`query_key`）或 mooncake python client `batch_get_replica_desc`
   抽查若干 key，确认有 LOCAL_DISK 副本且无 MEMORY 副本。不满足则
   增大 `--num-prefixes` 或缩小 segment，重跑 fill。
3. **B 组生效确认**：client 启动日志出现 `SSD prefetch enabled`；
   measure 期间 master VLOG(1) 可见 `prefetch_task_registered`（可选）。

## 4. 测试流程

### 4.1 生成数据集（两组共用同一份）

```bash
python3 gen_dataset.py --num-prefixes 48 --prefix-tokens 16385 --seed 42
# 产出 prompts.jsonl（主用）和 prompts_sharegpt.json（旧版 vllm 兜底）
```

### 4.2 每组两轮 bench（fill + measure）

```bash
# ---- fill：同一数据集先跑一遍，填满并溢出 DRAM ----
vllm bench serve \
  --backend openai --base-url http://127.0.0.1:8000 \
  --model dsv4-flash \
  --dataset-name custom --dataset-path prompts.jsonl \
  --custom-skip-chat-template \
  --num-prompts 48 --max-concurrency 1 \
  --custom-output-len 8 \
  --seed 42 \
  --percentile-metrics ttft --metric-percentiles 50,90,99 \
  --save-result --result-filename fill.json

# ---- settle：等 offload 落盘 ----
sleep 30
# ---- SSD-only 前置检查（见 §3.2），不通过则调参重来 ----

# ---- measure round 1（c=2 制造 probe→get 排队窗口） ----
vllm bench serve ... （同上命令，但 --max-concurrency 2） --result-filename measure_r1.json
# ---- measure round 2（识别缓存污染） ----
vllm bench serve ... （同上） --result-filename measure_r2.json
```

旧版 vllm-ascend 若没有 `vllm bench` 子命令或 `--dataset-name custom`：
- 用 `python3 -m vllm.entrypoints...benchmark_serving`（或源码树
  `benchmarks/benchmark_serving.py`）；
- 数据集换 `--dataset-name sharegpt --dataset-path prompts_sharegpt.json`；
- 输出长度参数改为 `--sharegpt-output-len 8`；
- 没有 `--percentile-metrics` 就看默认输出的 mean/median/p99 TTFT。

### 4.3 汇总

bench 的 result json 里有 `mean_ttft_ms / median_ttft_ms / p99_ttft_ms`。
每组取 measure_r1 为主结论，r2 用于判断污染：

| | median TTFT (ms) | p99 TTFT (ms) | mean TTFT (ms) |
|---|---|---|---|
| A (offload only) | | | |
| B (+prefetch) | | | |
| **降幅** | **-%** | **-%** | **-%** |

## 5. 判读规则

### 5.1 v1 教训（2026-09-17 首轮结果，A/B 无差异 -0.6%）

首轮配置：c=1 串行、`ssd_get_wait_ms=10`、DRAM 紧张（16MB segment，
mem_cache 仅 ~26 key）。三个叠加根因，已反映在上面的 v2 配置里：

1. **无 probe→get 窗口**：串行下 lookup 与 get 背靠背，单请求 KV ~GB 级
   （MLA 61 层 × ~1.1KB/token × 16K tokens），promotion 需秒级，来不及。
2. **DRAM 饱和**：日志实测 NO_AVAILABLE_HANDLE（vllm.log + master.log），
   PromotionAllocStart 失败 → 5s cooldown 退让 → prefetch 大部分被丢弃。
3. **get_wait 10ms** 对秒级 promotion 无意义，get 直接回落 SSD。

**每次 measure 必须同时采集这些证据**，否则无法区分"没收益"和"没生效"：
- master.log: `prefetch_task_registered` 计数（measure 期间应 ≈ fill
  keys 数；为 0 说明 prefetch 根本没跑起来）；
- client log: `DRAM saturated, backing off` 次数（应 ≈ 0）；
- measure 后抽查 fill keys 应重新有 MEMORY 副本；
- SsdMetric: `prefetch_complete_total` / `prefetch_fail_total`；
- NO_AVAILABLE_HANDLE 出现次数（应 ≈ 0；多则说明 DRAM 仍不足）。

### 5.2 判读

- **主结论看 r1（c=2）的中位数**。第 1 个请求无排队窗口、无收益属正常，
  median 已将其稀释。A 组 r1/r2 应基本持平（promotion-on-hit 关闭，
  SSD 读不自我提升）；B 组 r2 ≥ r1 的收益属正常（r1 已把数据提回
  DRAM）。若 A 组 r2 明显变快，说明有意外 promote，检查 master 配置。
- **prefix 缓存根本没命中** → prefix 长度低于 16K 的命中粒度（本方案
  固定 16385=16K+1，不要调小；HBM 充裕时可加大但无收益）；suffix 尾部
  不命中属正常，不影响主体。
- **TTFT 没差异** → 大概率：prefix 没真落 SSD（§3.2）、connector 没传
  prefetch options（§3.1）、SSD 是 tmpfs。
- **B 组反而更慢** → 查 master 日志是否 NO_AVAILABLE_HANDLE 风暴（DRAM
  太满，prefetch 与 eviction 打架）。这本身是社区关心的数据点，如实记录。
- 可选压力抽查：`--max-concurrency 4` 跑一遍 measure（~5min），只看
  收益是否保持，不进主表。

## 6. 时间预算（A2，16K-token prefill ≈ 2~3s/请求）

| 阶段 | 估时 |
|---|---|
| fill（48 请求，串行） | ~4 min |
| settle + SSD-only 检查 | ~1 min |
| measure r1 + r2（c=2） | ~5 min（A 组偏慢） |
| **单组小计** | **≤12 min** |
| **A/B 两组 + 重启服务** | **~35 min** |
