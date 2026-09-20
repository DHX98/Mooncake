#!/bin/bash
# Full A/B. Read this file top to bottom — that is the test method.
#
#   docker exec <bench-container> bash --noprofile --norc \
#     /path/to/scripts/ssd-prefetch-ttft-ab/run_ab.sh
#
# A = SSD offload only.  B = offload + prefetch.
# Primary number = measure r1 (c=2). Read the tee'd *.bench.log, not only JSON.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"

empty_ssd() {
  case "$SSD" in
    *ssd_dsv4*|*ssd_8b*|*prefetch_2646*|*prefetch-2646*)
      echo "REFUSING_OTHER_SSD $SSD"; exit 1 ;;
    /tmp|/tmp/*) echo "SSD_IS_TMP $SSD"; exit 1 ;;
  esac
  mkdir -p "$SSD"
  find "$SSD" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  echo "emptied $SSD"
}

one_arm() {
  local arm="$1"
  export ARM="$arm"
  # shellcheck disable=SC1091
  . "$HERE/env.sh"

  echo
  echo "########## ARM $arm  prefetch=$( [ "$arm" = b ] && echo ON || echo OFF ) ##########"
  ARM="$arm" "$HERE/serve.sh" start
  "$HERE/wait_ready.sh"

  echo "----- fill (write prefixes into the store) -----"
  DATASET="$DATADIR/prompts.jsonl" CONC="$FILL_CONCURRENCY" \
    "$HERE/bench.sh" "${arm}_fill.json"

  python3 - "$RESULTDIR/${arm}_fill.bench.log" <<'CHK'
import sys
p = sys.argv[1]
t = open(p, encoding='utf-8', errors='replace').read()
n = 0
for line in t.splitlines():
    if 'Successful requests:' in line:
        n = int(line.split(':')[-1].strip() or 0)
print('FAIL_FAST_FILL success', n)
if n <= 0:
    print('FILL_ZERO_ABORT'); raise SystemExit(1)
CHK
  echo "----- overflow (evict fill keys out of DRAM onto SSD) -----"
  DATASET="$DATADIR/overflow.jsonl" CONC="$FILL_CONCURRENCY" \
    NPROMPTS="$OVERFLOW_PREFIXES" BSEED="$OVERFLOW_SEED" \
    "$HERE/bench.sh" "${arm}_overflow.json"

  echo "----- settle ${SETTLE_SEC}s (leases / offload) -----"
  sleep "$SETTLE_SEC"

  echo "----- measure r1 c=${MEASURE_CONCURRENCY}  (PRIMARY) -----"
  DATASET="$DATADIR/prompts.jsonl" CONC="$MEASURE_CONCURRENCY" \
    "$HERE/bench.sh" "${arm}_r1.json"

  echo "----- measure r2 c=${MEASURE_CONCURRENCY}  (contamination check) -----"
  DATASET="$DATADIR/prompts.jsonl" CONC="$MEASURE_CONCURRENCY" \
    "$HERE/bench.sh" "${arm}_r2.json"

  ARM="$arm" "$HERE/serve.sh" stop
}

empty_ssd
python3 "$HERE/gen_dataset.py" \
  --num-prefixes "$NUM_PREFIXES" \
  --prefix-tokens "$PREFIX_TOKENS" \
  --seed "$SEED" \
  --out-prefix "$DATADIR/prompts"
python3 "$HERE/gen_dataset.py" \
  --num-prefixes "$OVERFLOW_PREFIXES" \
  --prefix-tokens "$PREFIX_TOKENS" \
  --seed "$OVERFLOW_SEED" \
  --out-prefix "$DATADIR/overflow"

"$HERE/serve.sh" stop || true
one_arm a
empty_ssd
one_arm b

echo
echo "########## done ##########"
echo "Read these screen logs (not the JSON):"
echo "  $RESULTDIR/a_r1.bench.log"
echo "  $RESULTDIR/b_r1.bench.log"
echo "gain_pct = (A - B) / A * 100   on median / mean / p99 of r1"
