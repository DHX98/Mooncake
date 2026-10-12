# review-4272-r3 全量验证，142 中途失联

目标提交是 `2a0b5949716cea290bc30fa02108b8db51d5a83f`。编译期修了两处机械问题后，验证树是 `731f75c72743befde20e3cb37fb67c8b3ea16f98`，父提交就是 `2a0b5949`。已快进推到 `ssd-prefetch/review-4272-r3`。提交说明里没有数字井号引用。`Mooncake-pr3` 仍在 `feat/ssd-prefetch-on-exist-v2` 的 `aa7e21bd`，没有动那条分支。

## 编译

容器 `prefetch-916`，`USE_ASCEND_DIRECT=ON`，`BUILD_UNIT_TESTS=ON`，`BUILD_SHARED_LIBS=ON`，`USE_CUDA=OFF`，`USE_ASCEND=OFF`，`WITH_EP=OFF`。本机没有 cargo，所以 `WITH_STORE_RUST=OFF`。gtest 和 yalantinglibs 用本地 vendor。

`CMAKE_RC=0`。第一轮 ninja 在 `prefetch_task_master_test.cpp` 停住：`MetadataAccessorRO::GetState` 是私有的。测试改成和 promotion-on-hit 一样，从公开的 tenant metadata map 读 `promotion_task`。第二轮链接 `shared_segment_test` 时缺 `aclrtSetDevice`（`libascendcl.so` 没在命令行上）。`USE_ASCEND_DIRECT` 时给这个目标补上 `ascendcl`。

增量构建 `BUILD_RC=0`。`ascend_transport.so` 在本次构建目录：

`/home/d00883276/prefetch_916/920_pre_pr/gate/build-r3-2a0b/mooncake-transfer-engine/src/transport/ascend_transport/ascend_transport.so`

第一次链出时的 md5 是 `0c61e3378d7aace71df334d3d77bed56`，大小 229728。后续增量构建没有重链这个 so。

## 修复

| commit | 原因 |
| --- | --- |
| `731f75c72743befde20e3cb37fb67c8b3ea16f98` | 只读 accessor 的 GetState 是私有的，测试改走公开 metadata；Ascend direct 构建给 shared_segment_test 补上 ascendcl |

## ctest

全量 `ctest --output-on-failure`，共 249 个。约 10:13 UTC 跑到 152/249 时，142 从实验网消失。当时计数：Passed 137，`***Failed` 10。`file_storage_promotion_test` 已 Passed（0.53s），因此 `PrefetchKeysForwardsTenantToPromotion` 在这个二进制里过了。`prefetch_task_master_test` 和 `prefetch_throttle_test` 还没轮到。smoke 没开始。

已看到的 9 个失败名：

| test | 现象 |
| --- | --- |
| default_config_test | 构建目录不在源码树下，夹具相对路径落空。已在 gate 下做了 `mooncake-common` 符号链接，还没重跑 |
| transport_uint_test | `engine.init` 安装 Ascend direct 时 `aclrtGetCurrentContext` 得到空 context |
| worker_pool_rail_state_test | 早期传输引擎失败，日志里有 RDMA 设备打开失败 |
| rdma_native_notify_test | 同上，整组失败 |
| rdma_notify_test | 同上 |
| shm_transport_e2e_test | 同上 |
| tcp_write_visibility_test | 同上 |
| ascend_direct_transport_test | 整组失败，断线前没有单独摘断言 |
| tebench_build_tree_help | 帮助文本的正则没匹配上 |

第 10 个失败的名字在断线前没有取到。这批失败都在传输引擎，不在 prefetch 的 master 状态机。空 context 这条没有改产品语义。

## 机器

开始时 8 张 NPU 没有进程，没有杀别人的任务。约 10:13 UTC 之后，工作站和 141 都连不上 80.48.37.142，141 上 ARP 一直 incomplete。旁边的 .140、.141、.143 通。全量 ctest 输出和 smoke 还在 142 的磁盘上，机器恢复前推不上来。
