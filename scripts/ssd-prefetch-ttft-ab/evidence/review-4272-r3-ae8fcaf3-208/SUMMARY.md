# r3 @ ae8fcaf3 smoke on 208

`ae8fcaf3b7a70bcc7497198db825459e0d6e08db` adds `ExistOptions` to
`_CPP_EXPORTS`. Native libraries are the b4ab9628 build
(`libmooncake_store.so` `bb3fa1943b01478f7919e4da1cf760ca`,
`ascend_transport.so` `9e4f073cdaacfc55d1e0b85aa249ce18`).

`run_ssd_offload_smoke.sh` `SMOKE_RC=0`. Offload 3 tests OK in 71.9s.
Promotion 3 tests OK, 1 skipped, in 41.0s. Prefetch 3 tests OK in 17.4s:
`test_exist_with_prefetch_promotes_ssd_only_key`,
`test_get_kick_promotes_ssd_only_key`,
`test_exist_without_prefetch_does_not_promote`.

One line: the facade re-export lets the prefetch smoke group start, and
all three groups pass.
