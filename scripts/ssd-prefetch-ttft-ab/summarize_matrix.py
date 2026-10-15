#!/usr/bin/env python3
"""Aggregate matrix.sh results into the decomposition table.

Reads <resultdir>/m{arm}_{shape}[_repN]_r1.bench.log files (vllm bench screen
logs) and prints per-arm TTFT p50/p90/p99 plus the pairwise reads the review
asked for. Also surfaces per-arm counters (LEASE_EXPIRED, promotion lines).
"""
import glob
import os
import re
import sys


def ttft_from_log(path):
    """Return {50,90,99: ms} from a vllm bench screen log, or None."""
    txt = open(path, encoding="utf-8", errors="replace").read()
    out = {}
    # vllm bench prints e.g. "P50 TTFT (ms):  123.45" inside a
    # "Time to First Token" section; accept several spellings.
    for m in re.finditer(
        r"P(50|90|99)\s+TTFT\s*\(ms\)\s*:\s*([0-9.]+)", txt, re.I
    ):
        out[int(m.group(1))] = float(m.group(2))
    if not out:
        for m in re.finditer(
            r"(50th|90th|99th)\s*percentile.*?TTFT.*?([0-9.]+)\s*ms",
            txt,
            re.I | re.S,
        ):
            out[int(m.group(1)[:2])] = float(m.group(2))
    return out or None


def mean_median_from_log(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    mean = med = None
    m = re.search(r"Mean TTFT\s*\(ms\)\s*:\s*([0-9.]+)", txt, re.I)
    if m:
        mean = float(m.group(1))
    m = re.search(r"Median TTFT\s*\(ms\)\s*:\s*([0-9.]+)", txt, re.I)
    if m:
        med = float(m.group(1))
    return mean, med


def collect(resultdir, arm, shape, reps):
    rows = []
    if shape == "pure":
        logs = [os.path.join(resultdir, f"m{arm}_pure_r1.bench.log")]
    else:
        logs = sorted(
            glob.glob(os.path.join(resultdir, f"m{arm}_mixed_rep*_r1.bench.log"))
        )
    for log in logs:
        if not os.path.exists(log):
            continue
        pct = ttft_from_log(log)
        mean, med = mean_median_from_log(log)
        rows.append((os.path.basename(log), mean, med, pct))
    return rows


def fmt(v):
    return f"{v:10.1f}" if isinstance(v, float) else f"{'—':>10}"


def main():
    resultdir = sys.argv[1]
    arms = sys.argv[2].split()
    shapes = sys.argv[3].split()
    data = {}  # (arm, shape) -> list of (mean, median, {pct})
    for arm in arms:
        for shape in shapes:
            rows = collect(resultdir, arm, shape, 0)
            merged = []
            for name, mean, med, pct in rows:
                merged.append((name, mean, med, pct))
            data[(arm, shape)] = merged

    print("\n=== TTFT by arm/shape (ms; mixed rows are per-rep) ===")
    print(f"{'arm':>4} {'shape':>6} {'run':>28} {'mean':>10} {'median':>10} "
          f"{'p90':>10} {'p99':>10}")
    for arm in arms:
        for shape in shapes:
            for name, mean, med, pct in data[(arm, shape)]:
                p90 = pct.get(90) if pct else None
                p99 = pct.get(99) if pct else None
                print(f"{arm:>4} {shape:>6} {name:>28} {fmt(mean)} {fmt(med)} "
                      f"{fmt(p90)} {fmt(p99)}")
            if not data[(arm, shape)]:
                print(f"{arm:>4} {shape:>6} {'(no logs)':>28}")

    def median_of(arm, shape):
        vals = [med for _, _, med, _ in data[(arm, shape)] if med is not None]
        return sorted(vals)[len(vals) // 2] if vals else None

    print("\n=== Pairwise reads (median TTFT, pure shape) ===")
    pairs = [("3", "4", "isolated WAIT benefit"),
             ("2", "3", "isolated KICK benefit"),
             ("5", "4", "kick path vs promotion_on_hit"),
             ("5", "6", "both enabled vs on_hit only"),
             ("1", "2", "exist-side prefetch base")]
    for a, b, label in pairs:
        ma, mb = median_of(a, "pure"), median_of(b, "pure")
        if ma and mb:
            gain = (ma - mb) / ma * 100
            print(f"  {a} vs {b}  {label:35} {ma:9.1f} -> {mb:9.1f}  "
                  f"gain {gain:+.1f}%")
        else:
            print(f"  {a} vs {b}  {label:35} (missing data)")

    print("\n=== Pairwise reads (median TTFT, mixed shape) ===")
    for a, b, label in pairs:
        ma, mb = median_of(a, "mixed"), median_of(b, "mixed")
        if ma and mb:
            gain = (ma - mb) / ma * 100
            print(f"  {a} vs {b}  {label:35} {ma:9.1f} -> {mb:9.1f}  "
                  f"gain {gain:+.1f}%")
        else:
            print(f"  {a} vs {b}  {label:35} (missing data)")

    print("\n=== Counters (LEASE_EXPIRED must be 0 everywhere) ===")
    for log in sorted(glob.glob(os.path.join(resultdir, "m*.counters.log"))):
        txt = open(log, encoding="utf-8", errors="replace").read()
        le = re.findall(r"LEASE_EXPIRED_\w+=(\d+)", txt)
        flag = "OK" if le and all(v == "0" for v in le) else "CHECK"
        print(f"  {os.path.basename(log):34} LEASE_EXPIRED={le} [{flag}]")


if __name__ == "__main__":
    main()
