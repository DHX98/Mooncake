# r3 @ ee62d6ae on 208

`ee62d6ae497040456a9e8fcd2a44d662f006f958` on top of `d11b41f8`. The only
change extracts the demand-side kick into `KickPrefetchForDiskHeadedKeys`
and calls it from both `get_buffer_internal` and
`batch_get_into_multi_buffers_internal`.

Full build `BUILD_RC=0`. Same-build md5:

- `ascend_transport.so` `20fc13a3d6f6e80a8836c3611e04e009`
- `libtransfer_engine.so` `39a7aa68a565898d23ab30bb5ad4fe81`
- `libmooncake_store.so` `cd911ff12d79fd0784d5926b39f2f24b`

ctest: 243 tests, 225 passed, 18 failed. The failed set is the same 18
as `d11b41f8`: transport_uint, worker_pool_rail_state, rdma_native_notify,
rdma_notify, rdma_endpoint_reestablish (aborted), rdma_async_event_drain
(segfault), shm_transport_e2e, tcp_transport (aborted), tcp_write_visibility,
transfer_metadata (aborted), ascend_direct_transport, tebench_build_tree_help,
transfer_task, client_tcp_local_memcpy, pybind_client, dummy_client_get_buffer,
dummy_client_probe_key, dummy_client_object_checksum.
`file_storage_promotion_test`, `prefetch_throttle_test`, and
`prefetch_task_master_test` passed.

Smoke `SMOKE_RC=0`. Offload 3 tests OK. Promotion 3 tests OK, 1 skipped.
Prefetch 3 tests OK in 17.4s, including `test_get_kick_promotes_ssd_only_key`
on plain `store.get()`.

`ssd-prefetch/v3-progress` push with `refs/heads/` succeeded at `c60f3739`.

One line: the single-key get now fires the kick, the prefetch smoke group
passes, and the other ctest failures match the previous run.
