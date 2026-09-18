# SSD prefetch TTFT A/B (DSV4 16k+1)

Human-readable replay of the v3 round-2 measurement that landed this
bugfix. **Primary metric is measure r1.** `gain = (A - B) / A * 100`
(positive = prefetch faster).

## After the fix (v3 r2, 2026-09-17, <bench-host> / <bench-container>)

| arm | median TTFT | mean TTFT | p99 TTFT |
|---|---:|---:|---:|
| A r1 offload only | 1497.80 ms | 1901.99 ms | 6820.60 ms |
| B r1 offload+prefetch | 1419.47 ms | 1805.45 ms | 5321.74 ms |
| **gain** | **+5.23%** | **+5.08%** | **+21.98%** |

Before the fix the same B arm hit p99 ~118 s / mean ~21 s because
`ssd_get_wait_ms` was applied **per key**. After the fix B is better
than A on median, mean, and p99.

Screen logs (not the machine JSON) are in `evidence/`:

- `a_r1.bench.log` / `b_r1.bench.log` — headline
- `a_r2.bench.log` / `b_r2.bench.log` — contamination check

## What the scripts do

```
run_ab.sh
  ├─ empty THIS experiment SSD only (never ssd_dsv4 / ssd_8b)
  ├─ gen_dataset.py          48 prefixes × 16385 tokens
  ├─ ARM=a  serve.sh start   master + vLLM, prefetch off
  ├─ fill → overflow 48 → settle 90s → SSD-only check
  ├─ vllm bench serve c=2    → a_r1.bench.log  (tee, human)
  ├─ recycle SSD, restart
  └─ ARM=b  same flow, prefetch on → b_r1.bench.log
```

Run **inside** `<bench-container>` (or any container that already has the
all-in-one Mooncake + DSV4 vLLM stack). From the host:

```bash
# host
docker exec <bench-container> bash --noprofile --norc \
  /path/to/scripts/ssd-prefetch-ttft-ab/run_ab.sh
```

Or step by step (same container):

```bash
cd /path/to/scripts/ssd-prefetch-ttft-ab
. ./env.sh
./serve.sh stop
./serve.sh start          # ARM=a by default
./wait_ready.sh
./bench.sh fill.json      # tee results/fill.bench.log
# ... overflow, settle, then:
ARM=a ./bench.sh a_r1.json
```

Knobs that must stay (this is the scenario the numbers came from):

- prefix 16385 / max_model_len 20480
- `global_segment_size=256MB`
- `ssd_get_wait_ms=2000` (now a **batch** budget)
- measure `--max-concurrency 2`
- master `--promotion_on_hit=false --enable_offload --offload_on_evict`
- real NVMe SSD, never `/tmp`
