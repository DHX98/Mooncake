# 性能测试交接单（内网测试 agent）

## 任务一句话

在 A2 + vllm-ascend + DSv4-Flash 环境，用 `vllm bench serve` 做 A/B 对比：
**SSD offload only vs SSD offload + prefetch**，输出 TTFT 降幅百分比。

## 输入物（都在本目录 `bench/ssd-prefetch/`）

本分支：`ssd-prefetch/perf-bench` @ https://github.com/DHX98/Mooncake

- `PERF_TEST_PLAN.md` — 完整方案（原理、判读规则、常见坑），先读
- `gen_dataset.py` — 数据集生成（确定性，A/B 共用同一文件）

被测代码分支（已含全部特性，基础测试已通过）：
`ssd-prefetch/all-in-one` @ 同一 fork。

## 执行步骤

### 0. 环境

- A2 节点，SSD offload 路径指向**真实 NVMe**（不要 tmpfs）
- vllm-ascend 起 DSv4-Flash，OpenAI 兼容服务（记 base-url，如
  http://127.0.0.1:8000）
- mooncake_master 独立部署

### 1. 生成数据集（两组共用）

```bash
python3 gen_dataset.py --num-prefixes 48 --prefix-tokens 32768 --seed 42
```

### 2. A 组（SSD offload only）

master:
```
mooncake_master --enable_offload=true --offload_on_evict=true \
  --promotion_on_hit=false --default_kv_lease_ttl=60000 \
  --root_fs_dir=/tmp/prefetch_bench
```

client/connector: `enable_ssd_offload=true`，`ssd_offload_path=<NVMe dir>`，
**不开** prefetch。

### 3. B 组（offload + prefetch）

master 配置与 A **逐字相同**；client 增加：
`enable_ssd_prefetch=true`、`ssd_get_wait_ms=10`。

### 4. 每组跑法（A、B 完全相同）

```bash
# fill
vllm bench serve --backend openai --base-url <url> --model dsv4-flash \
  --dataset-name custom --dataset-path prompts.jsonl \
  --custom-skip-chat-template \
  --num-prompts 48 --max-concurrency 1 --custom-output-len 8 \
  --seed 42 --percentile-metrics ttft --metric-percentiles 50,90,99 \
  --save-result --result-filename <arm>_fill.json

sleep 30
# 前置检查：抽查 key 为 LOCAL_DISK-only（plan §3.2）；B 组确认 client 日志
# 有 "SSD prefetch enabled"

# measure x2（命令同 fill，换 result 文件名）
... --result-filename <arm>_r1.json
... --result-filename <arm>_r2.json
```

旧版 vllm 没有 `vllm bench` / custom dataset 时的替代写法见 plan §4.2
（sharegpt 数据集 + benchmark_serving.py）。

### 5. 回填内容

1. 6 个 result json（A/B × fill/r1/r2）
2. TTFT 汇总表（median/p99/mean，两组，r1 为主）+ 降幅 %
3. 前置检查的证据：SSD-only 抽查截图/输出、B 组 `SSD prefetch enabled` 日志行
4. 异常时的 master/client 日志关键段（特别是 NO_AVAILABLE_HANDLE）

## 注意

- **prefix 长度固定 32K tokens，不要调小**：当前实现 prefix cache 的
  命中粒度是 16K tokens，低于 16K 的 prefix 根本不会命中缓存，实验
  直接无效。需要溢出更多/更少 DRAM 时只调 `--num-prefixes`。
- 两组之间**必须重启** master 和 vllm（缓存状态隔离），SSD 目录清空。
- connector 侧若还没接 `prefetch_to_memory` 选项，B 组无效——先确认
  plan §3.1 再跑。
- 时间预算 ~30 分钟；压力抽查（c4×1 轮）可选，不进主结论。
