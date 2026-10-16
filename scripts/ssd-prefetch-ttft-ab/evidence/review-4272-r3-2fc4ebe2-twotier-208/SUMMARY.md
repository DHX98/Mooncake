# Two-tier review on 208, tree 2fc4ebe2

Harness `ssd-prefetch/v3-verify` at `2a6c8810`. Store libs for arms other
than engine arm 3 are the unpatched build, md5 `a588165909244cc3c52d73b075514454`.
Engine arm 3 used `kick_decouple.patch` on that same commit; overlay md5
`528a28355330b23d67c4539b207728ab`. The patch was not committed.
Store tier: object 64 MiB, segment 512 MiB, 15 trials, probe gap 3 s.
Engine tier: 12 prefixes, measure concurrency 4, pure shape only.

## a) Isolated wait

Store get1 median, E1a (prefetch, wait 0) 109.5 ms to E1b (prefetch, wait 500)
123.6 ms, about -13%. E0 (offload only) 110.2 ms to E1b 123.6 ms, about -12%.
On both E1a and E1b the first get stays at SSD speed and the second get is
about 25 ms, after a MEMORY replica appears. The 500 ms wait did not turn
the timed get into a DRAM read.

Engine r1 median TTFT, arm 3 (kick, wait 0) 215.9 s to arm 4 (kick, wait 2000)
277.1 s, gain -28.4%. Arm 1 (offload only) median is 269.7 s. At this 12-prefix
c=4 shape, enabling the wait does not lower TTFT.

## b) Kick versus promotion_on_hit

From `store_matrix_e2*.jsonl`, first touch after which a MEMORY replica is
present (15 trials):

- e2a prefetch+kick: touch 1 in 12 trials, touch 2 in 3 trials.
- e2b on_hit only, threshold 2: no MEMORY in 13 trials; touch 1 once; touch 2 once.
- e2c both: no MEMORY in 13 trials; touch 2 once; touch 3 once.

e2a touch medians 94.7 / 24.6 / 24.4 ms. e2b stays near 80-101 ms across
three touches. Kick promotes on the first touch. on_hit at threshold 2
usually does not.

## c) Mixed batch, and leases

Store e1c (kick+wait, resident key plus cold key): 15/15 `batch_ok`, batch
median 107.2 ms. The resident key stays MEMORY; the cold key gains MEMORY
after the batch get.

Smoke mixed case did not execute. `waitmix probe 0` was `['LOCAL_DISK', 'DISK']`,
and the small key had no MEMORY replica, so the test skipped. No
`mixed batch_get results` line.

`LEASE_EXPIRED` is 0 on every store arm and on engine arms 1, 3, and 4
(master and vLLM). Saved counter files contain no `get-side kick` lines.

## memcpy bisect

`35199bd5` fails `TcpLocalMemcpyAutoEnableTest.MetadataRemoteReplicaOnSameTcpHostUsesTransferEngine`.
`986f385c` passes. No semantic fix.
