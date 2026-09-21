# Why A/B p99 went negative @ 104153ab

Audience: architect agent. Field did **not** change Mooncake C++ /
Python product files. Absolute milliseconds stay in this internal
pack and in `../final-round/INTERNAL.md`. Host names, employee IDs,
container names, and intranet paths are placeholders.

## 0. One-paragraph verdict

p99 is negative because **arm A is no longer SSD-bound**, while **arm B
still pays a get-side wait on a prefetch that does not register during
r1**. Body improved (p50 / p90). The worst 1 of 48 requests on B is
slower than A's worst. r2 (contamination) has all three gains positive.
This is not FILE_READ_FAIL (count 0). Compare the 9/18 v3-verify win:
B r1 is in the same band; A r1 collapsed from a ~14 s median to ~2 s.

## 1. Did the field change Mooncake code?

**No product edit.** Bench-host PR3 after the round:

- HEAD `104153ab9207e0bab8ae39adfe6260d4b0ddfaaa`
- branch `ssd-prefetch/pr3-exist-get-wiring`
- `git status --porcelain` empty

What the field *did* touch (not C++ / not committed to PR3):

| Change | Where | In 104153ab tree? |
|---|---|---|
| clang-format / ruff check | local Windows worktree, check-only | no |
| smoke retry 1: `PREFETCH_POLL_INTERVAL_SECONDS=2` | env wrapper | no |
| smoke retry 2: unpack `(key, type_hist)` | **gate-local copy** of the test | no (PR3 dirty stayed 0) |
| CRLF strip + `chmod +x` | v3-verify `ttft-ab/` overlay | scripts only |
| `HCCL_SOCKET_IFNAME` pin | overlay `serve.sh` / env | scripts only |
| deploy `patchelf` overlay into site-packages | runtime install | build artifact |

The official `test_prefetch_on_exist` TypeError is **already in
104153ab**: `_find_cold_key` / `wait_until` returns `(key, type_hist)`,
then `reference[cold_key]` uses that tuple as a dict key
(`mooncake-wheel/tests/test_prefetch_on_exist.py` around the
`return True, (key, type_hist)` / `cold_key = self._find_cold_key(...)`
pair). Field did not patch the committed file.

## 2. Scorecard (same numbers as `../final-round/`)

Primary = r1, gain = (A−B)/A. n=48, conc=4, so p99 ≈ the worst request.

| | median | mean | p90 | p99 |
|---|---|---|---|---|
| A r1 | 2226 | 2510 | 4296 | 8677 |
| B r1 | 2018 | 2383 | 3033 | 9344 |
| r1 gain | **+9.4%** | **+5.0%** | **+29.4%** | **−7.7%** |
| A r2 | 1843 | 1837 | 2145 | 2474 |
| B r2 | 1713 | 1650 | 1871 | 1943 |
| r2 gain | +7.0% | +10.2% | +12.8% | **+21.4%** |

Fill/overflow both arms 48/48. Failed requests 0. `FILE_READ_FAIL=0`.
`PENDING=0`.

## 3. Why p99 is the wrong headline

1. **Body of B is better.** p90 +29% with 0 failures. Prefetch is not
   a no-op on the typical request.
