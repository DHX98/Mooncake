# review-4272-r1 @ 98d9002f c=2 A/B，settle=700s

代码 `ssd-prefetch/review-4272-r1` @ `98d9002face6aaf6dbda9df493a27710146347bd`。dirty=0。
store md5 `33130c318dc1647ce3ef0c056514daf9`，与该 SHA 的 `USE_ASCEND_DIRECT=ON` 部署一致。产品代码未改。

协议与上一轮 c=2 同构，只把 settle 改成 700s（默认 `put_start_release_timeout` 仍是 600s，没有改这个参数）。
`c=2`，`MAX_NUM_SEQS=2`，`PREFIX_TOKENS=16385`，`SEGMENT=256MB`，`SSD_GET_WAIT_MS=2000`，`promotion_on_hit=false`，measure 期间 `GLOG_v=0`。
A 臂 prefetch 关。B 臂 prefetch 开：`ssd_prefetch_cooldown_sec=5`，`ssd_prefetch_dedup_ttl_sec=30`，`ssd_get_wait_ms=2000`。
两臂各用新的 SSD 目录。seed 42，overflow seed 1042。master 在一臂内部不重启。

## TTFT

gain% = (A−B)/A×100。主结果是 r1。四次 measure 都是 48/0。

| arm | success/fail | median | mean | p99 |
|---|---|---:|---:|---:|
| A_R1 | 48/0 | 1505.41 | 1490.94 | 2348.00 |
| A_R2 | 48/0 | 1320.73 | 1345.33 | 1981.80 |
| B_R1 | 48/0 | 1437.33 | 1370.17 | 2232.58 |
| B_R2 | 48/0 | 1211.83 | 1185.55 | 1839.31 |

| round | median gain | mean gain | p99 gain |
|---|---:|---:|---:|
| r1 | 4.52% | 8.10% | 4.92% |
| r2 | 8.25% | 11.88% | 7.19% |

r1 三档都为正，方向与 0327ddcb 那轮（median 约 +5.2%，p99 约 +22%）相同。median 接近那一轮，p99 小很多。没有改产品代码。

## Fill / overflow（必须 48/0）

| arm | fill | overflow |
|---|---|---|
| A | 48/0 median 3133.14 | 48/0 median 3046.79 |
| B | 48/0 median 3124.40 | 48/0 median 3042.92 |

## 闸门

客户端探针无 NPU context，`LOCAL_DISK-only=0`。两臂都用 HTTP `GET /batch_query_keys` 抽 64 个 fill key 补证。

| arm | n_fill | sampled | MEMORY | LOCAL_DISK | LOCAL_DISK-only | MISSING | GATE_PASS |
|---|---:|---:|---:|---:|---:|---:|---:|
| A | 3840 | 64 | 6 | 62 | 58 | 0 | 1 |
| B | 3840 | 64 | 10 | 63 | 54 | 0 | 1 |

FILE_READ_FAIL，r1 前和 r2 前，vLLM 与 master 都是 0：

```
FRF_GATE a_before_r1 vllm=0 master=0
FRF_GATE a_before_r2 vllm=0 master=0
FRF_GATE b_before_r1 vllm=0 master=0
FRF_GATE b_before_r2 vllm=0 master=0
```

没有 hang，没有同盘重测。

## Promotion

A 臂 r1 前后都是 completed=0。B 臂 r1 前是 0，r1 后是 1920；r2 后再加 1920，到 3840。failed 始终是 0。

r1 前：

```
Promotion: in_flight=0, admitted=0, completed=0, failed=0, cancelled=0, expired=0, bytes=0 B
```

r1 后：

```
Promotion: in_flight=0, admitted=0, completed=1920, failed=0, cancelled=0, expired=0, bytes=5.35 GB, rejected(freq/wm/cap)=0/0/0
SSD Storage: 10.70 GB
Mem Storage: 1.04 GB / 2.00 GB (51.9%)
```

r2 后：

```
Promotion: in_flight=0, admitted=0, completed=3840, failed=0, bytes=10.70 GB
Mem Storage: 933.23 MB / 2.00 GB (45.6%)
```

1920 = 48 prefix × 40 个 SSD-only key。r2 又完成同样一批。

## 测量窗口

`GLOG_v=0`，没有开 `GLOG_vmodule`。`RegisterPrefetchTask failed` 和 delegating 是 VLOG(1)，这个窗口里本来就不会出现。窗口切片里这几项都是 0：

```
===== b_r1 fail=0 errors={}
COUNT RegisterPrefetchTask failed = 0
COUNT DRAM saturated = 0
COUNT backing off = 0
COUNT delegating = 0
COUNT get-side kick = 0
===== b_r2 fail=0 errors={}
COUNT RegisterPrefetchTask failed = 0
COUNT DRAM saturated = 0
COUNT backing off = 0
```

A 臂 r1/r2 同样是 0。`DRAM saturated` 和 `backing off` 是 INFO，c=2 下为 0 是可见的。失败是否发生，以 master 的 `failed=0` 和 `completed=1920` 为准。

## 异常

无新的错误模式。r2 之后没有再做 `GLOG_v=1` 探针，master 没有为探针重启。
