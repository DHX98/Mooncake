#!/usr/bin/env python3
"""Store-level decomposition driver for the get-side mechanisms.

Drives store_py directly (no vLLM, no NPU): every trial is seconds, and the
measurement granularity is the get() latency — exactly the granularity the
review asks about. Every trial records replica-type evidence (pre/post) so
each number is traceable to a verified store state.

Arms (env ARM):
  e0   baseline: prefetch off. get of an SSD-only key = raw SSD read cost.
  e1a  kick, no wait (prefetch on, wait=0): get arrives mid-promotion, falls
       through to SSD immediately.
  e1b  kick + wait (prefetch on, wait=WAIT_MS): get waits out the in-flight
       promotion, reads DRAM.  E1a vs E1b = the wait's isolated benefit.
  e1c  mixed batch: batch_get([resident A, SSD-only K in flight]) under
       kick+wait — both must succeed and be timed (mixed-batch emphasis).
  e2a  prefetch+kick (wait on): cold-key touches get1/get2/get3.
  e2b  promotion_on_hit only (threshold=2): same touches — admission-gated.
  e2c  both on: coexistence, no conflict.
  e1d  OPTIONAL kick-rescue (needs the decoupled-kick build): saturate DRAM
       so the exist-triggered promotion is dropped (cooldown), then get —
       the kick is the only retry.

Env: ARM, MASTER_SERVER, MC_METADATA_SERVER, RESULTDIR,
     OBJECT_BYTES (100 MiB), SEGMENT_BYTES (256 MiB), LOCAL_BUFFER_BYTES
     (512 MiB), TRIALS (15), SSD_GET_WAIT_MS (per arm), PREFETCH_ENABLED,
     MOONCAKE_OFFLOAD_FILE_STORAGE_PATH (per-arm SSD dir, required).
"""
import ctypes
import json
import os
import sys
import time

from mooncake.store import ExistOptions, MooncakeDistributedStore

ARM = os.environ["ARM"]
OBJECT_BYTES = int(os.getenv("OBJECT_BYTES", str(100 * 1024 * 1024)))
SEGMENT_BYTES = int(os.getenv("SEGMENT_BYTES", str(256 * 1024 * 1024)))
LOCAL_BUFFER_BYTES = int(os.getenv("LOCAL_BUFFER_BYTES", str(512 * 1024 * 1024)))
TRIALS = int(os.getenv("TRIALS", "15"))
WAIT_MS = os.getenv("SSD_GET_WAIT_MS", "0")
PREFETCH = os.getenv("PREFETCH_ENABLED", "false")
LEASE_TTL_MS = int(os.getenv("KV_LEASE_TTL_MS", "2000"))
RESULTDIR = os.getenv("RESULTDIR", ".")
MAX_EVICT_ROUNDS = int(os.getenv("MAX_EVICT_ROUNDS", "14"))

# Probe cadence must exceed the master's lease TTL or every probe re-leases
# the target and eviction livelocks (see test_prefetch_on_exist.py NOTE).
PROBE_GAP_SEC = float(os.getenv("PROBE_GAP_SEC", "0.5"))
PROBE_INTERVAL = LEASE_TTL_MS / 1000.0 + PROBE_GAP_SEC


def log(msg):
    print(f"[{ARM}] {msg}", flush=True)


def setup_store():
    store = MooncakeDistributedStore()
    config = {
        "local_hostname": os.getenv("LOCAL_HOSTNAME", "127.0.0.1"),
        "metadata_server": os.getenv("MC_METADATA_SERVER", "P2PHANDSHAKE"),
        "global_segment_size": str(SEGMENT_BYTES),
        "local_buffer_size": str(LOCAL_BUFFER_BYTES),
        "protocol": os.getenv("PROTOCOL", "tcp"),
        "rdma_devices": os.getenv("DEVICE_NAME", ""),
        "master_server_addr": os.getenv("MASTER_SERVER", "127.0.0.1:50051"),
        "enable_ssd_offload": "true",
        "enable_ssd_prefetch": PREFETCH,
        "ssd_get_wait_ms": WAIT_MS,
    }
    ssd_path = os.getenv("MOONCAKE_OFFLOAD_FILE_STORAGE_PATH", "")
    if ssd_path:
        config["ssd_offload_path"] = ssd_path
    rc = store.setup(config)
    if rc:
        raise RuntimeError(f"store.setup failed rc={rc}")
    return store