2. **n=48 makes p99 a single-request statistic.** One extra-slow B
   request (~0.7 s worse than A's worst) flips the gate.
3. **r2, same process, all three gains positive.** After the first
   measure pass the tail is gone. Do not read r1 p99 as “prefetch
   always hurts tail.”
4. **B did not regress vs the 9/18 win. A did.** Same recipe
   (256 MiB segment, `ssd_get_wait_ms=2000`, 48×16385, CONC=4):

   | | A r1 median | B r1 median | A r1 p99 | B r1 p99 | r1 p99 gain |
   |---|---|---|---|---|---|
   | v3-verify 9/18 (`8cdcc10f`, store md5 `363b669c`) | 14427 | 2135 | 16172 | 8919 | **+44.9%** |
   | PR3 104153ab (store md5 `d270ecea`) | 2226 | 2018 | 8677 | 9344 | **−7.7%** |

   B r1 median/p99 are in the same band as last time (2018 vs 2135,
   9344 vs 8919). A r1 median dropped ~6× (14427 → 2226). The +85%
   win was “A stuck on SSD at c=4, B pulled most of it back.” This
   round A already looks DRAM-like, so the same B cannot show +85%.

## 4. Evidence chain on arm B logs

`serve.sh` truncates logs at each arm start. Counts below are **arm B
only**. Arm A logs are gone.

### 4.1 Before r1: DRAM is not empty

After B overflow / settle (17:45–17:47), master:

- Mem **1.20 / 2.00 GB (59.9%)**
- Keys **3666**
- Promotion completed=0 failed=0

Overflow did **not** push the working set to disk-only. ~60% of the
2 GB segment is still MEMORY. That is the mechanical reason A can
print a ~2 s median: most gets do not wait on SSD.

Last win ended B at Mem 1.95/2.00 GB (97.5%), Keys 3840, Promotion
completed=503 failed=860. Different occupancy, different A.

### 4.2 During r1 (17:47:28–17:48:55): kick without register

| signal | r1 window | notes |
|---|---|---|
| `get-side kick` | **344** | all `disk_keys=40`, all `in_cooldown=0` |
| `prefetch_task_registered` | **0** | first line is 17:49:24 (r2) |
| Promotion completed/failed | **0 / 0** | still zero on every 10 s snapshot |
| `DRAM saturated` | **0** | 165 lines are 17:49–17:50 (r2) |
| `FILE_READ_FAIL` | 0 | |

Get-side kick is firing (40 disk keys per kick, 8 ranks). Master
`RegisterPrefetchTask` does **not** land until r2. Field hypothesis
for the architect (not proven in C++): r1 get waits up to
`ssd_get_wait_ms=2000` for a promotion that is not on the master
yet, then reads SSD. Body still wins from the 1.2 GB already in
DRAM; the worst request pays wait + SSD and loses to A's worst
SSD-only get.

### 4.3 During r2 (17:48:55–17:50:19): prefetch actually runs

- `prefetch_task_registered`: 1186 @ 17:49 + 200 @ 17:50 = 1386
- Promotion at 17:50:16: completed=531, failed=855, bytes=1.47 GB
- Mem 1.95 / 2.00 GB (97.6%), Keys 3840, SSD 17.32 GB
- `DRAM saturated, backing off`: 128 @ 17:49 + 37 @ 17:50
- kicks in r2: 248; the 202 `in_cooldown=1` kicks are this window
  (r1 had 0 cooldown)

So cooldown / DRAM pressure are **r2 phenomena**. They do not explain
r1 p99. They do show prefetch competing for the same 2 GB once it
starts completing.

## 5. Questions for the architect

1. Why does `get-side kick` log 344 times in r1 with `disk_keys=40`
   while `prefetch_task_registered` and Promotion stay 0 until r2?
   Dedup? pool delay? exist-path vs get-path? failed RPC not logged?
2. Why is 1.20 GB / 3666 keys still MEMORY after overflow+90 s settle
   on 104153ab, vs last win’s 97.5% full / 3840 keys? Weaker
   eviction/offload, lease pinning, or a different overflow mix?
3. Official smoke TypeError: `_find_cold_key` returns `(key, hist)`
   but callers index `reference[cold_key]`. Is the livelock poll
   fix incomplete (histogram added, unpack not updated)?
4. Gate bar is r1 p99 > 0. With n=48 that is one request. If A is
   already DRAM-resident, +85% is not a reachable comparison. Should
   the gate require a proven LOCAL_DISK-only working set before
   measure, or score r2 as well?

## 6. What this is not

- Not a field C++ regression: PR3 dirty=0, SHA pinned.
- Not FILE_READ_FAIL / PENDING sibling hang (H20 class).
- Not fill=0/48 or occupier NPU (both arms 48/48, cards empty at start).
- Not “prefetch never ran”: r2 registers 1386, completes 531, fails 855.
- Not “B got slower than last B”: B is within last win’s band; A changed.

## 7. Pointers

- Gate pack: `../final-round/` (commit `108b26c`)
- Last +85% pack: `../v3-verify/RESULT.md`
- Host full B logs stay on the bench (vllm ~177 MB, master ~210 MB);
  only tails were pushed earlier.
