# GATE — 0327ddcb arm A LOCAL_DISK (2026-09-21)

Code: `ssd-prefetch/pr3-exist-get-wiring` @ `0327ddcb` (dirty 0).
Scripts: `ssd-prefetch/v3-verify` ttft-ab overlay. CONC=4, lease 2s.
Binaries reused from 104153ab (`libmooncake_store.so` md5 `d270ecea149d2c1dfcf34e062544b660`).
C++ vs 104153ab = test file only; Task 1/2 not re-run.

Stopped at arm A LOCAL_DISK gate after attempt 2. No r1 measure.

## Scorecard

```
任务1 编译: SKIP this round (already green; reused 104153ab binaries; C++ vs 0327ddcb = test file only)
任务1 format/pre-commit: SKIP
任务2 ctest/smoke: SKIP
任务3 A r1: N/A (stopped at LOCAL_DISK gate)
任务3 B r1: N/A
任务3 gain: N/A (p99 N/A, not a negative-p99 fail; gate fail)
任务3 prefetch_task_registered 数: N/A (no measure)
任务3 DRAM saturated/backing off 次数: N/A
任务3 gate: FAIL attempt=2 reason=store.setup ret=-1 (tcp sidecar). listed fill keys=1920. sampled=64 all recorded MISSING via except path. overflow retry 48->96. Master after retry: Mem 42.3% of 2GB, SSD 22.64GB, evicted keys=5456. Did not enter measure.
```

## What the gate measured

- fill 48/48; overflow 48 then the one allowed retry 96/96. No third overflow.
- listed 1920 fill keys via `http://127.0.0.1:9021/get_all_keys`.
- overlay `ssd_gate.py` sidecar: `MooncakeDistributedStore.setup` protocol=tcp, segment=4MB, master `127.0.0.1:50111`.
- both attempts: `RuntimeError store.setup ret=-1` then histogram 64/64 MISSING (except path, not a replica query).
- Master after retry (still meaningful): Mem 866.11 MB / 2.00 GB (42.3%), SSD 22.64 GB, Keys 5760, Eviction Success/Attempts=82/284 keys=5456 size=15.21 GB. Offload on master DID run.
- Gate failed because the sidecar tcp client could not `setup()`, not because LOCAL_DISK-only was proven absent.

## Files

- `a_ssd_gate.txt`, `a_fill_keys.txt` (count + 5 samples), `a_ssd_gate_fail/`
- `results/a_fill.bench.log`, `results/a_overflow.bench.log` (this run; stale r1 not copied)
- `logs/run_ab.host.log.tail` (SSD_GATE + `store.setup ret=-1`)
- `logs/master_admin_metrics.last.txt`
- overlay `ssd_gate.py`
- `code_store_lease.txt` (serve lease line, CODE_HEAD, store md5)
