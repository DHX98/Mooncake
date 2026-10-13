# 71274930 A 臂结果，B 臂未跑

代码 `71274930a6d3324302fa3c96a736cb3a8ab03e4e`。store 与 `ascend_transport.so` 来自 bench 容器里同一次 `USE_ASCEND_DIRECT=ON` 构建。装入站点包后 store md5 `fc8d64d065b668682d56a0ef075fc100`。harness 仍是上次的 `conn_ab.sh`：`c=2`，`PREFIX_TOKENS=16385`，`MAX_NUM_SEQS=2`，`SEGMENT=256MB`，`ssd_get_wait_ms=2000`，settle 700s，seed 42，overflow seed 1042，数据集 `data_r4272`。connector overlay md5 `dc012d160af268b9847139a62caec84d`。

B 臂按要求跳过，没有新的测量。磁盘上的 `b_r1` / `b_r2` 仍是 10 月 9 日那次，不计入本轮。

## A 臂 TTFT

prefetch 关。fill、overflow 都是 48/0。settle 06:49:50Z 到 07:01:31Z。`FILE_READ_FAIL` 为 0。`REPLICA_IS_NOT_READY` 为 0。`A_RC=0`。

| 轮次 | 成功/失败 | p50 | p90 | p99 | mean |
| --- | --- | ---: | ---: | ---: | ---: |
| fill | 48/0 | 3134.17 | 3197.71 | 3857.22 | 3157.52 |
| overflow | 48/0 | 3050.24 | — | 3207.25 | 3052.02 |
| r1 | 48/0 | 1501.89 | 1669.92 | 1968.08 | 1482.45 |
| r2 | 48/0 | 1457.30 | 1530.99 | 1859.06 | 1460.12 |

r2 结束时 master：`Promotion completed=0 failed=0`，内存 `872.69 MB / 2.00 GB`（42.6%），SSD `10.50 GB`，keys 3840。prefetch 关闭时完成数为 0，和上次 A 臂一致。

## 和上次 A 臂对照

上次是 connector c=2 settle=700 那轮。只比 A 臂，单位 ms。

| 轮次 | 指标 | 上次 | 这次 | 差 |
| --- | --- | ---: | ---: | ---: |
| r1 | p50 | 1406.35 | 1501.89 | +95.54 |
| r1 | mean | 1418.53 | 1482.45 | +63.92 |
| r1 | p99 | 1856.35 | 1968.08 | +111.73 |
| r2 | p50 | 1303.39 | 1457.30 | +153.91 |
| r2 | mean | 1408.22 | 1460.12 | +51.90 |
| r2 | p99 | 1916.80 | 1859.06 | -57.74 |

热路径 r2 的 p99 比上次 A 臂低 57.74 ms。B 臂没跑，p99 收益、prefetch complete 是否约 1920、有没有新增错误类别，这三项判据没有结果。

同目录有 `a_fill.bench.log`、`a_overflow.bench.log`、`a_r1.bench.log`、`a_r2.bench.log`。
