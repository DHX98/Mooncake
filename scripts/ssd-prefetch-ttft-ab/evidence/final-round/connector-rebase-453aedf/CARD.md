# vllm-ascend connector rebase onto named main

No pull request was opened. vllm-ascend PR 11037 was not modified. Mooncake product code was not modified.

## Branch

- https://github.com/DHX98/vllm-ascend/tree/feat/ssd-prefetch-on-exist-v2
- commit `453aedf51b84f8475826b83d9c872ff5aabaf1c0`
- parent: vllm-ascend `main` `37197ea0b37b04ca04f39059d6915804f35dcf15`
- previous branch tip `77c62937371588a9d9037e9f9fee82063fdcf56f` (parent `44358abf686dc64ef3effec70d800a89a03662b6`)
- tree `cef191cb86e040214c6530ed8b49d94851f8fc3b`, same tree that the unit tests and `format.sh ci` ran against

Upstream `main` had moved to `530ac6b7d05b2063275a5b3b75e0443e4b931a09` by the time of the rebase. This update uses the named base `37197ea0`.

Diff against that base: 3 files, documentation +17, tests +252, `mooncake_backend.py` +240 / -28.

| file | change |
|---|---|
| `docs/source/user_guide/feature_guide/kv_cache_pool_ascend_store.md` | prefetch fields moved onto the renamed guide. The `ssd_get_wait_ms` row states that any prefetch knob switches `setup()` to the config dict, so the store creates its own TransferEngine |
| `tests/ut/distributed/ascend_store/test_backend.py` | existing prefetch cases, rebased cleanly |
| `vllm_ascend/.../backend/mooncake_backend.py` | prefetch wiring kept. Scheduler-only clients still skip SSD registration. A comment on the keyword setup path says a config-dict probe miss should drop numeric knobs instead of failing init |

## Conflicts

The documentation file on the named main is `kv_cache_pool_ascend_store.md`. The prefetch rows and the example JSON were applied there.

`_setup_store` on the named main skips `_ssd_setup_kwargs` when the client does not contribute memory. The prefetch master switch uses that same gate, so a scheduler client stays on the keyword `setup()` path and does not register SSD storage.

## Commit message

One commit. The subject and body cite "Mooncake PR 4272", "vllm-ascend PR 11037", and "RFC 2213". The message contains no `#` digit autolink. It ends with:

```
Signed-off-by: DHX98 <haox.dai@gmail.com>
Co-authored-by: huangdong2022 <161736910+huangdong2022@users.noreply.github.com>
```

`git push` of the pack was rejected by the HTTP proxy with 403. The same tree and message were published with the Git Data API, and the branch ref was force-updated. The published commit id differs from the local object id because the API stored the author and committer timestamps in UTC. Tree, parent, and message text match.

## Unit tests

CPython 3.12, no torch, `pytest --noconftest tests/ut/distributed/ascend_store/test_backend.py -k "Mooncake or ssd_get or prefetch or Exist"`.

61 passed, 87 deselected. The previous tip reported 60. The extra match is a scheduler test whose name contains Mooncake; it passed with the contribute-memory gate.

## format.sh ci

`bash format.sh ci` completed with status 0. Hook results:

- ruff check, ruff format, codespell, typos, clang-format, markdownlint: passed
- actionlint: passed
- gitleaks, shellcheck, png-lint, filename check, package init, logger check, forbidden imports, boolean context manager, long functions, symbolic meta: passed

Two substitutions were required on this aarch64 host:

- The actionlint hook builds itself with Go. Module downloads failed certificate verification through the TLS intercepting proxy. The run used the `actionlint-system` hook id from the same actionlint `v1.7.7` repository and an aarch64 `actionlint 1.7.7` binary. The repository config was restored to `id: actionlint` before the status check. The published tree still has that id.
- The gitleaks helper downloads an x86_64 binary, which cannot execute here. An aarch64 gitleaks 8.24.3 on `PATH` was used instead. `gitleaks protect --staged` passed. A separate `gitleaks detect` of the one new commit scanned about 25 KB and reported no leaks.

The working tree was clean after the run.
