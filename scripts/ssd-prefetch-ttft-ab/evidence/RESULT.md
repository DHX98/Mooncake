# v3 r2 screen evidence (2026-09-17, 80.48.37.141, prefetch-916)

Copied from `vllm bench serve` stdout (`*.bench.log`). JSON files are
not the record of record.

Primary = **measure r1**, 48 prompts, `--max-concurrency 2`, prefix 16385.
`gain = (A - B) / A * 100`.

| | median | mean | p99 |
|---|---:|---:|---:|
| A r1 | 1497.80 ms | 1901.99 ms | 6820.60 ms |
| B r1 | 1419.47 ms | 1805.45 ms | 5321.74 ms |
| gain | **+5.23%** | **+5.08%** | **+21.98%** |

Before this bugfix, B r1 p99 was ~118523 ms (per-key 2000 ms wait).

## A r1 (`a_r1.bench.log`)

```
============ Serving Benchmark Result ============
Successful requests:                     48
Failed requests:                         0
Maximum request concurrency:             2
Benchmark duration (s):                  114.39
---------------Time to First Token----------------
Mean TTFT (ms):                          1901.99
Median TTFT (ms):                        1497.80
P50 TTFT (ms):                           1497.80
P90 TTFT (ms):                           3654.42
P99 TTFT (ms):                           6820.60
==================================================
```

## B r1 (`b_r1.bench.log`)

```
============ Serving Benchmark Result ============
Successful requests:                     48
Failed requests:                         0
Maximum request concurrency:             2
Benchmark duration (s):                  111.82
---------------Time to First Token----------------
Mean TTFT (ms):                          1805.45
Median TTFT (ms):                        1419.47
P50 TTFT (ms):                           1419.47
P90 TTFT (ms):                           3648.78
P99 TTFT (ms):                           5321.74
==================================================
```

## A r2 / B r2 (contamination check, not the headline)

```
A r2  Mean 1439.81  Median 1472.07  P99 1674.54
B r2  Mean 1284.50  Median 1380.40  P99 1506.41
```
