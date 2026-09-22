# RESULT — fce6b01c exist-v2 compile, ctest, smoke

Date: 2026-09-22. Branch under test: `feat/ssd-prefetch-on-exist-v2`.
HEAD as fetched: `fce6b01c686067f22be107dbb69c96ff07f22a0c`
(merge of `ssd-prefetch/pr3-exist-get-wiring` into upstream main).

That SHA did not compile. The four local fixes below are uncommitted, are not in `fce6b01c`, and were not pushed to the feat branch.

## Local fixes (dirty=4)

| path | change |
|---|---|
| `mooncake-store/include/master_service.h` | truncated `MasterService` restored from the two parents (+1522/−3). Bad friend declarations removed. Forward declarations added for `benchmarks::BatchEvictBench` and `ha::MasterSnapshotCodecTest`. |
| `mooncake-store/include/object_runtime_state.h` | `PromotionTask::from_prefetch` (+3) |
| `mooncake-store/src/dummy_client.cpp` | closing brace on `DummyClient::batchProbeKey` (+1) |
| `mooncake-wheel/mooncake/buffer_pool.py` | 12 lines restored from prefetch parent `c448bad`. Needed for smoke import. |

```
 mooncake-store/include/master_service.h       | 1522 ++++++++++++++++++++++++-
 mooncake-store/include/object_runtime_state.h |    3 +
 mooncake-store/src/dummy_client.cpp           |    1 +
 mooncake-wheel/mooncake/buffer_pool.py        |   12 +
 4 files changed, 1535 insertions(+), 3 deletions(-)
```

## Task 1

Command:

```
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_UNIT_TESTS=ON
cmake --build build
```

| stage | result |
|---|---|
| first ninja | stopped at `[129/730]`, `BUILD_RC=1`, `prefetch_error_count=93` |
| why | truncated `master_service.h` (`class MasterService` unclosed) cascaded into `/usr/include/zstd.h:11` and `namespace` parse errors |
| after header fix | `CMAKE_RC=0` `BUILD_RC=0` `prefetch_error_count=0` `[425/425]` |

The 93 count is the header cascade, not 93 independent prefetch errors.

Warning (path contains `master_service`; not a `probeKey` warning):

```
mooncake-store/tests/master_service/dsl/scenario.cpp:290: missing initializer for member mooncake::test::RacePutStartAction::group_ids
```

No `object_metadata` warning. No `probeKey` warning. `probe_warn_count=1` is this `scenario.cpp` line.

## Task 2

Filter:

```
ctest -R 'prefetch_throttle_test|prefetch_task_master_test|client_readonly_query_test|promotion_on_hit_test|file_storage_promotion_test|file_storage_test|probe'
```

`CTEST_RC=0`. 100% tests passed out of 9. Total Test time (real) = 123.92 sec.

```
1/9 Test  #34: rdma_gid_probe_test ..............   Passed    0.00 sec
2/9 Test  #36: rdma_context_reprobe_test ........   Passed    0.02 sec
3/9 Test  #86: promotion_on_hit_test ............   Passed   76.05 sec
4/9 Test  #88: file_storage_promotion_test ......   Passed    0.07 sec
5/9 Test #134: client_readonly_query_test .......   Passed   12.04 sec
6/9 Test #135: prefetch_throttle_test ...........   Passed    0.03 sec
7/9 Test #136: prefetch_task_master_test ........   Passed    5.02 sec
8/9 Test #177: file_storage_test ................   Passed   22.63 sec
9/9 Test #185: dummy_client_probe_key_test ......   Passed    8.05 sec
```

`prefetch_task_master_test` (`MasterServiceTestPeer`) passed after the local header restore. Clean `fce6b01c` did not compile, so this result is not a clean-SHA pass.

Smoke: `bash scripts/ci/run_ssd_offload_smoke.sh`.

- First run `SMOKE_RC=1`: `scripts/ci/services.sh` had no `ss`. Metadata had started; the wait still reported that port 8080 was not listening.
- After `iproute2`, retry `PHASE=smoke_retry` `SMOKE_RC=0`:
  - Ran 3 tests — OK
  - Ran 3 tests — OK (skipped=1)
  - Ran 2 tests — OK

## Scope

Tasks 1 and 2 only. Later TTFT A/B is not a pass. See `INTERNAL.md`.
