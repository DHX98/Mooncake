#!/usr/bin/env python3
"""Deterministic 16k+1 prefixes for the TTFT A/B. Same file for fill and measure."""
import argparse
import json
import random

WORDS = (
    "the quick brown fox jumps over a lazy dog near the river bank while "
    "autumn leaves fall gently onto the quiet road"
).split()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--num-prefixes", type=int, default=48)
    ap.add_argument("--prefix-tokens", type=int, default=16385)
    ap.add_argument("--suffix", default="Summarize the above in one sentence.")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--out-prefix", default="prompts")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    prompts = [
        " ".join(rng.choice(WORDS) for _ in range(args.prefix_tokens))
        + "\n\n"
        + args.suffix
        for _ in range(args.num_prefixes)
    ]
    jsonl = f"{args.out_prefix}.jsonl"
    with open(jsonl, "w", encoding="utf-8") as fh:
        for prompt in prompts:
            fh.write(json.dumps({"prompt": prompt}) + "\n")
    print(f"wrote {jsonl} n={len(prompts)} seed={args.seed}")


if __name__ == "__main__":
    main()
