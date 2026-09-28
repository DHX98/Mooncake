# review-4272-r1 @ 98d9002f c=2 A/B

代码 `ssd-prefetch/review-4272-r1` @ `98d9002face6aaf6dbda9df493a27710146347bd`。
平台 A2，协议与 final round 同构：fill 48 → overflow 48 → settle 90s → LOCAL_DISK 闸门 → FILE_READ_FAIL 闸门 → measure r1/r2。
`c=2`，`MAX_NUM_SEQS=2`，`PREFIX_TOKENS=16385`，`SEGMENT=256MB`，`SSD_GET_WAIT_MS=2000`，`promotion_on_hit=false`，measure 期间 `GLOG_v=0`。
A 臂 prefetch 关，B 臂 prefetch 开。两臂各用新的 SSD 目录。同一 dataset，seed 42 / overflow seed 1042。
产品代码 dirty=0。store 与 wheel 来自该 SHA 的 `USE_ASCEND_DIRECT=ON` 构建。

## TTFT

gain% = (A−B)/A×100。主结果是 r1。

| arm | success/fail | median | mean | p99 |
|---|---|---:|---:|---:|
| A_R1 | 48/0 | 1511.47 | 1468.26 | 2391.86 |
| A_R2 | 48/0 | 1421.38 | 1417.02 | 2017.84 |
| B_R1 | 48/0 | 1507.70 | 1466.80 | 2361.33 |
| B_R2 | 48/0 | 1327.79 | 1379.68 | 1978.30 |

| round | median gain | mean gain | p99 gain |
|---|---:|---:|---:|
| r1 | 0.25% | 0.10% | 1.28% |
| r2 | 6.58% | 2.63% | 1.96% |

r1 三档都为正，方向与历史 c=2（median 约 +5.2%，p99 约 +22%）相同，幅度小很多。没有改产品代码。

## Fill / overflow（必须 48/0）

| arm | fill | overflow |
|---|---|---|
| A | 48/0 3141.58 | 48/0 3040.25 |
| B | 48/0 3119.87 | 48/0 3032.39 |

## 闸门

客户端 `batch_get_replica_desc`（segment=0）setup 失败，两臂都改用 master `GET /batch_query_keys` 抽查 64 个 fill key。这是 harness 补证，不是放宽闸门。

| arm | n_fill | sampled | MEMORY | LOCAL_DISK | LOCAL_DISK-only | MISSING | GATE_PASS |
|---|---:|---:|---:|---:|---:|---:|---:|
| A | 3840 | 64 | 6 | 62 | 58 | 0 | 1 |
| B | 3840 | 64 | 4 | 62 | 60 | 0 | 1 |

FILE_READ_FAIL：A/B 在 r1 前、r2 前，vLLM 与 master 都是 0。没有 hang，没有同盘重测。

measure 期间 master 指标：A SSD 21.30 GB / keys 3840，evict keys 3560；B SSD 21.20 GB / keys 3840，evict keys 3535。DRAM 约 2 GB 段的 39%–42%。

## Prefetch 计数

B 臂 worker 的 `store.setup` 里 `enable_ssd_prefetch=true`，`ssd_prefetch_cooldown_sec=5`，`ssd_get_wait_ms=2000`。

measure 期间（`GLOG_v=0`）master 指标原文：`Promotion: in_flight=0, admitted=0, completed=0, failed=0`。`prefetch_task_registered` 日志行 = 0。`slot_exhaust` = 0。`DRAM saturated` = 0。

grep 里的 `promotion_failed`（A 176 / B 144）和 `cooldown`（A 9 / B 18）打中了指标行里的 `Promotion:` 以及配置里的 `ssd_prefetch_cooldown_sec`，不是失败事件或退让事件。

B 臂启动时有 2 条 `OffloadObjectHeartbeat failed, error code is UNAVAILABLE_IN_CURRENT_STATUS`。fill 仍是 48/0。

## get-side kick（VLOG，不是 TTFT）

r2 之后把 B 臂以 `GLOG_v=1` 重启，再打 8 条同一 dataset（c=2）。`BENCH_RC=0`，8/0。

```
kick_vllm=0
kick_master=0
promotion_completed=0
prefetch_task_registered=0
dram_saturated=0
slot_exhaust=0
```

没有 `get-side kick` 行，也没有 `Promotion completed` 行。

## 未跑

c=4 饱和 early-exit 轮没有跑。
