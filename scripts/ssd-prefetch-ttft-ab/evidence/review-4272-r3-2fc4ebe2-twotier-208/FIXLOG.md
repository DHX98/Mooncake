# FIXLOG twotier-208

## 2026-10-16 step 0
NPU 0-7 had no processes before this run (HBM about 3.4/64 GB, AICore 0).
serve.sh stop ran inside mc-r3-208 against model /data/DeepSeek-V4-Flash-w8a8-mtp
and rpc 50111. Ports 8271/50111/9021/50211 were not listening.

## 2026-10-16 step 1 smoke
Harness followup_verify.sh, MC_SRC 2fc4ebe2.
Three smoke groups OK, FAILED_SEEN=False. Group 3 OK (skipped=1).
waitmix probe lines = 1:
  waitmix probe 0: ['LOCAL_DISK', 'DISK']
  mem key replica types: ['LOCAL_DISK', 'DISK']
mixed batch_get results line absent. The skip is the test's own skipTest:
the small key lost its MEMORY replica under overflow, so the mixed
precondition was not met. The line "batch_get results [8388608]" belongs
to the non-mixed wait-lease test. Recorded and continued. No product change.

## 2026-10-16 step 1 memcpy bisect
35199bd5 CTEST=FAIL. Failed case:
  TcpLocalMemcpyAutoEnableTest.MetadataRemoteReplicaOnSameTcpHostUsesTransferEngine
  (5 passed, 1 failed, ctest 21.61s)
986f385c CTEST=PASS (1/1, 21.61s). The 986 binary was already built
(2026-10-15 17:32); ninja reported no work. Conclusion: the failure is
present on the post-merge pre-restructure commit and absent on the
pre-merge commit, i.e. the upstream merge range. No semantic fix.

## 2026-10-16 step 2
Reused the arm-3 overlay built earlier today. Not rebuilt.
BASE 2fc4ebe2, git apply clean, BUILD_RC=0.
libmooncake_store.so md5 528a28355330b23d67c4539b207728ab
size 509187840, differs from unpatched a588165909244cc3c52d73b075514454.
Patch matches kick_decouple.patch (one gate, measurement only). Not committed.

## 2026-10-16 harness
progress.sh: the progress push passes PROGRESS_HTTP_PROXY via git -c.
The machine gitconfig proxy on port 3128 times out. Store and engine
processes stay proxy-free.

## 2026-10-16 store e0 first attempt
Defaults OBJECT_BYTES=100MiB SEGMENT_BYTES=256MiB, probe gap 0.5s, lease 2000ms.
Trial 0 overflow puts returned rc=-200 (insufficient space) from round 0.
After 14 rounds the target was still ['MEMORY', 'DISK']. No jsonl rows.
The driver exited. The master on rpc 50211 was killed; the port is free.
Retry, same on every arm: OBJECT_BYTES=64MiB, SEGMENT_BYTES=512MiB,
PROBE_GAP_SEC=3. Sizes are inside the authorized range. The extra probe
gap is so a replica-desc poll does not re-lease the target before a 64MiB
offload can finish. Watermark, lease TTL, and arm configs are unchanged.

## 2026-10-16 store e0 second attempt
OBJECT_BYTES=64MiB, SEGMENT_BYTES=512MiB, PROBE_GAP_SEC=3.
Master did evict (52 successes, 1.56 GB) but the target stayed
['MEMORY', 'DISK', 'LOCAL_DISK']. Eviction deferred the key for disk
offload, then the next flood ran immediately after replica_types(),
which had just renewed the read lease, so the target was never chosen.
Fix: after each probe, sleep the lease TTL before the next flood.
Same sizes as the second attempt. All seven arms rerun; none had rows.

## 2026-10-16 engine attempt 1
Arm 1 died before fill. vLLM ZMQ IPC path was longer than 107 bytes
because TMPDIR was under engine-run/tmp. No bench log was produced.
Retry uses TMPDIR=/tmp/tt208-eng. SSD path is unchanged and is not under /tmp.

## 2026-10-16 engine attempt 2
The first matrix.sh survived the docker-exec kill and was reparented to init.
When the retry vLLM became ready, both matrices started fill into the same
m1_pure_fill files. Bench was still 0/12, so no completed request was kept.
Both trees were killed, logs removed, and one engine pair was started.

## 2026-10-16 evidence close
Store matrix and engine arms 1/3/4 finished. Engine arm 1 was restarted
once after a duplicate matrix filled the same files at 0/12, and once
after the ZMQ IPC path limit. No completed request from those attempts
was kept. Final r1 files are the clean single-matrix run.
Counter grep of the vLLM log found no get-side kick lines; LEASE counts
are 0. Evidence copied here and pushed on ssd-prefetch/v3-verify.
