# r3 @ ae8fcaf3 confirmatory A/B on 208

Tree `ae8fcaf3b7a70bcc7497198db825459e0d6e08db`. Same-build libraries
from the b4ab9628 ninja, whose C++ matches this commit:

- `libmooncake_store.so` `bb3fa1943b01478f7919e4da1cf760ca`
- `ascend_transport.so` `9e4f073cdaacfc55d1e0b85aa249ce18`

Protocol: 48 prefixes x 16385 tokens, 256MB segment, settle 90s,
measure c=4, MAX_NUM_SEQS=4. A is offload-only. B is prefetch on.
TTFT is from the bench.log screen text. Both r1 runs had 48 successful
requests. No LEASE_EXPIRED. No REPLICA_IS_NOT_READY on the B settle.
Arm A shutdown printed `stopped` with no segfault or unregister failure.

r1 screen TTFT, milliseconds:

| arm | median | mean | p99 |
| --- | ---: | ---: | ---: |
| A | 225694.15 | 226398.84 | 432062.03 |
| B | 205910.38 | 213011.42 | 423148.74 |
| drop | 8.77% | 5.91% | 2.06% |

The B r1 median drop is 8.77%, far under the 85.2% bar. r2 on B was
stopped after that result. The two r1 bench logs are in this directory.

One line: prefetch-on cuts the r1 median by 8.77%, not 85.2%.
