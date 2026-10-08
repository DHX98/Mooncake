# review-4272-r2 红绿两轮

不改产品代码，也不改测试。`ss` 用本地 helper。编译在带 Python 3.12 的容器里做，缺的 yaml-cpp、gflags、glog、curl、OpenSSL、jsoncpp、Boost 1.74、msgpack 3.3 开发包是装进容器的，不是改仓库。

## 红轮 `af797e8e`

`af797e8e9338ac830d056a05b7c38a84c58a5c21`，提交说明是 get 侧等待成功路径的回归测试，在未修复的 PR head 之上。

全量编译：`CMAKE_RC=0`，`BUILD_RC=0`。

`bash scripts/ci/run_ssd_offload_smoke.sh`：`SMOKE_RC=1`。

| 组 | 结果 |
|---|---|
| ssd offload | Ran 3，OK，68s |
| promotion | Ran 3，OK（skipped=1），40s |
| prefetch | Ran 3，FAILED（failures=1），17.5s |

失败的是 `test_get_wait_success_carries_live_lease`，但不是 `LEASE_EXPIRED`。断言停在 16MB 的 `put`：

```
File "mooncake-wheel/tests/test_prefetch_on_exist.py", line 231
    self.assertEqual(self.store.put(big_key, big_value), 0)
AssertionError: -200 != 0
```

`-200` 是 `NO_AVAILABLE_HANDLE`（空间不够）。get 等待和 lease 检查没有执行。测试未改。

## 绿轮 `0dc2e0b4`

`0dc2e0b493d64dcf4a2a8fca7fd9baab3679c8b7`，合并上游 main 之后的分支 HEAD。`setup_internal` 新签名和 embedded master 合入后，全量编译通过：`CMAKE_RC=0`，`BUILD_RC=0`。

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

同一套 smoke：`SMOKE_RC=1`。前两组仍是 OK（111.8s，39.1s 且 skipped=1）。同一个用例仍然在第 231 行 `put` 失败，`AssertionError: -200 != 0`。没有转绿，也没有出现 `LEASE_EXPIRED`。

## 判读

红轮没有复现「get 成功路径把 lease_ttl_ms=0 交给传输」。绿轮也没有把这条用例跑到 lease 检查。两边都在 16MB `put` 上因 `NO_AVAILABLE_HANDLE` 退出。smoke 脚本把 `SEGMENT_SIZE_BYTES` 设成 33554432。用例要先放进一个 16MB 的值，这一步在当前段大小下没有成功。
