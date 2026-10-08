# aa24af7a c=2 A/B，settle=700s

代码 `aa24af7ad8a3546573f1cebcfb0c873e8096fc07`。store md5 `4ca28bccfdafd18cceb6538a22afcc60`。工作区干净。`USE_ASCEND_DIRECT=ON`、`BUILD_SHARED_LIBS=ON`。`ascend_transport.so` 用的是同一次构建的产物，用来避开 #4325 对镜像里旧插件的布局破坏。产品代码没有改。

协议与 settle700 那轮相同。`c=2`，`MAX_NUM_SEQS=2`，`PREFIX_TOKENS=16385`，`SEGMENT=256MB`，`ssd_get_wait_ms=2000`，`promotion_on_hit=false`，测量时 `GLOG_v=0`。A 臂 prefetch 关。B 臂 prefetch 开：cooldown 5s，dedup 30s。两臂各用新的 SSD 目录。seed 42，overflow seed 1042。master 在一臂内部不重启。`CLEAN_AB_PASS`，`A_RC=0`，`B_RC=0`。

## TTFT

gain% = (A−B)/A×100。四次 measure 都是 48/0。

| arm | success/fail | median | mean | p99 |
|---|---|---:|---:|---:|
| A_R1 | 48/0 | 1560.81 | 1473.32 | 2344.79 |
| A_R2 | 48/0 | 1400.88 | 1450.31 | 1974.56 |
| B_R1 | 48/0 | 1290.98 | 1361.25 | 2226.75 |
| B_R2 | 48/0 | 1374.41 | 1297.40 | 1939.53 |

| round | median gain | mean gain | p99 gain |
|---|---:|---:|---:|
| r1 | 17.29% | 7.61% | 5.03% |
| r2 | 1.89% | 10.54% | 1.77% |

r1、r2 的 median / mean / p99 都为正，方向与 settle700 那轮相同。r1 的 median 降幅比那轮的 4.52% 大，r2 的 median 降幅小。

## Fill / overflow

| arm | fill | overflow |
|---|---|---|
| A | 48/0 median 3116.26 | 48/0 median 3028.17 |
| B | 48/0 median 3128.21 | 48/0 median 3028.57 |

## 闸门

HTTP `GET /batch_query_keys` 抽 64 个 fill key。

| arm | n_fill | sampled | MEMORY | LOCAL_DISK | LOCAL_DISK-only | MISSING | GATE_PASS |
|---|---:|---:|---:|---:|---:|---:|---:|
| A | 3840 | 64 | 9 | 59 | 55 | 0 | 1 |
| B | 3840 | 64 | 8 | 59 | 56 | 0 | 1 |

r1 前和 r2 前，状态文件里的 `FILE_READ_FAIL` 在 vLLM 和 master 都是 0。

## Promotion

A 臂测量窗口里的 master 计数保持 `completed=0`，`failed=0`。B 臂 r1 结束时（13:01:10）是 `completed=1920, failed=0, bytes=5.35 GB`。r2 结束时（13:03:20）是 `completed=3840, failed=0, bytes=10.70 GB`。1920 = 48 个 prefix × 40 个 SSD-only key。

## 复现

装好同一次构建的 `libmooncake_store.so`、`libtransfer_engine.so`、`engine.so`、`store.so`、`mooncake_master` 和 `ascend_transport.so` 之后，在 bench 容器里跑 settle700 那份 c=2 脚本，只把 SHA 校验、md5 文件和 SSD 目录换成这一轮的。进度在 `progress.txt`，原始判定在 `verdict.txt`。
