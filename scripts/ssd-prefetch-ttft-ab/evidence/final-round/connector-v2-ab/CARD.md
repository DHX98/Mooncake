# c=2 settle=700 TTFT A/B

Connector `77c62937371588a9d9037e9f9fee82063fdcf56f`（`feat/ssd-prefetch-on-exist-v2`）。store `aa24af7ad8a3546573f1cebcfb0c873e8096fc07`，`libmooncake_store.so` md5 `4ca28bccfdafd18cceb6538a22afcc60`。工作区干净。overlay md5 `dc012d160af268b9847139a62caec84d`。

bench 镜像没有 `backend/base.py`，overlay 在导入失败时退回镜像里的 `Backend`，prefetch 接线仍是这条 connector 提交的逻辑。两边 worker 日志都打在 `mooncake_backend.py:432`：A 臂 `enable_ssd_prefetch=false ssd_get_wait_ms=2000`，B 臂 `enable_ssd_prefetch=true ssd_get_wait_ms=2000`。json 里 cooldown 5、dedup 30。

协议：`c=2`，`MAX_NUM_SEQS=2`，`PREFIX_TOKENS=16385`，`SEGMENT=256MB`，`ssd_get_wait_ms=2000`，`promotion_on_hit=false`，测量 `GLOG_v=0`。A 臂 prefetch 关，B 臂 prefetch 开。两臂各用新的 SSD 目录。seed 42，overflow seed 1042。`A_RC=0`，`B_RC=0`，`CLEAN_AB_PASS`。

## TTFT

gain% = (A−B)/A×100。四次 measure 都是 48/0。

| arm | success/fail | median | mean | p99 |
|---|---|---:|---:|---:|
| A_R1 | 48/0 | 1406.35 | 1418.53 | 1856.35 |
| A_R2 | 48/0 | 1303.39 | 1408.22 | 1916.80 |
| B_R1 | 48/0 | 1226.20 | 1301.69 | 1823.05 |
| B_R2 | 48/0 | 1387.53 | 1298.38 | 1769.38 |

| round | median gain | mean gain | p99 gain |
|---|---:|---:|---:|
| r1 | 12.81% | 8.24% | 1.79% |
| r2 | -6.46% | 7.80% | 7.69% |

r1 的 median / mean / p99 都为正。r2 的 median 为负，mean 和 p99 为正。

## Fill / overflow

| arm | fill | overflow |
|---|---|---|
| A | 48/0 3123.71 | 48/0 3037.16 |
| B | 48/0 3112.54 | 48/0 3036.23 |

## 闸门

HTTP 抽样 64 个 fill key。

| arm | n_fill | sampled | MEMORY | LOCAL_DISK | LOCAL_DISK-only | MISSING | GATE_PASS |
|---|---:|---:|---:|---:|---:|---:|---:|
| A | 3840 | 64 | 4 | 64 | 60 | 0 | 1 |
| B | 3840 | 64 | 8 | 60 | 56 | 0 | 1 |

r1 前和 r2 前，`FILE_READ_FAIL` 在 vLLM 和 master 都是 0。

## Promotion

A 臂测量窗口里 master 计数保持 `completed=0`，`failed=0`。B 臂 r1 结束时（11:05:09Z）是 `completed=1920, failed=0, bytes=5.35 GB`。r2 结束时（11:07:21Z）是 `completed=3840, failed=0, bytes=10.70 GB`。
