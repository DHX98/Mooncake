# review-4272-r1 红绿两轮

分支 `ssd-prefetch/review-4272-r1`。红轮 `b0a455b8714c7ce0f724058464f1e49663a5aab5`（测试 commit，在未修复的 PR head 之上）。绿轮 `98d9002face6aaf6dbda9df493a27710146347bd`（分支 HEAD）。

## 红轮

全量编译 `CMAKE_RC=0` `BUILD_RC=0`，`[730/730]`。

`ctest -R 'prefetch_throttle_test|prefetch_task_master_test|file_storage_promotion_test'`

三个 ctest 目标都失败，`CTEST_RC=8`。gtest 恰好 4 个失败，其余通过：

| suite | passed | failed |
| --- | ---: | --- |
| FileStoragePromotionTest | 11/12 | PrefetchKeysStopsBatchOnDramPressure |
| PrefetchThrottleTest | 12/13 | ZeroTtlKeepsNoPerKeyState |
| PrefetchTaskMasterTest | 5/7 | PrefetchFailureDoesNotRecordCandidate, RegisterPropagatesCandidateFailureCount |

失败要点：

- `PrefetchKeysStopsBatchOnDramPressure`：DRAM 压力后仍继续处理 pk2–pk4。`alloc_calls` 为 4，期望 1。
- `ZeroTtlKeepsNoPerKeyState`：ttl 为 0 时 key `a`/`b` 仍留下 per-key state，不是 `kFailed`。
- `PrefetchFailureDoesNotRecordCandidate`：失败后 `CandidateFailuresForTesting("pkl")` 仍有值，期望没有。
- `RegisterPropagatesCandidateFailureCount`：`TaskFailuresForTesting("pkp")` 为 0，期望 2；candidate failure 仍被记下。

完整输出：`red_ctest.log`。

## 绿轮

全量编译 `CMAKE_RC=0` `BUILD_RC=0`，`[254/254]`。

`ctest -R 'prefetch_throttle_test|prefetch_task_master_test|client_readonly_query_test|promotion_on_hit_test|file_storage_promotion_test|file_storage_test|probe'`

9/9 通过，`CTEST_RC=0`。包含红轮那三个目标：`file_storage_promotion_test`、`prefetch_throttle_test`、`prefetch_task_master_test`。

- `rdma_gid_probe_test` Passed 0.01s
- `rdma_context_reprobe_test` Passed 0.06s
- `promotion_on_hit_test` Passed 76.29s
- `file_storage_promotion_test` Passed 0.09s
- `client_readonly_query_test` Passed 12.06s
- `prefetch_throttle_test` Passed 0.03s
- `prefetch_task_master_test` Passed 7.03s
- `file_storage_test` Passed 27.49s
- `dummy_client_probe_key_test` Passed 8.07s

`bash scripts/ci/run_ssd_offload_smoke.sh`：`SMOKE_RC=0`（3 OK，3 OK 且 1 skipped，2 OK）。`ss` 使用本地 helper。
