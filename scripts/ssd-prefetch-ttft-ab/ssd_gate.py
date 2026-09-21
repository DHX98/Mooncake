#!/usr/bin/env python3
"""Overlay-only LOCAL_DISK gate. Do not add DRAM (1-8MB segment, never 256MB).

list: snapshot fill keys (9021 then probe master HTTP ports).
probe: one batch_get_replica_desc sample. Not a poll (leases livelock eviction).
validate-keys: curl body is a real key list.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

# vLLM client uses SEGMENT_SIZE=256MB. Never inherit that.
os.environ.pop("MOONCAKE_GLOBAL_SEGMENT_SIZE", None)

# Query-only client: zero segment, zero buffer (proven by
# client_metrics_test's dict setup). A 4MiB segment is rejected by
# validate_single_segment_size and made setup() fail with ret=-1, which
# previously masked the gate as 64/64 MISSING instead of a hard error.
GATE_SEGMENT = 0
GATE_BUFFER = 0
SAMPLE_N = 64
MASTER = os.environ.get("SSD_GATE_MASTER", "127.0.0.1:50111")
METRICS_PORT = int(os.environ.get("METRICS_PORT", "9021"))


def log(msg: str) -> None:
    print(msg, flush=True)


def _replica_types(descs, key):
    """Return replica type tags ('MEMORY', 'LOCAL_DISK', 'DISK') for a key."""
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


def spread(keys: list[str], n: int) -> list[str]:
    if len(keys) <= n:
        return keys
    if n <= 1:
        return keys[:1]
    return [keys[int(i * (len(keys) - 1) / (n - 1))] for i in range(n)]


def parse_keys(raw: str) -> list[str]:
    t = (raw or "").strip()
    if not t:
        return []
    if t.startswith("[") or t.startswith("{"):
        try:
            body = json.loads(t)
        except json.JSONDecodeError:
            body = None
        if isinstance(body, list):
            return [str(x).strip() for x in body if str(x).strip()]
        if isinstance(body, dict):
            for k in ("keys", "data", "result"):
                v = body.get(k)
                if isinstance(v, list):
                    return [str(x).strip() for x in v if str(x).strip()]
    keys = []
    for line in t.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith("Failed") or s.startswith("<"):
            return []
        if " " in s and s.split()[-1].replace(".", "", 1).isdigit():
            # prometheus sample, not a key list
            return []
        keys.append(s)
    return keys


def http_get(url: str, timeout: float = 15.0) -> str:
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def try_get_all_keys(port: int, timeout: float = 8.0) -> list[str] | None:
    url = f"http://127.0.0.1:{port}/get_all_keys"
    try:
        raw = http_get(url, timeout=timeout)
    except Exception as e:
        log(f"SSD_GATE list miss port={port} {type(e).__name__} {e}")
        return None
    keys = parse_keys(raw)
    if not keys:
        log(f"SSD_GATE list empty/invalid port={port} bytes={len(raw)}")
        return None
    log(f"SSD_GATE list hit port={port} n={len(keys)}")
    return keys


def listen_ports() -> list[int]:
    ports: list[int] = []
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(path, encoding="utf-8", errors="replace").read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            parts = line.split()
            if len(parts) < 4 or parts[3] != "0A":
                continue
            local = parts[1]
            if ":" not in local:
                continue
            try:
                ports.append(int(local.rsplit(":", 1)[1], 16))
            except ValueError:
                continue
    return ports


def collect_ports() -> list[int]:
    ordered = [METRICS_PORT, 9021, 8080, 9000, 9001, 9002, 9003, 9090, 9091]
    seen: set[int] = set()
    out: list[int] = []
    extra = [p for p in listen_ports() if 8000 <= p <= 9999]
    for p in ordered + extra:
        if p <= 0 or p in seen:
            continue
        if p == 50111:
            continue
        seen.add(p)
        out.append(p)
    return out


def write_keys(path: str, keys: list[str]) -> None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        for k in keys:
            fh.write(k + "\n")


def write_gate(
    path: str,
    *,
    n_fill: int,
    n_sampled: int,
    hist: dict[str, int],
    gate_pass: int,
    attempt: int,
    extra: str = "",
) -> None:
    lines = [
        f"n_fill_keys={n_fill}",
        f"n_sampled={n_sampled}",
        f"MEMORY={hist.get('MEMORY', 0)}",
        f"LOCAL_DISK={hist.get('LOCAL_DISK', 0)}",
        f"LOCAL_DISK-only={hist.get('LOCAL_DISK-only', 0)}",
        f"MISSING={hist.get('MISSING', 0)}",
        f"GATE_PASS={gate_pass}",
        f"attempt={attempt}",
    ]
    if extra:
        lines.append(extra.rstrip("\n"))
    text = "\n".join(lines) + "\n"
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    log("----- SSD_GATE -----")
    sys.stdout.write(text)
    sys.stdout.flush()


def cmd_validate(path: str) -> int:
    try:
        raw = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return 1
    keys = parse_keys(raw)
    log(f"SSD_GATE validate n={len(keys)} file={path}")
    return 0 if keys else 1


def cmd_list(out: str) -> int:
    # 9021 first, then other master HTTP ports
    for port in collect_ports():
        keys = try_get_all_keys(port)
        if keys:
            write_keys(out, keys)
            return 0
    log("SSD_GATE list FAIL cannot prove fill keys")
    write_keys(out, [])
    return 1


def setup_store():
    if GATE_SEGMENT < 1024 * 1024 or GATE_SEGMENT > 8 * 1024 * 1024:
        raise RuntimeError(f"refusing segment {GATE_SEGMENT}")
    from mooncake.store import MooncakeDistributedStore

    store = MooncakeDistributedStore()
    cfg = {
        "local_hostname": "127.0.0.1",
        "metadata_server": os.environ.get("MC_METADATA_SERVER", "P2PHANDSHAKE"),
        "global_segment_size": str(GATE_SEGMENT),
        "local_buffer_size": str(GATE_BUFFER),
        "protocol": "tcp",
        "rdma_devices": "",
        "master_server_addr": MASTER,
        "enable_ssd_offload": "false",
        "enable_ssd_prefetch": "false",
    }
    log(f"SSD_GATE store setup segment={GATE_SEGMENT} protocol=tcp master={MASTER}")
    ret = store.setup(cfg)
    if ret not in (0, None):
        raise RuntimeError(f"store.setup ret={ret}")
    return store


def cmd_probe(arm: str, attempt: int, keys_file: str, gate_file: str) -> int:
    empty = {"MEMORY": 0, "LOCAL_DISK": 0, "LOCAL_DISK-only": 0, "MISSING": 0}
    keys: list[str] = []
    if keys_file and os.path.isfile(keys_file):
        keys = [
            ln.strip()
            for ln in open(keys_file, encoding="utf-8", errors="replace")
            if ln.strip()
        ]
    if not keys:
        write_gate(
            gate_file,
            n_fill=0,
            n_sampled=0,
            hist=empty,
            gate_pass=0,
            attempt=attempt,
            extra="reason=no_fill_keys",
        )
        return 1

    sample = spread(keys, SAMPLE_N)
    store = None
    try:
        store = setup_store()
        descs = store.batch_get_replica_desc(sample)
    except Exception as e:
        log(f"SSD_GATE probe err {type(e).__name__} {e}")
        write_gate(
            gate_file,
            n_fill=len(keys),
            n_sampled=len(sample),
            hist={**empty, "MISSING": len(sample)},
            gate_pass=0,
            attempt=attempt,
            extra=f"reason=probe_err {type(e).__name__}",
        )
        return 1
    finally:
        if store is not None:
            try:
                store.close()
            except Exception:
                pass

    hist = {"MEMORY": 0, "LOCAL_DISK": 0, "LOCAL_DISK-only": 0, "MISSING": 0}
    for key in sample:
        tags = _replica_types(descs, key)
        has_mem = any(t == "MEMORY" for t in tags)
        has_disk = any(t == "LOCAL_DISK" for t in tags)
        if not tags:
            hist["MISSING"] += 1
            continue
        if has_mem:
            hist["MEMORY"] += 1
        if has_disk:
            hist["LOCAL_DISK"] += 1
        if has_disk and not has_mem:
            hist["LOCAL_DISK-only"] += 1

    gate_pass = 1 if hist["LOCAL_DISK-only"] >= 1 else 0
    write_gate(
        gate_file,
        n_fill=len(keys),
        n_sampled=len(sample),
        hist=hist,
        gate_pass=gate_pass,
        attempt=attempt,
    )
    return 0 if gate_pass else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_val = sub.add_parser("validate-keys")
    p_val.add_argument("path")
    p_list = sub.add_parser("list")
    p_list.add_argument("--out", required=True)
    p_probe = sub.add_parser("probe")
    p_probe.add_argument("--arm", required=True)
    p_probe.add_argument("--attempt", type=int, required=True)
    p_probe.add_argument("--keys", required=True)
    p_probe.add_argument("--out", required=True)
    args = ap.parse_args()
    if args.cmd == "validate-keys":
        return cmd_validate(args.path)
    if args.cmd == "list":
        return cmd_list(args.out)
    if args.cmd == "probe":
        return cmd_probe(args.arm, args.attempt, args.keys, args.out)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
