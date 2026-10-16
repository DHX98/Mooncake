#!/bin/bash
# Engine-level anchor pair: the ONE comparison that must also hold at vLLM
# TTFT level — arm 3 (kick, no wait) vs arm 4 (kick + wait), plus arm 1 as
# the offload-only reference. Mini protocol: 12 prefixes (same DRAM-churn
# regime, ~1h per arm instead of 6h), measure at c=4 (the queue window is
# where TTFT differences live — the stopped c=2 arms showed none).
#
#   OVERLAY_DIR_3=<decouple libs> \
#     docker exec <bench-container> bash --noprofile --norc \
#       /path/to/scripts/ssd-prefetch-ttft-ab/run_engine_pair.sh
#
# Everything is overridable; defaults are the mini protocol.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

export NUM_PREFIXES="${NUM_PREFIXES:-12}"
export OVERFLOW_PREFIXES="${OVERFLOW_PREFIXES:-12}"
export MEASURE_CONCURRENCY="${MEASURE_CONCURRENCY:-4}"
export MAX_NUM_SEQS="${MAX_NUM_SEQS:-4}"
export ARMS="${ARMS:-1 3 4}"
export SHAPES="${SHAPES:-pure}"

echo "engine anchor pair: ARMS='$ARMS' SHAPES='$SHAPES' pool=$NUM_PREFIXES c=$MEASURE_CONCURRENCY"
echo "(arm 3 requires OVERLAY_DIR_3 — matrix.sh refuses to run it otherwise)"
exec "$HERE/matrix.sh"
