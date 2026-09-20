# v3-verify 测试方法（现场）

没有改 Mooncake C++。本目录脚本是 141 上实际跑通的副本：补了 HCCL/P2P 环境、stop 时回收孤儿 worker、fill 0/48 立即停。

## 环境

- 机：<host-ip>，容器 `<bench-container>`（不新建、不 pull）
- 分支：`ssd-prefetch/v3-verify` @ `8cdcc10f`
- overlay：`libmooncake_store.so` md5 `363b669c`
- 工作目录：`/home/<user><user>/perf_test_prefetch_v3_verify`
  （bind 进容器为 `/home/<user><user>/prefetch_916/perf_test_prefetch_v3_verify`）
- 只清空本实验 `$ROOT/ssd`，不动 `ssd_dsv4` / `ssd_8b` / 2646
- 端口：HTTP 8271，RPC 50111，metrics 9021
- 旋钮：prefix 16385，max_model_len 20480，segment 256MB，
  `ssd_get_wait_ms=2000`，overflow 48，`promotion_on_hit=false`，
  `MAX_NUM_SEQS=4`，measure `CONC=4`，client `GLOG_v=1`，master 不带 `--v=1`

## 怎么跑

容器内：

```bash
docker exec <bench-container> bash --noprofile --norc \
  /home/<user><user>/prefetch_916/perf_test_prefetch_v3_verify/scripts/run_verify.sh
```

`run_verify.sh` 只做四件事：钉 ROOT/CONC/MAX_NUM_SEQS/GLOG_v，然后调 `run_ab.sh`。

`run_ab.sh` 每臂：start → wait `/v1/models` → fill(c=1) → **fill 成功数必须 >0** → overflow → settle 90s → measure r1/r2 (c=4) → stop。A 完清空本实验 SSD，再 B。

主数字看屏上 `*.bench.log` 的 TTFT，不要只看 JSON。gain% = (A−B)/A×100。过线：r1 median、mean、p99 都是 B<A。

## 现场踩过的坑（HANDOFF 不对的地方以这里为准）

1. **孤儿 `VLLM::Worker`**。EngineDead 之后 `pkill vllm serve` 杀不掉 PPID=1 的 worker，NPU 上留 64MB 占卡。下一轮 `/v1/models` 是活的，首包 16k generate 卡满 300s。`serve.sh stop` 必须再 `pkill -9 VLLM::Worker` / `VLLM::EngineCore`。重开前用 `npu-smi info -t proc-mem` 看 0–7 是否清空，不要只看 HBM%。
2. **回放 `serve.sh` 缺现场环境**。能跑的 v3 有 `HCCL_IF_IP=<host-ip>`、`GLOO/HCCL/TP_SOCKET_IFNAME=enp189s0f0`、`MC_METADATA_SERVER=P2PHANDSHAKE`、`LOCAL_HOSTNAME=127.0.0.1`、`--data-parallel-size 1`。HANDOFF 精简稿没有。
3. **`vllm bench` 全失败也返回 0**。必须读 `Successful requests:`，0 就停，否则会继续 overflow。
4. **kick 日志是 `in_cooldown=0|1`，不是 `true|false`**。按 HANDOFF 去 `grep in_cooldown=true` 会得到 0，是假阴性。
5. **没有 `SsdMetric` 字符串**。看 master 周期行里的 `Promotion: completed=/failed=/bytes=`。
6. **`prefetch_task_registered` 不是 ≈166**。赢了的 v3 r2 是 master 2307；本轮是 1363。这是 rank/layer/fill+overflow+measure 累加，不是 exist 前缀条数。
7. **RESULTDIR 里会同时出现 `a_*` 和 `b_*` 文件名**。以时间戳和 host 日志阶段为准：A 的 r1 在 15:57，B 的 r1 在 16:21。不要拿 A 阶段写出来的 `b_r1.*` 当 B。

## 本轮证据索引

目录：`scripts/ssd-prefetch-ttft-ab/evidence/v3-verify/`

| 文件 | 内容 |
|---|---|
| `RESULT.md` | 结论、TTFT 表、kick/cooldown 计数、Promotion 摘录 |
| `STEP0.md` | 9/17 赢了的 v3 r2 零成本 grep |
| `run_ab.host.log` | 整轮屏上过程（含 VERIFY START/DONE） |
| `{a,b}_{fill,overflow,r1,r2}.bench.log` | vLLM bench 屏上 TTFT |
| `vllm.log.gz` | client/vLLM 全量（原 599MB，GLOG_v=1） |
| `master.log.gz` | mooncake_master 全量（原 201MB） |
| `kicks.txt` | 全部 `get-side kick` 行 |
| `promotion_last.txt` | master 最后几帧 Promotion |
| `fail1.host.log` | 第一轮 A-fill 0/48 / EngineDead 的 host 日志 |

原日志仍在 141：`/home/<user><user>/perf_test_prefetch_v3_verify/logs/{vllm,master}.log`。

## 本轮数字（r1 c=4，48/48）

| | median | mean | p99 |
|---|---:|---:|---:|
| A | 14426.96 | 13583.52 | 16172.33 |
| B | 2135.01 | 2523.33 | 8918.93 |
| gain | +85.20% | +81.42% | +44.85% |

kick 592；`in_cooldown=0` 381；`in_cooldown=1` 211。冷却中 kick 发生过，不能据此删 `ignore_cooldown`。

cooldown 行：vllm 2150 / master 0。DRAM saturated：vllm 177 / master 0。registered：master 1363 / vllm 0。

Promotion 最后一帧：completed=503 failed=860 bytes=1.40 GB，DRAM 97.5%，Keys 3840。

VERIFY：2026-09-18T07:32:32Z → 08:22:51Z。
