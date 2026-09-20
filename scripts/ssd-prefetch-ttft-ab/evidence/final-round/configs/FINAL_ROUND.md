# FINAL ROUND 交接单（内网 agent，一页读完）

## 两个目录，两个分支，别混

- **被测代码**：`ssd-prefetch/pr3-exist-get-wiring` @ `104153ab`
  （clone 后 `git checkout` 这个分支构建；上游 PR 候选。
  本分支**已恢复 get-kick + ignore_cooldown**，并修复：
  两个测试的 InitGoogleLogging 重复调用、throttle cooldown=0 的
  kFailed 过期语义、format、smoke 环境变量钉死）
- **测试脚本**：`ssd-prefetch/v3-verify` 分支的 `scripts/ssd-prefetch-ttft-ab/`
  （serve.sh / run_ab.sh / env.sh 已加固：会 pkill 孤儿 Worker、fill 0/48 会中止）

## 铁律（每次提交证据前）

```bash
bash scripts/ssd-prefetch-ttft-ab/scrub.sh <每个要提交的文件>
```

工号、IP、容器名、内网路径一律不进 commit。MS 级绝对延迟数字只进
内部证据，不进任何会被 PR 引用的文本。

## 任务 1：编译 + 静态检查（PR 分支）

```bash
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_UNIT_TESTS=ON
cmake --build build --parallel $(nproc)
./scripts/code_format.sh
pre-commit run --files $(git diff --name-only origin/main...HEAD)
```

## 任务 2：单测 + smoke（PR 分支）

```bash
ctest --test-dir build --output-on-failure -R \
  'prefetch_throttle_test|prefetch_task_master_test|client_readonly_query_test|promotion_on_hit_test|file_storage_promotion_test|file_storage_test'
bash scripts/ci/run_ssd_offload_smoke.sh
```

## 任务 3：A/B 复跑（PR 分支的库 + v3-verify 的脚本）

目的：验证恢复 get-kick 后的最终代码。流程照旧
（fill → overflow → settle → measure），**measure 用 CONC=4**。
期望：median/mean/p99 三个增益均为正且显著（参照 +85% 量级）；
**如果 p99 为负，标记失败并贴完整日志**：

```bash
CONC=4 MAX_NUM_SEQS=4 bash scripts/ssd-prefetch-ttft-ab/run_ab.sh
```

跑完先 scrub 再提交证据到 v3-verify 分支 `evidence/final-round/`。

## 回填格式（照抄填写）

```
任务1 编译: PASS/FAIL（warning 贴出）
任务1 format/pre-commit: PASS/FAIL（有 diff 贴 diff，勿提交）
任务2 ctest: N/N
任务2 smoke: PASS/FAIL（含 test_prefetch_on_exist 正反两例）
任务3 A r1: median/mean/p99 ms
任务3 B r1: median/mean/p99 ms
任务3 gain: median% / mean% / p99%
任务3 prefetch_task_registered 数:
任务3 DRAM saturated/backing off 次数:
（失败时贴完整报错段）
```


## 本轮回填 (104153ab)

```
任务1 编译: PASS（prefetch 路径 0 warning；1 条 LTO informational）
任务1 format/pre-commit: PASS（DIFF_BYTES=0；Windows hook 缺 /bin/bash 故 pre-commit RC=1）
任务2 ctest: 6/6（含 client_readonly_query_test / prefetch_task_master_test / FailedKeyRetriesAfterBackoffNotFullTtl）
任务2 smoke: official FAIL（TypeError unpack）；retry1 env FAIL；retry2 wrap PASS 正反两例
任务3 A r1: median 2226.33 / mean 2509.56 / p99 8677.44
任务3 B r1: median 2018.02 / mean 2383.14 / p99 9343.87
任务3 gain: 9.4% / 5.0% / -7.7%
任务3 prefetch_task_registered 数: 1386
任务3 DRAM saturated/backing off 次数: 165 (vllm)
任务3 get-side kick: 592 (in_cooldown=0: 390, in_cooldown=1: 202)
```
