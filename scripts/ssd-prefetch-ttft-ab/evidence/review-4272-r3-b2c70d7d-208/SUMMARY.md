# r3 @ b2c70d7d on 208

`b2c70d7d2918761dc7e636d0b84d667972823fa4`. Clean configure succeeded
(`CMAKE_RC=0`). The full ninja build stopped (`BUILD_RC=1`).

The only compiler errors are in `prefetch_task_master_test.cpp`:

- line 135 and 136: `TenantState` has no member `promotion_candidates`
- line 173: `MasterService` has no member `RecordOrUpdateCandidate`

Candidates now live on `MasterService::promotion_candidates_`
(`PromotionCandidateTracker`), updated through `RecordLocked`. The test
still uses the old per-tenant map and `RecordOrUpdateCandidate`. That is
a test/API mismatch. The test and the product sources were not edited.

`prefetch_teardown_test.cpp` itself compiled. Ninja built
`prefetch_teardown_test.cpp.o` at step 428 and reported no error for that
file. The test binary was not linked, and `libmooncake_store.so` was not
produced, because ninja stopped on the master-test object.

Same-build md5 for the two transfer-engine artifacts that did link:

- `ascend_transport.so` `c4dddfe0ca06029f96b8cdb68f9f4088`
- `libtransfer_engine.so` `b029ec56154e44682ef73b0a307293b4`

ctest, the 20-repeat, and smoke were not run. TSAN/ASAN was not run.

The leftover `58217a71` logs were pushed earlier as `c82eda3a`.

One line: the teardown test file compiles, and the full build still stops
on the stale prefetch master test.
