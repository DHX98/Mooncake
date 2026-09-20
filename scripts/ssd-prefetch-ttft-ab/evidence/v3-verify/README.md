Architect entry: start at PROCESS.md, then RESULT.md, then configs/.

H20 overflow SSD GET hang (store wait-all, both arms, not prefetch):
`STORE_BATCH_HANG.md` and `../h20-round1/STORE_BATCH_HANG.md`.

- Successful c=4 run full logs: `vllm.log.gz`, `master.log.gz` in this directory.
- Failed rounds: `runs/fail{1,2,3}/` (host + vllm + master + bench).
- 9/17 winning r2: `runs/v3-r2-win/run.host.log` and `STEP0.md` here;
  full vllm/master stay on 141 at `/home/<user>/perf_test_prefetch_v3/logs/`
  (office proxy rejects the 36MB gzip push).
