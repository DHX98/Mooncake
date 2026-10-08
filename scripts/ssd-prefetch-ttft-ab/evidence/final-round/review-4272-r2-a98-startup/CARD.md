# 98d9002f 在当前环境只起 A 臂

上轮 `95b24456` 的 c=2 A/B 两臂都死在 worker 初始化：`ContextManager is not initialized`，`AscendDirectTransport: cannot allocate local segment, ret: -1`，然后 `Initialize mooncake failed. ret=-1`。没有 `Application startup complete`。

磁盘上已经没有那次部署后的库。`store_md5_98d9002f` 记录的是 `33130c318dc1647ce3ef0c056514daf9`，现有的 `libmooncake_store.so` 都对不上。于是按 `98d9002f` 用 `USE_ASCEND_DIRECT=ON` 重新构建，并用和 settle700 相同的 patchelf 装进当前环境。装完后的 store md5 是 `33130c318dc1647ce3ef0c056514daf9`，和 settle700 记录的部署 md5 相同。

只起 A 臂。prefetch 关，`SEGMENT=256MB`，`ssd_get_wait_ms=2000`，`promotion_on_hit=false`，`GLOG_v=0`，新的 SSD 目录。没有 fill，没有 measure。

## 结果

`SERVE_START_RC=0`。worker 日志有 `Application startup complete`。`GET /v1/models` 返回 200。没有 `ContextManager is not initialized`。

对照上轮 `95b24456` 的 worker 日志：`ContextManager is not initialized` 出现 160 次，没有 `Application startup complete`。

## 判读

同一套当前环境里，`98d9002f` 的构建能把 A 臂服务拉起来。启动失败在 `98d9002f` 之后合进去的代码里，不是这两周的容器、驱动或打包方式。没有做 commit 级二分。