def replica_types(store, key):
    descs = store.batch_get_replica_desc([key])
    infos = descs.get(key) if isinstance(descs, dict) else None
    if infos is None:
        return []
    if not isinstance(infos, (list, tuple)):
        infos = [infos]
    tags = []
    for info in infos:
        if hasattr(info, "is_memory_replica") and info.is_memory_replica():
            tags.append("MEMORY")
        elif hasattr(info, "is_local_disk_replica") and info.is_local_disk_replica():
            tags.append("LOCAL_DISK")
        elif hasattr(info, "is_disk_replica") and info.is_disk_replica():
            tags.append("DISK")
        else:
            tags.append("UNKNOWN")
    return tags


def prefetch_opts(on=True):
    o = ExistOptions()
    o.prefetch_to_memory = on
    return o


class TimedGet:
    """Timed batch_get_into_multi_buffers through registered buffers — the
    exact code path under review (the two-phase get restructure)."""

    def __init__(self, store):
        self.store = store
        self.cap = OBJECT_BYTES
        self.buf = (ctypes.c_ubyte * self.cap)()
        self.ptr = ctypes.addressof(self.buf)
        rc = store.register_buffer(self.ptr, self.cap)
        if rc:
            raise RuntimeError(f"register_buffer failed rc={rc}")

    def get(self, keys):
        ptrs = [[self.ptr] for _ in keys]
        caps = [[self.cap] for _ in keys]
        t0 = time.perf_counter()
        results = self.store.batch_get_into_multi_buffers(keys, ptrs, caps, False)
        ms = (time.perf_counter() - t0) * 1000.0
        ok = all(r == self.cap for r in results)
        return ms, ok, list(results)

    def close(self):
        self.store.unregister_buffer(self.ptr)


def evict_to_ssd_only(store, target, flood_prefix, put_value):
    """Flood unique overflow objects until target is LOCAL_DISK-only.
    Puts 2 objects per round, then probes (rarely, to dodge re-leasing)."""
    for round_i in range(MAX_EVICT_ROUNDS):
        for j in range(2):
            rc = store.put(f"{flood_prefix}_ovf_{round_i}_{j}", put_value)
            if rc != 0:
                log(f"overflow put rc={rc} round={round_i}")
        time.sleep(PROBE_INTERVAL)
        types = replica_types(store, target)
        if types and "MEMORY" not in types and "LOCAL_DISK" in types:
            return types, round_i + 1
    raise RuntimeError(
        f"target not evicted after {MAX_EVICT_ROUNDS} rounds "
        f"(last={replica_types(store, target)})"
    )


def run_single_key_trials(store, trigger):
    """e0/e1a/e1b: SSD-only key -> (optional prefetch trigger) -> timed gets."""
    rows = []
    get = TimedGet(store)
    put_value = os.urandom(OBJECT_BYTES)
    for trial in range(TRIALS):
        store.remove_all(True)
        key = f"{ARM}_t{trial}_target"
        assert store.put(key, put_value) == 0
        time.sleep(LEASE_TTL_MS / 1000.0 + 0.5)  # put lease out
        pre_types, rounds = evict_to_ssd_only(store, key, f"{ARM}_t{trial}", put_value)
        if trigger:
            assert store.is_exist(key, prefetch_opts(True)) == 1
        # No sleep: land the get inside the promotion's in-flight window.
        get1_ms, get1_ok, _ = get.get([key])
        mid_types = replica_types(store, key)
        get2_ms, get2_ok, _ = get.get([key])
        post_types = replica_types(store, key)
        rows.append({
            "arm": ARM, "trial": trial, "key": key,
            "pre_types": pre_types, "evict_rounds": rounds,
            "get1_ms": round(get1_ms, 2), "get1_ok": get1_ok,
            "mid_types": mid_types,
            "get2_ms": round(get2_ms, 2), "get2_ok": get2_ok,
            "post_types": post_types,
        })
        log(f"trial {trial}: get1={get1_ms:.1f}ms get2={get2_ms:.1f}ms "
            f"pre={pre_types} mid={mid_types}")
    get.close()
    return rows


