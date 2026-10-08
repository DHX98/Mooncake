# review-4272-r2 @ aa24af7a lease 红绿

红轮复现了 bug。绿轮同一条用例通过。产品代码没有改。测试文件相对 `aa24af7a` 有一处 setup 修正，两边用的是同一份，diff 在 `test_setup.diff`。

## 结论

`af797e8e` 加上 `aa24af7a` 的 `test_prefetch_on_exist.py`，再加下面的 setup 修正后，`bash scripts/ci/run_ssd_offload_smoke.sh` 的前两组通过，`test_get_wait_success_carries_live_lease` 失败。失败点是等待成功之后的传输被判 lease 过期：

```
W1008 11:18:41.285660 client_service.cpp:1956] lease_expired_before_data_transfer_completed key=prefetch_waitlease_big_1791458317311
E1008 11:18:41.285737 real_client.cpp:7833] BatchGet failed for key 'prefetch_waitlease_big_1791458317311': LEASE_EXPIRED
batch_get results [-707]
AssertionError: Lists differ: [-707] != [8388608]
```

`-707` 是 `ErrorCode::LEASE_EXPIRED`。对象在 get 之前已经是 `['LOCAL_DISK', 'DISK']`，没有 MEMORY。

`aa24af7a` 全量编译后 ctest 9/9，`CTEST_RC=0`。同一条 smoke：`SMOKE_RC=0`，该用例 `batch_get results [8388608]`，日志里没有 `LEASE_EXPIRED`。

## 测试 setup 修正

相对 `aa24af7a` 的测试文件，只动了 `test_get_wait_success_carries_live_lease`。理由：

1. 8MB 对象的 put 租约是 500ms。紧接着的 overflow 落在租约里，段被写满后不再有新的压力，对象一直停在 `MEMORY+LOCAL_DISK`。先 `sleep(1.5)` 等租约结束再 overflow。
2. `_find_cold_key` 每秒探一次，每次探询都会重新授 lease，把对象钉在 DRAM 里直到超时。改成每 2 秒探一次；若仍有 MEMORY，再补一轮 overflow。
3. 这台机器上 `sleep(0.025)` 和 `sleep(0.003)` 都落在提升完成之后，get 的首次查询已经看到 MEMORY，不会走进等待路径。红轮因此会误通过。改成 `is_exist` 之后 `sleep(0)`，get 落在 kInFlight 窗口里。diff 里有一行注释还写着 3ms，实际执行的是 `time.sleep(0)`。

未修正时的失败是 setup，不是 lease：`timeout (25s) waiting for a LOCAL_DISK-only key`，最后状态 `{'DISK,LOCAL_DISK,MEMORY': 1}`。

## 复现

容器里，`ss` 用已有的本地 helper。

红轮：

```
git checkout --detach af797e8e9338ac830d056a05b7c38a84c58a5c21
# 覆盖 mooncake-wheel/tests/test_prefetch_on_exist.py 为 aa24af7a 再打上 test_setup.diff
# USE 与既有 smoke 相同的 cmake（BUILD_UNIT_TESTS=ON，本地 gtest / yalantinglibs）
bash scripts/ci/run_ssd_offload_smoke.sh
```

绿轮：

```
git checkout --detach aa24af7ad8a3546573f1cebcfb0c873e8096fc07
# 同一份测试修正
ctest --test-dir build -R 'prefetch_throttle_test|prefetch_task_master_test|client_readonly_query_test|promotion_on_hit_test|file_storage_promotion_test|file_storage_test|probe'
bash scripts/ci/run_ssd_offload_smoke.sh
```

日志：`red_smoke.log`、`green_smoke.log`、`green_ctest.log`、`test_setup.diff`。
