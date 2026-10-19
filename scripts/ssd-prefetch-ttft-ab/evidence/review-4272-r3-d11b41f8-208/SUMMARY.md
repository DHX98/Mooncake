# r3 @ d11b41f8 on 208

Tree `d11b41f8d87d69c26ab429a421cc4c1fd3a9940f`, one commit past `2fc4ebe2`:
get-side wait removed, demand-side kick kept and gated only on
`enable_ssd_prefetch`. No merge, no upstream change in that commit.
Full build `BUILD_RC=0` inside `mc-r3-208`, same cmake flags as the
previous 208 card (`USE_ASCEND_DIRECT=ON`, unit tests on).

Same-build md5, timestamps UTC:

- `ascend_transport.so` `069516b55c3f019ba5a83e0f51fd494e` at 01:44:00
- `libtransfer_engine.so` `9ec3940aeee6878b9518b2a8861a02d9` at 01:46:09
- `libmooncake_store.so` `64187f3946af4125bd0336da2ace6ea0` at 01:54:03

## ctest

243 tests, 225 passed, 18 failed. `CTEST_RC=8`.

Passed, the three that this tree changes:

- `file_storage_promotion_test`
- `prefetch_throttle_test` (11 `TEST(` cases in the source; the binary passed)
- `prefetch_task_master_test`

Failed, not modified here:

`transport_uint_test`, `worker_pool_rail_state_test`,
`rdma_native_notify_test`, `rdma_notify_test`,
`rdma_endpoint_reestablish_test` (aborted), `rdma_async_event_drain_test`
(segfault), `shm_transport_e2e_test`, `tcp_transport_test` (aborted),
`tcp_write_visibility_test`, `transfer_metadata_test` (aborted),
`ascend_direct_transport_test`, `tebench_build_tree_help`,
`transfer_task_test`, `client_tcp_local_memcpy_test`, `pybind_client_test`,
`dummy_client_get_buffer_test`, `dummy_client_probe_key_test`,
`dummy_client_object_checksum_test`.

`client_tcp_local_memcpy_test` is the already-bisected upstream failure
(`35199bd5` fail / `986f385c` pass). No semantic fix.

## smoke

`scripts/ci/run_ssd_offload_smoke.sh` against this build's master and
`store.so` (staged copy, md5 matches the build).

- offload group: 3 tests, OK
- promotion group: 3 tests, OK, 1 skipped
- prefetch group: 3 tests, `test_exist_with_prefetch_promotes_ssd_only_key`
  and the negative control passed. `test_get_kick_promotes_ssd_only_key`
  failed: 15s timeout, key stayed `['LOCAL_DISK', 'DISK']`. The get itself
  returned bit-exact bytes. `SMOKE_RC=1`.

Python `store.get` calls `RealClient::get_buffer` /
`get_buffer_internal`. That function reads a LOCAL_DISK replica through
the offload RPC and returns. It does not call `TriggerPrefetch`. The
demand-side kick block is only in `batch_get_into_multi_buffers_internal`
(`real_client.cpp` around the `enable_ssd_prefetch_ && prefetcher_`
check). `is_exist` with `prefetch_to_memory` does call `TriggerPrefetch`,
which is why the exist case passed. Default-level logs show
`SSD prefetch runtime: pool_size=4` and no `ssd_get_wait_ms` field, so
this is the new binary. Not patched.

## e2c

Previous arm, tree `2fc4ebe2`, prefetch on, wait 500, promotion_on_hit
threshold 2. Diagnosis only. See `E2C_DIAG.md`.

## progress branch

`ssd-prefetch/v3-progress` was absent because a detached HEAD push of
`HEAD:ssd-prefetch/v3-progress` is not a full ref. Proxy and credentials
were already working. One push of `HEAD:refs/heads/ssd-prefetch/v3-progress`
created the branch at `0c08ff9e`. `progress.sh` now uses that refspec.
