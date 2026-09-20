# H20 clean-gate official SSD-prefetch TTFT A/B (internal)

GLOG_v=0 on official serve/measure. Fresh NVMe SSD per arm
(`ssd_ab2` / `ssd_ab2_b`). FILE_READ_FAIL gate before each measure.
Hung first r1 on both arms (46/48, 120s stall) voided; remesured once
on the same SSD after a <=30s GLOG_v=1 evidence window. store.so stayed
stock. hybrid unpack kept. worker fail-fast not re-applied.

## TTFT (screen `*.bench.log`)

| arm | success/fail | median | mean | p99 |
|---|---|---:|---:|---:|
| A_R1 | 48/0 | 3720.39 | 3619.49 | 10801.07 |
| A_R2 | 48/0 | 3698.35 | 3276.31 | 8713.38 |
| B_R1 | 48/0 | 2700.54 | 3376.81 | 10766.51 |
| B_R2 | 48/0 | 2620.99 | 2895.87 | 5257.80 |

gain% = (A-B)/A*100

| round | median gain | mean gain | p99 gain |
|---|---:|---:|---:|
| r1 | 27.41% | 6.70% | 0.32% |
| r2 | 29.13% | 11.61% | 39.66% |

Fill/overflow (c=1), all 48/0:

| arm | fill med/mean/p99 | overflow med/mean/p99 |
|---|---|---|
| A | 1317.25 / 1444.08 / 4447.81 | 1320.17 / 1322.12 / 1377.08 |
| B | 1316.30 / 1441.84 / 4449.36 | 1315.44 / 1316.59 / 1373.24 |

## Gates (this arm log only)

| gate | FILE_READ_FAIL vllm | FILE_READ_FAIL master | result |
|---|---:|---:|---|
| A before r1 | 0 | 0 | PASS |
| A before r2 (after r1 remesure) | 0 | 0 | PASS |
| B before r1 | 0 | 0 | PASS |
| B before r2 (after r1 remesure) | 0 | 0 | PASS |

Official remesure/r2 measures that entered after a PASS gate: FILE_READ_FAIL=0
at gate time. First r1 attempts were voided (46/48 stall); hang logs had
FILE_READ_FAIL >> 0 and still-pending=0 under GLOG_v=0.

## Hang / remesure

- A r1 first: stall 46/48 for 120s. Voided. GLOG_v=1 <=30s on same `ssd_ab2`.
  Remesure GLOG_v=0: 48/0.
- B r1 first: stall 46/48 for 120s. Voided. GLOG_v=1 <=30s on same `ssd_ab2_b`.
  Remesure GLOG_v=0: 48/0.
- store.so not swapped. engine.so unchanged.

## Hashes

- engine.so `275b0687e217c9013f527e3e5faf980a` (required)
- store.so `668c0f0819e00738ac1d2d9e92a4df28` (stock eabc511f / bak_frf)

## Knobs

PLATFORM=h20 PREFIX_TOKENS=16385 NUM/OVERFLOW=48 FILL_C=1 MEASURE_C=4
MAX_NUM_SEQS=4 SETTLE=90 SEGMENT=256MB SSD_GET_WAIT_MS=2000 GLOG_v=0
`--kv-cache-dtype fp8` `kv_load_failure_policy=recompute` `promotion_on_hit=false`
TP=8. NVIDIA FP8 weights. No /tmp SSD. No docker pull. No engine rebuild.

## Sources

- `results/{a,b}_{fill,overflow,r1,r2}.bench.log` + json
- hang voids: `results/{a,b}_r1.hang.bench.log` if present
- configs: serve.sh env.sh mooncake_a.json mooncake_b.json platforms/h20.env
- `logs/` tails + host log + gate excerpts
- `greps.txt`