def run_mixed_trials(store):
    """e1c: batch = [resident A] + [SSD-only K with promotion in flight]."""
    rows = []
    get = TimedGet(store)
    put_value = os.urandom(OBJECT_BYTES)
    for trial in range(TRIALS):
        store.remove_all(True)
        key_k = f"{ARM}_t{trial}_cold"
        assert store.put(key_k, put_value) == 0
        time.sleep(LEASE_TTL_MS / 1000.0 + 0.5)
        pre_types, rounds = evict_to_ssd_only(store, key_k, f"{ARM}_t{trial}", put_value)
        # Resident key: put after the flood stops; nothing evicts it now.
        key_a = f"{ARM}_t{trial}_resident"
        assert store.put(key_a, put_value) == 0
        a_types = replica_types(store, key_a)
        if "MEMORY" not in a_types:
            rows.append({"arm": ARM, "trial": trial, "skipped": True,
                         "reason": f"resident key not in DRAM: {a_types}"})
            log(f"trial {trial}: SKIP resident not in DRAM {a_types}")
            continue
        assert store.is_exist(key_k, prefetch_opts(True)) == 1
        get1_ms, get1_ok, results = get.get([key_a, key_k])
        post_types = {"A": replica_types(store, key_a),
                      "K": replica_types(store, key_k)}
        rows.append({
            "arm": ARM, "trial": trial, "pre_types": pre_types,
            "a_types_pre": a_types, "evict_rounds": rounds,
            "batch_ms": round(get1_ms, 2), "batch_ok": get1_ok,
            "results": results, "post_types": post_types,
        })
        log(f"trial {trial}: batch={get1_ms:.1f}ms ok={get1_ok} post={post_types}")
    get.close()
    return rows


def run_touch_trials(store):
    """e2a/e2b/e2c: cold key, three timed touches; when does it turn DRAM?"""
    rows = []
    get = TimedGet(store)
    put_value = os.urandom(OBJECT_BYTES)
    for trial in range(TRIALS):
        store.remove_all(True)
        key = f"{ARM}_t{trial}_target"
        assert store.put(key, put_value) == 0
        time.sleep(LEASE_TTL_MS / 1000.0 + 0.5)
        pre_types, rounds = evict_to_ssd_only(store, key, f"{ARM}_t{trial}", put_value)
        touches = []
        for touch in (1, 2, 3):
            ms, ok, _ = get.get([key])
            types = replica_types(store, key)
            touches.append({"touch": touch, "ms": round(ms, 2), "ok": ok,
                            "types_after": types})
            log(f"trial {trial} touch {touch}: {ms:.1f}ms after={types}")
        rows.append({"arm": ARM, "trial": trial, "pre_types": pre_types,
                     "evict_rounds": rounds, "touches": touches})
    get.close()
    return rows


def main():
    store = setup_store()
    if ARM in ("e0", "e1a", "e1b", "e1d"):
        rows = run_single_key_trials(store, trigger=(ARM != "e0"))
    elif ARM == "e1c":
        rows = run_mixed_trials(store)
    elif ARM in ("e2a", "e2b", "e2c"):
        rows = run_touch_trials(store)
    else:
        raise SystemExit(f"unknown ARM {ARM}")

    meta = {
        "arm": ARM, "prefetch": PREFETCH, "wait_ms": int(WAIT_MS),
        "object_bytes": OBJECT_BYTES, "segment_bytes": SEGMENT_BYTES,
        "trials": TRIALS, "lease_ttl_ms": LEASE_TTL_MS,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    out = os.path.join(RESULTDIR, f"store_matrix_{ARM}.jsonl")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(json.dumps({"meta": meta}) + "\n")
        for row in rows:
            fh.write(json.dumps(row) + "\n")
    log(f"wrote {out} rows={len(rows)}")


if __name__ == "__main__":
    main()
