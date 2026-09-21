# INTERNAL — 0327ddcb gate fail (no r1 measure)

Do not quote Task 3 r1 milliseconds from this directory. There are none.
Fill/overflow bench logs contain write-path TTFT; those are not A/B measure.

## Code / scripts

- code: ssd-prefetch/pr3-exist-get-wiring @ 0327ddcb1f59af995a9ac00242d7e41bf30b21fd
- dirty: 0
- scripts: v3-verify ttft-ab overlay (ssd_gate.py sidecar only; product C++/Python not edited)
- store overlay md5 (container, reused 104153ab): d270ecea149d2c1dfcf34e062544b660
- master overlay md5: 3fbef11a55bd49da52ab5af0db1918b0
- store.so md5: 818e9adf581fdc44be07b3f09f7dd5df
- CONC=4 MEASURE_CONCURRENCY=4 MAX_NUM_SEQS=4 GLOG_v=1
- lease: --default_kv_lease_ttl=${KV_LEASE_TTL_MS:-2000} (LEASE_TTL_MS=2000)
- vLLM segment 256MB; gate sidecar segment 4MB protocol=tcp master 127.0.0.1:50111
- run start: 2026-09-21T04:19:39Z; host run_ab pid dead after gate

## Task 1 / 2

SKIP this round. Binaries reused. C++ vs 104153ab = test file only.

## Task 3 r1

N/A. Did not enter measure. a_r1.* on the bench host is the stale 01:27 leftover and was not copied.

## Fill / overflow (this run only)

- A fill 48/48 duration 269.44s (bench rewritten 12:32 +0800)
- A overflow first 48/48, then one retry 96/96 duration 408.38s (12:46 +0800)
- no third overflow

## Gate

attempt=1 and attempt=2:
  SSD_GATE store setup segment=4194304 protocol=tcp master=127.0.0.1:50111
  AscendDirectTransport: cannot allocate local segment, ret: -1
  Failed to install Ascend transport / init transfer engine
  Failed to create client on port 12504 after 20 retries
  RuntimeError store.setup ret=-1
  n_fill_keys=1920 n_sampled=64 MEMORY=0 LOCAL_DISK=0 LOCAL_DISK-only=0 MISSING=64 GATE_PASS=0
  MISSING=64 is the except path, not a replica-desc sample of the 1920 keys.

## Master after overflow retry (04:48:17)

Mem Storage: 866.11 MB / 2.00 GB (42.3%)
SSD Storage: 22.64 GB / 18.00 TB
Keys: 5760 (soft-pinned: 0)
Clients: 9
Eviction: Success/Attempts=82/284 keys=5456 size=15.21 GB
Mem Eviction: Success/Attempts=82/284 keys=5456 size=15.21 GB
Discard: Released/Total=3320/3320
Promotion: in_flight=0 admitted=0 completed=0 failed=0
Offload on master DID run. Gate fail is sidecar setup(), not proven LOCAL_DISK-only absence.
