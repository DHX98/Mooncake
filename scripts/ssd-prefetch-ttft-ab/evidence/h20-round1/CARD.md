# H20 round1 official A/B measure (internal)

Official passing H20 SSD-prefetch TTFT A/B. First official run_ab 0/48
(~17:31-17:38 a_r1/b_r1), hung 47/48 r2 logs, and leftover 17:56 r1 are
not this win and are not in this tree.

## TTFT (48/48)

| arm | success/fail | median | mean | p99 |
|---|---|---:|---:|---:|
| A_R1 | 48/0 | 2605.86 | 3183.65 | 10768.36 |
| A_R2 | 48/0 | 2994.47 | 2949.48 | 5113.44 |
| B_R1 | 48/0 | 2580.78 | 3197.01 | 10791.03 |
| B_R2 | 48/0 | 2561.11 | 2483.34 | 5078.65 |

A fill/overflow: 48/0 and 48/0 from official one_arm a (`a_fill_retry` / `a_overflow_retry`).
B fill/overflow: 48/0 and 48/0 from `.bpass` (18:14 / 18:16).

## ENGINE_MD5

`275b0687e217c9013f527e3e5faf980a` unpack=0

## PATH notes

- hybrid unpack: vLLM scheduler `_update_requests_with_invalid_blocks` group-aware rewind; unpack hits = 0
- store.so pending-fail: FILE_READ_FAIL / still-pending path kept
- worker drop-failed-keys: GET fail-fast (8s) + batch_remove value<0

Attempt2 vllm.log (after truncate): unpack=0 FILE_READ_FAIL=616 PENDING=0 DROPPED=8

## Sources

- A measure: `results/a_r1_retry.bench.log` / `a_r2_retry.bench.log` (attempt2, parsed 48/48 before copy)
- A fill/overflow: official one_arm a `a_fill_retry` / `a_overflow_retry`
- B measure + fill/overflow: `results/b_*_retry.*.bpass` and `bpass/` (frozen `h20-round1-bpass`)
- configs: serve.sh env.sh mooncake_a.json mooncake_b.json
- vllm.log: tail only
