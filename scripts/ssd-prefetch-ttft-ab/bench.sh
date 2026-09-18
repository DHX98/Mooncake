#!/bin/bash
# One vllm bench serve. The screen log is the evidence; JSON is a side product.
#   DATASET=.../prompts.jsonl CONC=2 ./bench.sh a_r1.json
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy

name="${1:-}"
[ -n "$name" ] || { echo "usage: $0 <result.json>"; exit 2; }
dataset="${DATASET:-$DATADIR/prompts.jsonl}"
conc="${CONC:-$MEASURE_CONCURRENCY}"
nprompts="${NPROMPTS:-$NUM_PREFIXES}"
bseed="${BSEED:-$SEED}"
bench_log="$RESULTDIR/${name%.json}.bench.log"
mkdir -p "$RESULTDIR"
test -f "$dataset" || { echo "PROMPTS_MISSING $dataset"; exit 1; }

echo "===== vllm bench serve  $name  c=$conc  n=$nprompts ====="
echo "tee $bench_log"

set +e
vllm bench serve \
  --backend openai \
  --base-url "http://127.0.0.1:${HTTP_PORT}" \
  --model "$SERVED_NAME" \
  --tokenizer "$MODEL" \
  --trust-remote-code \
  --num-prompts "$nprompts" \
  --max-concurrency "$conc" \
  --seed "$bseed" \
  --dataset-name custom \
  --dataset-path "$dataset" \
  --skip-chat-template \
  --custom-output-len "$CUSTOM_OUTPUT_LEN" \
  --percentile-metrics ttft \
  --metric-percentiles 50,90,99 \
  --save-result \
  --result-dir "$RESULTDIR" \
  --result-filename "$name" \
  2>&1 | tee "$bench_log"
rc=${PIPESTATUS[0]}
set -e

echo "BENCH_RC=$rc log=$bench_log"
echo "----- TTFT from screen log -----"
grep -A8 'Time to First Token' "$bench_log" || true
exit "$rc"
