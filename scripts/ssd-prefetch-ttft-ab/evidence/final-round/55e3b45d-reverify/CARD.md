# feat/ssd-prefetch-on-exist-v2 reverify at 55e3b45d

Code under test: `feat/ssd-prefetch-on-exist-v2` @ `55e3b45d58804f7c99c382a2a5fb629f37e1568d`.

Git parent is `fce6b01c686067f22be107dbb69c96ff07f22a0c`. Against `aa7e21bd26daceb4aebaf46b1ce321f8d4e24bb1` the tree deletes 4 lines in `mooncake-store/include/master_service.h`: an empty `namespace benchmarks`, and a duplicate `friend class MasterSnapshotManager`. Working tree dirty count 0.

## Task 1

```
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_UNIT_TESTS=ON
cmake --build build
```

`CMAKE_RC=0` `BUILD_RC=0`. Prefetch-path error count 0. Link finished at `[730/730]`.

Warning whose path contains `master_service` (not a `probeKey` warning):

```
mooncake-store/tests/master_service/dsl/scenario.cpp:290: missing initializer for member mooncake::test::RacePutStartAction::group_ids
```

No `object_metadata` warning. No `probeKey` warning.

## Task 2

`ctest -R 'prefetch_throttle_test|prefetch_task_master_test|client_readonly_query_test|promotion_on_hit_test|file_storage_promotion_test|file_storage_test|probe'`

9/9 passed. `CTEST_RC=0`. Total test time (real) = 124.17 sec.

- `rdma_gid_probe_test` Passed 0.00s
- `rdma_context_reprobe_test` Passed 0.02s
- `promotion_on_hit_test` Passed 76.07s
- `file_storage_promotion_test` Passed 0.07s
- `client_readonly_query_test` Passed 12.05s
- `prefetch_throttle_test` Passed 0.03s
- `prefetch_task_master_test` Passed 5.02s
- `file_storage_test` Passed 22.82s
- `dummy_client_probe_key_test` Passed 8.06s

Smoke `bash scripts/ci/run_ssd_offload_smoke.sh`: first `SMOKE_RC=1` because `ss` was not installed (`metadata` had started). Retry with a local `ss` helper: `SMOKE_RC=0` (3 OK, 3 OK with 1 skipped, 2 OK).

Same outcome as the previous exist-v2 round: compile 0 error, 9/9, smoke RC=0.
