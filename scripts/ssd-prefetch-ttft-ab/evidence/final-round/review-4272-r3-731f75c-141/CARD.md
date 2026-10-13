# review-4272-r3 @ 731f75c，在 141 上跑完

142 从实验网消失后，同一份已推送的编译修复在 141 的 `mc-r2` 里重做了一遍。验证树是 `731f75c72743befde20e3cb37fb67c8b3ea16f98`，父提交 `2a0b5949716cea290bc30fa02108b8db51d5a83f`。没有新的产品提交。`feat/ssd-prefetch-on-exist-v2` 没有动。

## 编译

`USE_ASCEND_DIRECT=ON`，`BUILD_UNIT_TESTS=ON`，`BUILD_SHARED_LIBS=ON`，`USE_CUDA=OFF`，`USE_ASCEND=OFF`，`WITH_EP=OFF`。没有 cargo，所以 `WITH_STORE_RUST=OFF`。构建目录在源码树内的 `build/`，夹具相对路径因此能找到。

`CMAKE_RC=0`，`BUILD_RC=0`，`[825/825]`。

`ascend_transport.so` 来自这次构建：

`Mooncake-r3review/build/mooncake-transfer-engine/src/transport/ascend_transport/ascend_transport.so`

md5 `782536a7d8c86570c41070a50e218081`，大小 229728。

## 重点用例

单独再跑，三个返回码都是 0。

`prefetch_task_master_test` 7 个都过：

- RegisterSuccessThenDuplicateSkips
- MissingKeyNotFound
- NonHolderRejected
- MemoryReplicaPresentSkips
- NotifyPromotionSuccessGrantsLeaseForPrefetch
- PrefetchFailureDoesNotRecordCandidate
- RegisterPropagatesCandidateFailureCount

`prefetch_throttle_test` 的 `WaitOutcomeReflectsPromotionState` 过了。

`file_storage_promotion_test` 的 `PrefetchKeysForwardsTenantToPromotion` 过了。

全量 ctest 里这三个二进制也是 Passed（0.54s、0.54s、7.31s）。

## ctest

249 个里 228 通过，21 失败，`CTEST_RC=8`。失败名单：

| test | ctest 标记 |
| --- | --- |
| transport_uint_test | Failed |
| worker_pool_rail_state_test | Failed |
| rdma_endpoint_reestablish_test | SEGFAULT |
| rdma_async_event_drain_test | SEGFAULT |
| shm_transport_e2e_test | Failed |
| tcp_transport_test | Subprocess aborted |
| tcp_write_visibility_test | Failed |
| transfer_metadata_test | Subprocess aborted |
| memory_location_test | Failed |
| ascend_direct_transport_test | Failed |
| tebench_build_tree_help | Failed |
| transfer_task_test | Failed |
| pybind_client_test | Failed |
| local_file_snapshot_object_store_test | Failed |
| snapshot_child_process_test | Failed |
| dummy_client_get_buffer_test | Failed |
| dummy_client_probe_key_test | Failed |
| dummy_client_object_checksum_test | Failed |
| mmap_arena_test | Failed |
| mmap_arena_fallback_test | Failed |
| master_heartbeat_metric_test | Failed |

抽到的 dummy client 失败停在 `Failed to get current device, ret=107002`，`SetupStack()` 为 false，没有进到 probe 断言。传输引擎用例在安装 Ascend direct 时拿不到当前 context。`master_heartbeat_metric_test` 只有 `PreservesAndEscapesLabels` 的指标文本对不上。这些都没有按语义去改。

## smoke

`scripts/ci/run_ssd_offload_smoke.sh`，`SMOKE_RC=0`。三组：

| 组 | 结果 |
| --- | --- |
| ssd offload evict | Ran 3 tests in 69.050s，OK |
| promotion on hit | Ran 3 tests in 41.017s，OK（skipped=1） |
| prefetch on exist | Ran 3 tests in 21.527s，OK |

同目录有 `build.log`、`ctest.log`、`smoke.log`、`named.log`。
