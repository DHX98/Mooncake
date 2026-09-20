# INTERNAL — Task1 gate notes (eabc511f)

No A/B run. No absolute latency numbers.

## Code / scripts

- code: ssd-prefetch/pr3-exist-get-wiring @ eabc511f589280d208f87cac5881f2bf1f419c01
- scripts: v3-verify ttft-ab overlay (FINAL_ROUND names eabc511f)
- unit-test build: CMAKE_BUILD_TYPE=Release, BUILD_UNIT_TESTS=ON, RC=0
- deploy build: USE_ASCEND_DIRECT=ON, RC=0; not installed; not used

## Task1 compile

PASS. 0 errors. 0 prefetch-path warnings.

16 unrelated warnings:
- mooncake-integration/store/store_py_internal.h unused-function x12
- mooncake-store/tests/dfs_posix_test.cpp range-loop-construct x2
- mooncake-store/tests/master_service/dsl/scenario.cpp missing-field-initializers x1
- mooncake-store/tests/ha/leadership/high_availability_test.cpp unused WaitForServing x1

See gate/task1_warn_all.txt.

## Task1 format

FAIL. clang-format 20.1.8 + pre-commit 4.6.2 on a Windows worktree at
the same SHA (bench host has neither tool). Diff is wrap-only; do not
apply to PR3.

2 files:
- mooncake-store/include/prefetch_throttle.h — 3 wrap sites
- mooncake-wheel/tests/test_prefetch_on_exist.py — ruff-format
  (blank line + 3 assertEqual wraps)

Standalone body: format.diff and gate/format.diff

## Task2 / Task3

SKIPPED per fail policy (Task1 format FAIL).
