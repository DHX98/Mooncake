# review-4272-r2 @ 4e31d100 红绿

不改产品代码，也不改测试。`ss` 用本地 helper。红轮是 `af797e8e`，只把 `mooncake-wheel/tests/test_prefetch_on_exist.py` 换成 `4e31d100` 的版本。该文件 blob `26bd9331d3408e31085e3bf71d323f4d6cda1366`，工作区只有这一个改动。

## 红轮 `af797e8e` + 测试文件

全量编译：`CMAKE_RC=0`，`BUILD_RC=0`。

`bash scripts/ci/run_ssd_offload_smoke.sh`：`SMOKE_RC=1`。

| 组 | 结果 |
|---|---|
| ssd offload | Ran 3，OK，69.1s |
| promotion | Ran 3，OK（skipped=1），41.0s |
| prefetch | Ran 3，FAILED（failures=1），15.4s |

失败的是 `test_get_wait_success_carries_live_lease`，不是 `LEASE_EXPIRED`，也不是 `put` 的 `-200`。断言停在重置：

```
File "mooncake-wheel/tests/test_prefetch_on_exist.py", line 229
    self.assertEqual(self.store.remove_all(True), 0)
AssertionError: 61 != 0
```

`remove_all` 成功时返回删掉的对象个数，失败时返回负的错误码。61 是成功删掉 61 个对象，不是错误码。断言要求返回 0，所以用例在这里退出。后面的 `put`、get 等待和 lease 检查没有执行。测试未改。

## 绿轮 `4e31d100`

`4e31d1002d6cf409c6d1bcc39d718a2db2221b1d`，父提交是 `95b24456`。工作区干净。全量编译：`CMAKE_RC=0`，`BUILD_RC=0`。

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

同一套 smoke：`SMOKE_RC=1`。前两组仍是 OK（67.7s，41.0s 且 skipped=1）。同一个用例仍然在第 229 行 `remove_all(True)` 得到 61。没有转绿，也没有出现 `LEASE_EXPIRED`。

## 判读

红轮没有复现「get 成功路径把 lease_ttl_ms=0 交给传输」。绿轮也没有把这条用例跑到 lease 检查。两边都在 `remove_all` 的返回值上退出。
