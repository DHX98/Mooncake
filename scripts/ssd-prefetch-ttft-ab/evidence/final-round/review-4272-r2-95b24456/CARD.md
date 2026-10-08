# review-4272-r2 @ 95b24456 红绿

不改产品代码，也不改测试。`ss` 用本地 helper。红轮是 `af797e8e`，只把 `mooncake-wheel/tests/test_prefetch_on_exist.py` 换成 `95b24456` 的版本。该文件 blob `61f5f0e54f5b2607b60bd95494694ff4363df38e`，工作区只有这一个改动。

## 红轮 `af797e8e` + 测试文件

全量编译：`CMAKE_RC=0`，`BUILD_RC=0`。

`bash scripts/ci/run_ssd_offload_smoke.sh`：`SMOKE_RC=1`。

| 组 | 结果 |
|---|---|
| ssd offload | Ran 3，OK，67.3s |
| promotion | Ran 3，OK（skipped=1），41.0s |
| prefetch | Ran 3，FAILED（failures=1），15.4s |

失败的是 `test_get_wait_success_carries_live_lease`，不是 `LEASE_EXPIRED`。断言停在 8MB 的 `put`：

```
File "mooncake-wheel/tests/test_prefetch_on_exist.py", line 234
    self.assertEqual(self.store.put(big_key, big_value), 0)
AssertionError: -200 != 0
```

`-200` 是 `NO_AVAILABLE_HANDLE`。get 等待和 lease 检查没有执行。同一 class 的前两个用例已经把 32MB segment 写满，这个用例和它们共用 `setUpClass` 的 store。测试未改。

## 绿轮 `95b24456`

`95b24456a347267d257b1e3644e4aaf5d65668af`，父提交是 `0dc2e0b4`。工作区干净。全量编译：`CMAKE_RC=0`，`BUILD_RC=0`。

ctest：

```
prefetch_throttle_test          Passed
prefetch_task_master_test       Passed
client_readonly_query_test      Passed
promotion_on_hit_test           Passed
file_storage_promotion_test     Passed
file_storage_test               Passed
rdma_gid_probe_test             Passed
rdma_context_reprobe_test       Passed
dummy_client_probe_key_test     Passed
100% tests passed out of 9
CTEST_RC=0
```

同一套 smoke：`SMOKE_RC=1`。前两组仍是 OK（69.7s，41.1s 且 skipped=1）。同一个用例仍然在第 234 行 `put` 失败，`AssertionError: -200 != 0`。没有转绿，也没有出现 `LEASE_EXPIRED`。

## 判读

红轮没有复现「get 成功路径把 lease_ttl_ms=0 交给传输」。绿轮也没有把这条用例跑到 lease 检查。两边都在先执行的 8MB `put` 上因 `NO_AVAILABLE_HANDLE` 退出。
