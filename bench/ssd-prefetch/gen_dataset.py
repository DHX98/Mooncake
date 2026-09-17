#!/usr/bin/env python3
"""Generate the fixed prompt dataset for the prefetch TTFT A/B benchmark.

Emits prompts.jsonl (one {"prompt": ...} per line, vllm bench
`--dataset-name custom`) and prompts_sharegpt.json (ShareGPT-style, fallback
for vllm versions without custom dataset support). Deterministic via --seed:
the SAME file must be used for fill and measure, and for both arms.

DSv4-Flash is MLA (tiny KV per token), and the connector-side prefix cache
hit granularity is 16K tokens: prefixes must be >= 16385 (one full 16K
cacheable block plus a 1-token tail that avoids boundary ambiguity; the tail
recompute is negligible). Larger prefixes (e.g. 32K) only cost more HBM via
max_model_len without adding signal -- a single 16K block is already ~GB of
KV, far above TTFT noise. Constraint: prefix <= max_model_len - suffix -
output_len.
"""

import argparse
import json
import random

WORDS = (
    "the quick brown fox jumps over a lazy dog near the river bank while "
    "autumn leaves fall gently onto the quiet road"
).split()


def make_prefix(rng, approx_tokens):
    # ~1 word per token for BPE on English-ish text; exact count does not
    # matter -- determinism does.
    return " ".join(rng.choice(WORDS) for _ in range(approx_tokens))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--num-prefixes", type=int, default=48)
    ap.add_argument("--prefix-tokens", type=int, default=16385)
    ap.add_argument("--suffix",
                    default="Summarize the above in one sentence.")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--out-prefix", default="prompts")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    prompts = [
        f"{make_prefix(rng, args.prefix_tokens)}\n\n{args.suffix}"
        for _ in range(args.num_prefixes)
    ]

    jsonl = f"{args.out_prefix}.jsonl"
    with open(jsonl, "w") as fh:
        for p in prompts:
            fh.write(json.dumps({"prompt": p}) + "\n")

    sharegpt = f"{args.out_prefix}_sharegpt.json"
    with open(sharegpt, "w") as fh:
        json.dump(
            [{"conversations": [{"from": "human", "value": p},
                                {"from": "gpt", "value": ""}]}
             for p in prompts],
            fh,
        )

    print(f"wrote {jsonl} and {sharegpt} ({len(prompts)} prompts, "
          f"seed={args.seed})")


if __name__ == "__main__":
    main()
