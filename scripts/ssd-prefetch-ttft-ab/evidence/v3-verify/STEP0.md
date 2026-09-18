# v3 r2 (winning, 2026-09-17 22:46-23:36) zero-cost grep

Logs (same inode via bind):
`/home/tester/perf_test_prefetch_v3/logs/{master,vllm}.log`

| pattern | master.log | vllm.log | combined |
|---|---:|---:|---:|
| DRAM saturated, backing off | 0 | 122 | 122 |
| memory-pressure cooldown | 0 | 1525 | 1525 |
| prefetch_task_registered | 2307 | 0 | 2307 |
