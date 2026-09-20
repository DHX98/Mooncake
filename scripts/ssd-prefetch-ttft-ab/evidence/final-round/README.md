# final-round evidence (PR3 exist-get-wiring @ eabc511f)

Code under test: `ssd-prefetch/pr3-exist-get-wiring` @ `eabc511f589280d208f87cac5881f2bf1f419c01`

Replay scripts: `ssd-prefetch/v3-verify` `scripts/ssd-prefetch-ttft-ab/`
(on-box overlay; FINAL_ROUND names eabc511f). A/B was not run.

## Task 1 / 2 / 3

任务1 编译: PASS（prefetch 路径 0 warning；16 条无关 warning 见 INTERNAL）
任务1 format/pre-commit: FAIL（diff 见 format.diff，勿提交）
任务2 ctest: SKIP（任务1 FAIL，按 fail policy 未跑）
任务2 smoke: SKIP（任务1 FAIL，按 fail policy 未跑）
任务3 A r1: SKIP
任务3 B r1: SKIP
任务3 gain: SKIP
任务3 prefetch_task_registered 数: SKIP
任务3 DRAM saturated/backing off 次数: SKIP

format.diff: 2 files, wrap-only (`prefetch_throttle.h` 3 wrap sites;
`test_prefetch_on_exist.py` blank line + 3 assertEqual wraps).
Do not apply to the PR branch.

Deploy build finished RC=0 with USE_ASCEND_DIRECT=ON. Not installed and
not used for A/B.
