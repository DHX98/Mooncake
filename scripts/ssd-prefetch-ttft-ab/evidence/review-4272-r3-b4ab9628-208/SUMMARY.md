# r3 @ b4ab9628 on 208

`b4ab9628da2aa0f0e4e38202a69e7584d5fac7c5`. Clean build `BUILD_RC=0`.
Same-build md5:

- `libmooncake_store.so` `bb3fa1943b01478f7919e4da1cf760ca`
- `ascend_transport.so` `9e4f073cdaacfc55d1e0b85aa249ce18`
- `libtransfer_engine.so` `a8f187fd60bfdcdf087cf6b5409ecf6b`

`prefetch_task_master_test.cpp` and `prefetch_teardown_test.cpp` compiled.
Both binaries linked.

ctest: 255 tests, 237 passed, 18 failed. The failed names match the
ee62 set: transport_uint, worker_pool_rail_state, rdma_native_notify,
rdma_notify, rdma_endpoint_reestablish, rdma_async_event_drain,
shm_transport_e2e, tcp_transport, tcp_write_visibility, transfer_metadata,
ascend_direct_transport, tebench_build_tree_help, transfer_task,
client_tcp_local_memcpy, pybind_client, dummy_client_get_buffer,
dummy_client_probe_key, dummy_client_object_checksum.

Direct runs: prefetch_teardown_test 2 passed, prefetch_task_master_test
7 passed, prefetch_throttle_test 11 passed, file_storage_promotion_test
13 passed. `prefetch_teardown_test` repeated 20 times, all passed,
`REPEAT_RC=0`, about 6.5s each.

Smoke: the first two attempts failed in the harness (the extension is
`_store` / `PyInit__store`, then `libasio.so` was not beside it). The
third run loaded the module. Offload: 3 tests OK in 74.1s. Promotion:
3 tests OK, 1 skipped, in 41.0s. Prefetch did not run. `test_prefetch_on_exist.py`
does `from mooncake.store import ExistOptions`, and
`python/mooncake/store/__init__.py` does not re-export that name.
`store_py.cpp` does bind `py::class_<ExistOptions>`. The facade was not
edited.

`ssd-prefetch/v3-progress` push reached `f31f6d45`. TSAN/ASAN was not run.

One line: the build, ctest, and the 20-repeat are good, and the prefetch
smoke group stops because the Python facade does not export ExistOptions.
