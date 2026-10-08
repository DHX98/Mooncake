# review-4272-r2 @ 95b24456 c=2 A/B

代码 `95b24456a347267d257b1e3644e4aaf5d65668af`。dirty=0。
`USE_ASCEND_DIRECT=ON` 部署。store md5 `70290b24694c3a984eed49f27944cc07`。同一次构建的 engine 模块已装进同一 site-packages。产品代码未改。

协议与 settle700 那轮相同：`c=2`，`MAX_NUM_SEQS=2`，`PREFIX_TOKENS=16385`，`SEGMENT=256MB`，`SSD_GET_WAIT_MS=2000`，`promotion_on_hit=false`，settle 700s，master 默认参数，measure 期间 `GLOG_v=0`。A 臂 prefetch 关。B 臂 `ssd_prefetch_cooldown_sec=5`，`ssd_prefetch_dedup_ttl_sec=30`。两臂各用新的 SSD 目录。seed 42，overflow seed 1042。

没有进入 fill。两臂都在 vLLM worker 初始化 Mooncake 时退出。

## 启动失败

worker 日志：

```
ContextManager is not initialized.
AscendDirectTransport: cannot allocate local segment, ret: -1
Failed to install Ascend transport
Failed to initialize transfer engine, rc=-1
Initialize mooncake failed. ret=-1, metadata_server=P2PHANDSHAKE
```

同一条出现在每个 TP worker。`wait_ready` 随后超时。A 臂如此。B 臂在把 engine 模块与 store 对齐之前也是同一条 `Initialize mooncake failed`。对齐之后重开 A 臂，错误不变。

没有 fill/overflow 的 48/0，没有 HTTP 闸门，没有 r1/r2，没有 Promotion 计数，没有 TTFT。

## 和 settle700 的差别

settle700 那轮（`98d9002f`）能过启动，B 臂 r1 `Promotion completed=1920`，median gain 4.52%，mean gain 8.10%。这一轮在 serve 起来之前就停了，比不出 TTFT。
