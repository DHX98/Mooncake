# v3-verify 执行过程（给架构师）

没有改 Mooncake C++。本目录是 141 上实际跑过的现场包。
分支：`ssd-prefetch/v3-verify` @ `8cdcc10f`（代码）+ 本证据提交。
机器：`80.48.37.141`，容器 `prefetch-916`（不新建）。
工作目录：`/home/d00883276/perf_test_prefetch_v3_verify`
（bind 进容器为 `/home/d00883276/prefetch_916/perf_test_prefetch_v3_verify`）。

先看本文件和 `RESULT.md`，再按需打开 gzip 全量日志。

## 旋钮（成功那一轮）

| 项 | 值 |
|---|---|
| 模型 | `/data/DeepSeek-V4-Flash-w8a8-mtp`，served `dsv4-flash` |
| prefix / max_model_len | 16385 / 20480 |
| segment / wait | 256MB / `ssd_get_wait_ms=2000` |
| overflow | 48 |
| `promotion_on_hit` | false |
| `MAX_NUM_SEQS` / measure CONC | 4 / 4（`run_verify.sh` 覆盖 `env.sh` 默认 2） |
| client `GLOG_v` | 1 |
| master `--v` | 关 |
| overlay `libmooncake_store.so` | md5 `363b669c` |
| 端口 | HTTP 8271，RPC 50111，metrics 9021 |
| 只清本实验 `$ROOT/ssd` | 不动 `ssd_dsv4` / `ssd_8b` / 2646 |

配置原文：`configs/`。master / vLLM 命令行：`configs/master.flags.txt`、`configs/vllm.serve.txt`。

## 怎么跑

容器内：

```bash
docker exec prefetch-916 bash --noprofile --norc \
  /home/d00883276/prefetch_916/perf_test_prefetch_v3_verify/scripts/run_verify.sh
```

`run_verify.sh` 钉 ROOT / CONC=4 / MAX_NUM_SEQS=4 / GLOG_v=1，然后调 `run_ab.sh`。
每臂：start → `/v1/models` → fill(c=1) → **成功数必须 >0** → overflow → settle 90s → r1/r2 (c=4) → stop。
A 完清本实验 SSD，再 B。

## 各轮实验

### 0) 对照：9/17 赢了的 v3 r2（`perf_test_prefetch_v3`）

`MAX_NUM_SEQS=2`，CONC=2。A r1 1497.80 / 1901.99 / 6820.60 vs B 1419.47 / 1805.45 / 5321.74。
日志：`runs/v3-r2-win/`。grep 摘要：`STEP0.md`。

### 1) fail1 `20260918_150739` — A-fill EngineDead

`runs/fail1/`。A-fill 300s 0/48，`sample_tokens` RPC timeout。
`serve.sh stop` 只杀了 `vllm serve`，`VLLM::Worker`（PPID 1）占卡。
host / vllm / master 都在该目录，体积小（当时 generate 没真正起来）。

### 2) fail2 `20260918_152955` — 清卡不全，再挂

`runs/fail2/`。退了 master `--v=1`，其余照旧。A-fill 仍 0/48。
现场后判：不是 `--v=1`，是上一轮孤儿 worker + 回放 `serve.sh` 缺 HCCL/P2P。

### 3) fail3 `20260918_153220` — 启动即停

`runs/fail3/`。worker 报 `Free memory 48.39/60.96 < 0.95*60.96`。
HBM 没空干净就拉起。之后 `pkill -9 VLLM::Worker`，HBM 回到 ~5%。

### 4) success `2026-09-18T07:32:32Z → 08:22:51Z` — c=4 过线

host：`run_ab.host.log`。bench 屏上：`{a,b}_{fill,overflow,r1,r2}.bench.log`。
JSON：`runs/success/*.json`。
全量：`vllm.log.gz`（原 599MB）、`master.log.gz`（原 201MB）。
kick 摘录：`kicks.txt`（592 行，`in_cooldown=1` 211 次）。
Promotion 末帧：`promotion_last.txt`。

r1 c=4，48/48：

| | median | mean | p99 |
|---|---:|---:|---:|
| A | 14426.96 | 13583.52 | 16172.33 |
| B | 2135.01 | 2523.33 | 8918.93 |
| gain | +85.20% | +81.42% | +44.85% |

过线：r1 median AND mean AND p99 都是 B<A。

## 现场否定过的 HANDOFF 细节

1. 前两轮 A-fill 卡死是孤儿 `VLLM::Worker`，不是 prefetch kick，也不是 master `--v=1`。
2. kick 行是 `in_cooldown=0|1`，不是 `true|false`。211 次冷却中 kick → 不要删 `ignore_cooldown`。
3. 没有 `SsdMetric` 字符串；看 master 周期行 `Promotion: completed=/failed=`。
4. `prefetch_task_registered` 本轮 master 1363，不是 ≈166。
5. `vllm bench` 全失败也返回 0，必须读 `Successful requests:`。
6. RESULTDIR 里 A 阶段也可能写出 `b_*` 文件名，以时间戳和 host 日志为准。

## 目录

```
evidence/v3-verify/
  PROCESS.md                 本文件
  RESULT.md                  结论和 TTFT 表
  STEP0.md                   9/17 r2 零成本 grep
  METHOD.md                  （上一级 scripts/ssd-prefetch-ttft-ab/METHOD.md）
  configs/                   serve / env / master flags / vLLM argv / mooncake json
  run_ab.host.log            成功轮整段屏上过程
  {a,b}_*.bench.log          成功轮 bench 屏上 TTFT
  vllm.log.gz                成功轮 client/vLLM
  master.log.gz              成功轮 mooncake_master
  kicks.txt / promotion_last.txt
  runs/fail1|fail2|fail3/    三轮失败的 host + vllm + master + bench
  runs/success/*.json        成功轮 bench JSON
  runs/v3-r2-win/            9/17 赢了的对照日志
```
