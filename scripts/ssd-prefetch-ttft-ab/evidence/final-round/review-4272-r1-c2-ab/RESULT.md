# 98d9002f c=2 A/B

`CLEAN_AB_PASS`。A_RC=0 B_RC=0。产品代码 dirty=0。

r1 gain（(A−B)/A）：median 0.25%，mean 0.10%，p99 1.28%。三档为正，幅度小于历史 c=2（约 +5.2% / +22%）。

两臂 LOCAL_DISK-only 闸门通过（HTTP `batch_query_keys`，A 58/64，B 60/64）。FILE_READ_FAIL=0。无 hang。

B 臂 `enable_ssd_prefetch=true`。master 指标 Promotion completed/failed/admitted 均为 0。`GLOG_v=1` 的 8 条探针里 get-side kick = 0。没有改产品代码。c=4 未跑。
