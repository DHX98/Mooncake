# vllm-ascend connector update for Mooncake #4272

No pull request was opened. vllm-ascend #11037 was not modified. Mooncake product code was not modified.

## Branch

- https://github.com/DHX98/vllm-ascend/tree/feat/ssd-prefetch-on-exist-v2
- commit `77c62937371588a9d9037e9f9fee82063fdcf56f`
- base: vllm-ascend `main` `44358abf686dc64ef3effec70d800a89a03662b6`

Diff against that base: 3 files, +503 / -28.

| file | change |
|---|---|
| `vllm_ascend/.../backend/mooncake_backend.py` | ExistOptions wiring, two warnings, explicit-set setup knobs, `ssd_get_wait_ms`, config-dict setup when a knob is actually forwarded |
| `tests/ut/distributed/ascend_store/test_backend.py` | #11037 cases plus `ssd_get_wait_ms` forward / omit / no-ExistOptions |
| `docs/source/user_guide/feature_guide/kv_pool.md` | four mooncake.json fields |

## Sources compared

| copy | identity |
|---|---|
| #11037 head | `44a38c729a3bf831949166be86ec89e5c9f5af07` on `main_ssd_prefetch`. 3 files, +242 / -1. Open, merge-conflicts, last update 2026-07-15. |
| vllm-ascend main | `44358abf686dc64ef3effec70d800a89a03662b6` at clone time. |
| deployment runtime | overlay that the serve script puts on `PYTHONPATH` ahead of the image package. md5 `6cff4ee25547d8bf8609fd2c7824a4de`, 27156 bytes, 635 lines. Saved as `runtime_mooncake_backend.py` in this directory. |
| image package | md5 `8d8280c524122c70cd7a1639a155bc7b`. No `ExistOptions`, `enable_ssd_prefetch`, or `ssd_get_wait_ms`. |

## Runtime relative to #11037

#11037 already has ExistOptions, the capability probe, the two warnings, and explicit forwarding of `ssd_prefetch_cooldown_sec` / `ssd_prefetch_dedup_ttl_sec`. The deployment runtime keeps that and adds:

1. `ssd_get_wait_ms` on `MooncakeStoreConfig` and in `mooncake.json`. Unset stays `None` and is not passed to `setup()`. Also falls back to `MOONCAKE_SSD_GET_WAIT_MS` when the json field is absent. The verified value is 2000.
2. Config-dict `store.setup()`. Mooncake #4272 documents `enable_ssd_prefetch`, the two throttle knobs, and `ssd_get_wait_ms` only on the dict overload. The keyword overload does not take them. The runtime probes `setup()` docstring for `Supported keys:` plus `enable_ssd_prefetch`, stringifies bools to `true`/`false`, and lets the store own the transfer engine. `register_buffer` then goes through the store.
3. Throttle kwargs are gated on the setup docstring naming that key, not only on `ExistOptions`. The comment in the runtime says ExistOptions can ship before those `setup()` keywords exist.
4. `enable_ssd_prefetch` is always placed in the config dict (including `false`). Numeric knobs are still omitted when unset.
5. A log line prints the whole setup dict, including the wait value.
6. Relative to the June #11037 base, the runtime also has `contribute_memory`, per-rank SSD directories, `tenant_id`, and store QoS checks. Current main already has those, plus layerwise session APIs and QoS injection from connector extra config, which the runtime does not have.

The new branch does not copy (2) as an always-on switch, and does not copy the environment-variable fallback or the full-dict log. Default setups stay on the keyword `setup()` path, including shared transfer engine. The dict overload is used only when a prefetch knob is actually being forwarded and the binding advertises it. `enable_ssd_prefetch=true` is one of those knobs, because #4272 will not promote unless setup received the master switch.

## What the branch keeps from #11037

- `ExistOptions(prefetch_to_memory=True)` on `exists()` / `batch_is_exist` when prefetch resolved on.
- Probe: missing `ExistOptions` disables prefetch and logs a warning. SSD offload off with prefetch requested logs the other warning.
- Cooldown, dedup, and now `ssd_get_wait_ms` are passed only when `mooncake.json` sets them. Omitted fields keep Mooncake defaults (5 s, 30 s, 0 ms).
- Comments and `kv_pool.md` cite kvcache-ai/Mooncake#4272. RFC #2213 remains the concept reference.
- Doc semantics match `docs/source/design/store/ssd-prefetch.md`: master switch, DRAM-pressure backoff, per-key dedup TTL, one batch-get wait deadline. `ssd_get_wait_ms` example value is 2000, not the default.

## Unit tests and lint

Runner: CPython 3.12, `pytest --noconftest tests/ut/distributed/ascend_store/test_backend.py`. That interpreter has no torch, and the repo `tests/ut/conftest.py` imports torch, so conftest was skipped. `_mock_deps` supplied the stand-ins.

- ruff 0.14.0 `check` on the two Python files: pass. This is the ruff revision in `.pre-commit-config.yaml`.
- ruff 0.14.0 `format --check` on those files: pass.
- Mooncake filter (`Mooncake or ssd_get or prefetch or Exist`): 60 passed.
- Full file: 145 passed, 6 failed, 106 subtests passed.

The 6 failures are not on the connector change:

- `TestLayerwiseProtocolRegistry` / `TestLayerwiseProtocolRegistration`: `ModuleNotFoundError: vllm.utils.torch_utils` because vllm is not installed in this interpreter.
- `TestMemcacheBackendMethods` SSD rewarm cases: the mock torch module has no `empty`.

`bash format.sh ci` was not run. That command is `pre-commit run --all-files --hook-stage manual` and pulls markdownlint, clang-format, and the rest of the hook set.
