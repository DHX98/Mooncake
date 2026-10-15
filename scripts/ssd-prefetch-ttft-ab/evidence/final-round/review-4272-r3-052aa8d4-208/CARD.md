# review-4272-r3 @ 052aa8d4，在 208 上跑完

机器 master-node（80.48.37.208）。验证树是 `052aa8d4297da54b1f3f97b2cf5d507b31276c1e`，父提交 `35199bd539071420a562f94bdd6a2b1e8de67728`，subject 是 `[Store] Submit memory transfers before the get-side prefetch wait`。相对这个提交没有新的产品修复。工作区是 detached HEAD，不在 `feat/ssd-prefetch-on-exist` 或 `feat/ssd-prefetch-on-exist-v2` 上。

容器 `mc-r3-208`，镜像是本机已有的 `vllm-ascend:v0.23.0rc1-openeuler`（没有 docker pull）。编译前在容器里补了 glog、jsoncpp、curl、openssl、zstd、xxhash、zeromq、liburing、hiredis、yaml-cpp、iproute 的开发包，并从 141 的 `mc-r2` 拷入 msgpack 3 的头文件。这些都是环境，没有改产品源码。

## 编译

`USE_ASCEND_DIRECT=ON`，`BUILD_UNIT_TESTS=ON`，`BUILD_SHARED_LIBS=ON`，`USE_CUDA=OFF`，`USE_ASCEND=OFF`，`WITH_EP=OFF`。没有 cargo，所以 `WITH_STORE_RUST=OFF`。gtest 1.17.0 和 yalantinglibs `7801bc9` 用本地 vendor。构建目录在源码树内的 `build/`。

`CMAKE_RC=0`，`BUILD_RC=0`。第一次链接前缺 `msgpack.hpp`，补上后从同一棵 `build/` 继续编完。

`ascend_transport.so` 来自这次构建。日志里有 `[34/810] Linking CXX shared library mooncake-transfer-engine/src/transport/ascend_transport/ascend_transport.so`。

路径：`Mooncake-r3review/build/mooncake-transfer-engine/src/transport/ascend_transport/ascend_transport.so`

md5 `fd7af65feb5de26efdd6ca16983e3b79`，大小 267120，mtime `2026-10-15 11:57:52 +0800`。

## 重点用例

单独再跑，五个返回码都是 0。

`prefetch_task_master_test` 7 个都过。

`prefetch_throttle_test` 的 `WaitOutcomeReflectsPromotionState` 过了。

`file_storage_promotion_test` 的 `PrefetchKeysForwardsTenantToPromotion` 过了。

`client_readonly_query_test` 4 个都过。`client_metrics_test` 20 个都过。

全量 ctest 里这五个二进制也是 Passed（7.33s、0.43s、0.43s、12.64s、16.78s）。

## ctest

243 个里 225 通过，18 失败，`CTEST_RC=8`。上一轮 r3（731f75c）是 249 个里 21 个失败。

这一轮仍失败：

| test | ctest 标记 |
| --- | --- |
| transport_uint_test | Failed |
| worker_pool_rail_state_test | Failed |
| rdma_endpoint_reestablish_test | Subprocess aborted |
| rdma_async_event_drain_test | SEGFAULT |
| shm_transport_e2e_test | Failed |
| tcp_transport_test | Subprocess aborted |
| tcp_write_visibility_test | Failed |
| transfer_metadata_test | Subprocess aborted |
| ascend_direct_transport_test | Failed |
| tebench_build_tree_help | Failed |
| transfer_task_test | Failed |
| pybind_client_test | Failed |
| dummy_client_get_buffer_test | Failed |
| dummy_client_probe_key_test | Failed |
| dummy_client_object_checksum_test | Failed |

上一轮失败、这一轮不在失败名单里：`memory_location_test`、`local_file_snapshot_object_store_test`、`snapshot_child_process_test`、`mmap_arena_test`、`mmap_arena_fallback_test`、`master_heartbeat_metric_test`（其中 heartbeat 在日志里是 Passed）。

新增失败：

| test | 现象 |
| --- | --- |
| rdma_native_notify_test | Failed。Ascend context 是空指针，`Failed to install Ascend transport`，随后 `sender_` 为 nullptr。和历史的 device context 失败同一类。 |
| rdma_notify_test | Failed。同一类传输引擎/RDMA 环境失败。 |
| client_tcp_local_memcpy_test | Failed。6 个里 5 个过，只有 `MetadataRemoteReplicaOnSameTcpHostUsesTransferEngine` 在 `client_tcp_local_memcpy_test.cpp:427` 期望 true、实际 false。不是 get 路径的租约断言。 |

这些都没有改产品代码或测试断言。dummy client 一类仍按历史口径视为没有 device context，没有当语义问题去修。

## smoke

`scripts/ci/run_ssd_offload_smoke.sh`，容器里有 `ss`（iproute2）。跑了两遍，`SMOKE_RC` 都是 0。下面是第二遍；第一遍同样三组通过、混合用例同样 skip，日志在 `smoke-first.log`。

| 组 | 第二遍 |
| --- | --- |
| ssd offload evict | Ran 3 tests in 74.808s，OK |
| promotion on hit | Ran 3 tests in 41.034s，OK（skipped=1） |
| prefetch on exist | Ran 4 tests in 27.677s，OK（skipped=1） |

`test_get_wait_success_carries_live_lease` 两遍都过。第二遍 `batch_get results [8388608]`，8MB 整段读回。

`test_get_wait_mixed_batch_serves_memory_and_ssd_keys` 两遍都 skip，不是 fail。第二遍：大 key 在 probe 1 变成 `LOCAL_DISK+DISK`；小 key 的 replica 是 `LOCAL_DISK+DISK`，没有 MEMORY。用例因此 skip，原因是 overflow 把 1MB 的 key 也逐出了 32MB segment，混合 batch 的 DRAM 前提不成立。主机内存大约还有 1191G 可用，没有别的 mooncake master 在抢。没有改 skip 条件。

## 修复 commit

没有。验证的就是 `052aa8d4`。
