# Get-side decomposition matrix — method

This harness answers one review question: **which get-side mechanism earns
what**. It extends the existing A/B (`run_ab.sh`) without changing its
defaults — `run_ab.sh` keeps working exactly as before.

## What it runs

`matrix.sh` = 6 arms × 2 batch shapes. Every arm is the proven sequence:
fresh SSD dir → serve start → fill → overflow → settle → measure → stop.
Same datasets and seeds as `run_ab.sh` (48 × 16k, overflow 48, seed 42/1042).

| arm | build | prefetch | wait | on_hit | isolates |
|---|---|---|---|---|---|
| 1 | PR tree | off | 0 | off | baseline (offload only) |
| 2 | PR tree | on | 0 | off | exist-side prefetch only (no kick, no wait) |
| 3 | **decouple build** | on | 0 | off | + kick, no wait |
| 4 | PR tree | on | on | off | current PR head (kick + wait) |
| 5 | PR tree | off | 0 | on | promotion-on-hit only |
| 6 | PR tree | on | on | on | both |

Pairwise reads: **3v4** = wait's isolated benefit; **2v3** = kick's isolated
benefit; **5v4** = kick path vs promotion_on_hit; **5v6** = value of
enabling both; **1v2** = exist-side base.

## Arm 3's build (the coupling breaker)

Main-line code fires the get-side kick only when `ssd_get_wait_ms > 0`, so a
zero/nonzero wait comparison cannot isolate waiting. Arm 3 must be built
from the PR tree **plus `kick_decouple.patch`** (one gate line; measurement
only, never for the PR). Put its store libs in a directory and point
`OVERLAY_DIR_3` at it; `matrix.sh` copies the overlay into `$PKG` before arm
3 and records the md5. Without `OVERLAY_DIR_3` arm 3 would silently
duplicate arm 2, so the script refuses to run it.

## Batch shapes

- **pure**: the existing A/B form. After overflow+settle every measured
  request's blocks are all SSD-only (48 unique prefixes, one pass, nothing
  revisited). This stays the primary shape for all pairwise reads.
- **mixed**: each measured request reads ~45% of its blocks from DRAM and
  the rest from SSD. Mechanics per rep: mini-overflow (rep≥2) → warm pass
  over a small subset (`MIXED_PREFIXES=6`) whose prompts splice the original
  45% head onto an alien tail at FULL length (a truncated ~7k prompt can
  fall under the connector's external-cache length threshold and never
  reach the store; at full length head blocks are cached token-identically,
  the alien tail misses by content) → immediate measure of the same 6 full
  prompts. The subset is
  small on purpose: the churned DRAM (~256MB) can only hold a few prefixes'
  heads, so warming all 48 would re-evict the early ones. Sample size is
  small (6/rep × `MIXED_REPS=2`); treat mixed medians as directional, pure
  shape stays primary.

## Hard gates (abort / invalidate)

- fill successful requests = 0 → abort (same as run_ab.sh).
- `OVERLAY_DIR_3` missing when arm 3 is selected → abort before measuring.
- any `LEASE_EXPIRED` in master or vllm log of an arm → the arm is flagged
  `CHECK` in the summary; the round-2 lease fix must hold under load, so a
  nonzero count invalidates the run and gets investigated first.
- SSD dir safety: refuses paths matching other experiments (`ssd_dsv4`,
  `ssd_8b`, `prefetch_2646`, `/tmp`).

## Settle rule

Default `SETTLE_SEC` comes from env.sh (90s), which the proven A/B used
because fills complete cleanly here. If the master log shows
`REPLICA_IS_NOT_READY` on prefetch registration (stuck-put reaper, 600s
TTL), re-run the affected arm with `MATRIX_SETTLE_SEC=700` — do not compare
an arm that registered zero promotions.

## Output

Per arm×shape: `m{arm}_{shape}[_repN]_r1.{json,bench.log}` plus
`m{arm}_{shape}.counters.log` (LEASE_EXPIRED, promotion lines, kick lines).
Final table from `summarize_matrix.py`: TTFT mean/median/p90/p99 per arm,
the five pairwise reads on both shapes, and the LEASE_EXPIRED gate.

## ① Follow-up verification (separate, run first)

`followup_verify.sh` — re-runs the SSD-offload smoke (the mixed-batch case
must EXECUTE: it prints `waitmix probe` lines and `mixed batch_get results`;
a skip means the lease pin did not hold) and bisects the one newly failing
`client_tcp_local_memcpy_test` across `35199bd5` (post-merge, pre
restructure) and `986f385c` (pre-merge). Env: `MC_SRC`, `BUILD_DIR`,
`BISECT_ROOT`, `CMAKE_FLAGS` (defaults match the 208 card).

## Two-tier redesign (after the 6h/arm pace proved infeasible)

The engine matrix at 48 prefixes / c=2 costs ~6h per arm AND cannot resolve
the mechanisms: 16k-token prefills are compute-dominated there (baseline and
prefetch arms both median ~123s), so get-side differences drown in queueing
noise. The matrix is therefore split into a cheap, precise store tier and a
small engine anchor tier.

### Tier 1 — store level (primary evidence): `store_matrix.sh`

Drives store_py directly (no vLLM/NPU): 100MB objects, 256MB segment, 15
trials per arm, minutes per arm. Measurement granularity = get() latency,
which is exactly the granularity the review asks about. Every trial logs
pre/post replica types (traceable store state) into
`store_matrix_<arm>.jsonl`; build md5 recorded per arm.

| arm | config | answers |
|---|---|---|
| e0 | offload only | raw SSD-read reference |
| e1a | prefetch, wait=0 | get arrives mid-promotion → SSD fallback |
| e1b | prefetch, wait=500 | get waits out promotion → DRAM read |
| e1c | e1b + mixed batch [resident A + cold K] | mixed-batch emphasis |
| e2a | prefetch+kick | cold-key touches 1/2/3 |
| e2b | on_hit only (threshold=2) | admission-gated touches |
| e2c | both | coexistence |
| e1d | optional, needs decouple overlay | kick rescues a cooldown-dropped probe |

Pairwise: **E1a vs E1b = the wait's isolated benefit (point 1)**; E0 vs E1b
= get path as a whole; E2 touch series + "first DRAM after touch #N" =
kick's first-touch promotion vs on_hit's gated admission (point 2).

### Tier 2 — engine anchor: `run_engine_pair.sh`

Only the one comparison that must also hold at vLLM TTFT level:
**arm 3 (kick, no wait) vs arm 4 (kick+wait)**, plus arm 1 as reference.
Mini protocol: `NUM_PREFIXES=12`, measure at **c=4** (the queue window is
where TTFT differences live — the stopped c=2 arms at ~123s median on both
sides are the counter-evidence), ~1h per arm, pure shape only. Everything
else is answered at the store tier; the aggregate TTFT claim remains the
PR's original A/B (c=4, DRAM-constrained, median 85.2%).

## Live progress (every 10 min)

All orchestrators source `progress.sh`: a heartbeat writes a rolling
`PROGRESS.md` in the run's result dir every `PROGRESS_INTERVAL` seconds
(default 600 — timestamp, current arm/phase from the state file, last
meaningful log lines). With `PROGRESS_REMOTE_SRC` set to a local clone of
the fork, the file is also amended + force-pushed to branch
`ssd-prefetch/v3-progress` every `PROGRESS_PUSH_EVERY` seconds (default
1800, best-effort; network failures never break the run). Watch either the
local file or that branch; evidence history on v3-verify stays clean.
