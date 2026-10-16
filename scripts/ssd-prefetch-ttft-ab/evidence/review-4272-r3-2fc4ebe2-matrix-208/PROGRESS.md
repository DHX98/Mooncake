# Get-side matrix progress, stopped mid arm 2 pure

Stopped at user request on 2026-10-16 13:59 +0800 so the pace can be discussed.
The in-flight arm 2 pure r2 measurement was killed at 36/48. Finished benches were left on disk.
No next arm was started.

## Pace

Each pure pass is 48 requests, concurrency 2, and a request has been taking about 2 minutes.
Arm 1 pure ran about 6 hours. Arm 1 mixed ran about 5 hours. Arm 2 pure had already run about 6 hours when r2 was stopped at 36/48.

## Arm 1 pure (prefetch off, wait 0, on_hit off)

fill, overflow, r1, and r2 each finished with 48 successful requests.
LEASE_EXPIRED master 0, vllm 0.
r2 screen TTFT: mean 136463.50 ms, median 123334.17 ms, p99 245759.04 ms.

## Arm 1 mixed (same switches, 6 prefixes x 2 reps)

Both reps finished with 6 successful measured requests.
LEASE_EXPIRED master 0, vllm 0.
rep 1 screen TTFT: mean 177775.7 ms, median 164568.1 ms, p99 245711.5 ms.
rep 2 screen TTFT: mean 170966.9 ms, median 164253.3 ms, p99 245711.0 ms.

## Arm 2 pure (prefetch on, wait 0, on_hit off)

fill 48 successful. Screen TTFT mean 112599.78 ms, median 108409.96 ms, p99 128736.21 ms.
overflow 48 successful. Screen TTFT mean 112946.78 ms, median 122907.41 ms, p99 128702.61 ms.
r1 48 successful. Screen TTFT mean 159245.01 ms, median 123631.16 ms, p99 246150.47 ms.
r2 stopped at 36/48. No r2 TTFT.

## Not comparable yet

summarize_matrix.py still raises KeyError ('3', 'pure') when invoked after a single arm, because later arms are absent. That is not a failed bench. Pairwise 3v4, 2v3, 5v4, 5v6, and 1v2 are not available.
