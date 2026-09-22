# feat/ssd-prefetch-on-exist-v2 compile, ctest, and smoke

Code under test: `feat/ssd-prefetch-on-exist-v2` @ `fce6b01c686067f22be107dbb69c96ff07f22a0c` (merge of `ssd-prefetch/pr3-exist-get-wiring` into upstream main).

The commit as fetched did not compile. Local uncommitted fixes were required. They are not in that SHA and were not pushed to the feat branch. Dirty count 4.

- `mooncake-store/include/master_service.h`: merge truncated class `MasterService`; restored from the two parents (+1522/−3). Bad friend declarations removed. Forward declarations added for `benchmarks::BatchEvictBench` and `ha::MasterSnapshotCodecTest`.
- `mooncake-store/include/object_runtime_state.h`: `PromotionTask::from_prefetch` (+3).
- `mooncake-store/src/dummy_client.cpp`: closing brace on `DummyClient::batchProbeKey` (+1).
- `mooncake-wheel/mooncake/buffer_pool.py`: 12 lines restored from prefetch parent `c448bad` (merge had dropped it). Needed for smoke import.

Stat line only (patch body omitted): `logs/dirty_stat.txt`.

## Task 1

```
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_UNIT_TESTS=ON
cmake --build build
```

First ninja failed at 129/730. The truncated header left `class MasterService` open, and that cascaded into `/usr/include/zstd.h` and `namespace` parse errors. `prefetch_error_count=93` on that log is the cascade, not 93 independent prefetch errors.

After the header fix: `CMAKE_RC=0` `BUILD_RC=0`, prefetch-path error count 0. Link finished at `[425/425]`.

Warning whose path contains `master_service` (not a `probeKey` warning):

```
mooncake-store/tests/master_service/dsl/scenario.cpp:290: missing initializer for member mooncake::test::RacePutStartAction::group_ids
```

No `object_metadata` warning. No `probeKey` warning.

## Task 2

`ctest -R 'prefetch_throttle_test|prefetch_task_master_test|client_readonly_query_test|promotion_on_hit_test|file_storage_promotion_test|file_storage_test|probe'`

9/9 passed. `CTEST_RC=0`. Total test time (real) = 123.92 sec.

- `rdma_gid_probe_test` Passed
- `rdma_context_reprobe_test` Passed 0.02s
- `promotion_on_hit_test` Passed 76.05s
- `file_storage_promotion_test` Passed 0.07s
- `client_readonly_query_test` Passed 12.04s
- `prefetch_throttle_test` Passed 0.03s
- `prefetch_task_master_test` Passed 5.02s (this is the `MasterServiceTestPeer` question: it passed after the local header restore, not on clean `fce6b01c`)
- `file_storage_test` Passed 22.63s
- `dummy_client_probe_key_test` Passed 8.05s

Smoke `bash scripts/ci/run_ssd_offload_smoke.sh`: first RC=1 because the bench container had no `ss` (metadata had started). After `iproute2`, retry `SMOKE_RC=0` (3 OK, 3 OK with 1 skipped, 2 OK).

This directory is tasks 1 and 2 only. Later TTFT A/B is not a pass (`INTERNAL.md`).
