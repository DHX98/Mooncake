# v3-verify RESULT (field)

Branch: `ssd-prefetch/v3-verify` @ `8cdcc10f`
Store overlay md5: `363b669c`
Workdir: `/home/tester/perf_test_prefetch_v3_verify`
Container: <bench-container> (no new container)
VERIFY START: 2026-09-18T07:32:32Z
VERIFY DONE:  2026-09-18T08:22:51Z
Knobs: MAX_NUM_SEQS=4, MEASURE_CONCURRENCY=4, GLOG_v=1, master `--v=1` off,
segment 256MB, wait=2000, prefix 16385, overflow 48, promotion_on_hit=false.

## Why the first two A-fills died

Field, not HANDOFF: EngineDead / `sample_tokens` 300s was **not** prefetch kick
and **not** master `--v=1`.

After the first EngineDead, `serve.sh stop` only `pkill`'d `vllm serve`.
Orphan `VLLM::Worker` (PPID 1) stayed on NPU 0-5 at 64MB/card. The next
`/v1/models` came up, first 16k generate hung 300s, bench returned 0/48,
script continued because `vllm bench` exits 0 even when every request failed.

Replay `serve.sh` was also missing the env the winning v3 actually exported
(`HCCL_IF_IP`, `GLOO/HCCL_SOCKET_IFNAME`, `MC_METADATA_SERVER=P2PHANDSHAKE`).
Those were restored. The decisive fix was **kill -9 orphan workers** and
hardening `serve.sh stop` to reap `VLLM::Worker` / `VLLM::EngineCore`.

## c=4 TTFT (screen logs, not JSON)

Primary = measure r1. gain% = (A-B)/A*100. All 48/48.

| arm | round | median ms | mean ms | p99 ms |
|-----|-------|-----------|---------|--------|
| A   | r1    | 14426.96  | 13583.52 | 16172.33 |
| B   | r1    | 2135.01   | 2523.33  | 8918.93 |
| A   | r2    | 13646.08  | 11218.35 | 22704.77 |
| B   | r2    | 1694.55   | 1640.29  | 2176.20 |

r1 gain: median **+85.20%**  mean **+81.42%**  p99 **+44.85%**

Win bar (r1 median AND mean AND p99 all B<A): **met**.

A at c=4 is much slower than the 9/17 v3 r2 win at c=2 (A 1497/1901/6820).
That is a different concurrency, not a regression of the C++ wait-budget fix.

## get-side kick (actual log format)

VLOG prints `in_cooldown=0|1`, **not** `true|false`. HANDOFF grep for
`in_cooldown=true` misses this binary.

| metric | count |
|--------|------:|
| `SSD prefetch: get-side kick` | 592 |
| kick `in_cooldown=0` | 381 |
| kick `in_cooldown=1` | 211 |
| `prefetch_task_registered` master / vllm | 1363 / 0 |
| `DRAM saturated` master / vllm | 0 / 177 |
| `memory-pressure cooldown` master / vllm | 0 / 2150 |

Sample (B measure, 08:20:12Z):
`SSD prefetch: get-side kick, disk_keys=40, in_cooldown=0`

Do **not** treat a `true`-string count of 0 as "delete ignore_cooldown".
Cooldown **did** fire (2150 vllm lines). The kick flag is an int.

## Promotion / SSD (no `SsdMetric` string)

Last master snapshot 08:22:43Z:
Mem 1.95/2.00 GB (97.5%), Keys 3840, SSD 17.39 GB,
Promotion completed=503 failed=860 cancelled=0 expired=0 bytes=1.40 GB,
rejected(freq/wm/cap)=0/0/0.
Discard Released/Total=1443/1443.

## Logs

- host: `$HOST/logs/run_ab.host.log`
- vllm: `$HOST/logs/vllm.log` (627 MB, GLOG_v=1)
- master: `$HOST/logs/master.log` (210 MB)
- screen: `$HOST/results/{a,b}_r1.bench.log`
- this file: `$HOST/RESULT.md`
