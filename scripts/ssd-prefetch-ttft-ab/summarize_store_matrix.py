#!/usr/bin/env python3
"""Summarize store_matrix results into the review-facing table.

Reads store_matrix_<arm>.jsonl files and prints per-arm get-latency
medians/p99s plus the pairwise reads mapped to the review questions:
  E1a vs E1b  = the wait's isolated benefit (review point 1)
  E1c         = mixed batch under kick+wait (point 1 emphasis)
  E2a/E2b/E2c = kick vs promotion_on_hit, and both (point 2)
  E0          = the raw SSD-read reference ("meaningful" baseline)
"""
import json
import os
import sys


def pct(vals, q):
    if not vals:
        return None
    vals = sorted(vals)
    k = min(len(vals) - 1, max(0, int(round((q / 100.0) * (len(vals) - 1)))))
    return vals[k]


def load(resultdir, arm):
    path = os.path.join(resultdir, f"store_matrix_{arm}.jsonl")
    if not os.path.exists(path):
        return None, []
    meta, rows = None, []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            row = json.loads(line)
            if "meta" in row:
                meta = row["meta"]
            else:
                rows.append(row)
    return meta, rows


def fmt(v):
    return f"{v:9.1f}" if isinstance(v, (int, float)) else f"{'—':>9}"


def main():
    resultdir = sys.argv[1]
    arms = sys.argv[2:]
    data = {}
    for arm in arms:
        meta, rows = load(resultdir, arm)
        data[arm] = (meta, rows)

    print("\n=== get1 latency by arm (ms) ===")
    print(f"{'arm':>5} {'n':>3} {'median':>9} {'p90':>9} {'p99':>9} "
          f"{'get2 med':>9}  note")
    for arm in arms:
        meta, rows = data[arm]
        rows = [r for r in rows if not r.get("skipped")]
        if not rows:
            print(f"{arm:>5} {'0':>3}  (no rows)")
            continue
        g1 = [r["get1_ms"] for r in rows if "get1_ms" in r]
        g2 = [r["get2_ms"] for r in rows if "get2_ms" in r]
        batch = [r["batch_ms"] for r in rows if "batch_ms" in r]
        n = len(rows)
        note = ""
        if arm == "e1c":
            ok = sum(1 for r in rows if r.get("batch_ok"))
            note = f"batch_ok={ok}/{n}"
            print(f"{arm:>5} {n:>3} {fmt(pct(batch,50))} {fmt(pct(batch,90))} "
                  f"{fmt(pct(batch,99))} {'—':>9}  {note}")
            continue
        ok1 = sum(1 for r in rows if r.get("get1_ok"))
        note = f"get1_ok={ok1}/{n}"
        print(f"{arm:>5} {n:>3} {fmt(pct(g1,50))} {fmt(pct(g1,90))} "
              f"{fmt(pct(g1,99))} {fmt(pct(g2,50))}  {note}")

    def med(arm, field="get1_ms"):
        _, rows = data.get(arm, (None, []))
        vals = [r[field] for r in rows if field in r and not r.get("skipped")]
        return pct(vals, 50)

    print("\n=== Pairwise reads ===")
    e0, e1a, e1b = med("e0"), med("e1a"), med("e1b")
    if e0 and e1b:
        print(f"  E0 vs E1b  raw SSD read -> kick+wait get: "
              f"{e0:.1f} -> {e1b:.1f} ms  ({(e0-e1b)/e0*100:+.1f}%)  "
              f"= benefit of the get path as a whole")
    if e1a and e1b:
        print(f"  E1a vs E1b kick-no-wait -> kick+wait:   "
              f"{e1a:.1f} -> {e1b:.1f} ms  ({(e1a-e1b)/e1a*100:+.1f}%)  "
              f"= ISOLATED WAIT BENEFIT (point 1)")

    print("\n=== Touch analysis (kick vs promotion_on_hit, point 2) ===")
    for arm in ("e2a", "e2b", "e2c"):
        _, rows = data.get(arm, (None, []))
        rows = [r for r in rows if r.get("touches")]
        if not rows:
            print(f"  {arm}: no rows")
            continue
        per_touch = {}
        for r in rows:
            for t in r["touches"]:
                per_touch.setdefault(t["touch"], []).append(t["ms"])
        line = "  " + arm + "  "
        for touch in (1, 2, 3):
            line += f"t{touch}={fmt(pct(per_touch.get(touch), 50))}ms  "
        # how many touches until a MEMORY replica is seen
        first_dram = []
        for r in rows:
            for t in r["touches"]:
                if "MEMORY" in t["types_after"]:
                    first_dram.append(t["touch"])
                    break
        fd = pct(first_dram, 50)
        line += f"| first DRAM after touch #{fd if fd else '—'}"
        print(line)

    print("\n=== Traceability ===")
    for arm in arms:
        meta, rows = data[arm]
        if meta:
            print(f"  {arm}: build md5 in build_{arm}.md5.log, "
                  f"object={meta['object_bytes']}B segment={meta['segment_bytes']}B "
                  f"trials={len(rows)} ts={meta['ts']}")


if __name__ == "__main__":
    main()
