#!/bin/bash
# Pins for the DSV4 16k+1 A/B. Source this, then run the other scripts.
# Override any variable before sourcing if your paths differ.

ROOT="${ROOT:-/home/<user>/prefetch_916/920_pre_pr/perf}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PKG="${PKG:-/usr/local/python3.12.13/lib/python3.12/site-packages/mooncake}"
RUNTIME="${RUNTIME:-/home/<user>/prefetch_916/runtime}"
MODEL="${MODEL:-/data/DeepSeek-V4-Flash-w8a8-mtp}"
SERVED_NAME="${SERVED_NAME:-dsv4-flash}"

# vLLM / master
NPU="${NPU:-0,1,2,3,4,5,6,7}"
HTTP_PORT="${HTTP_PORT:-8271}"
RPC_PORT="${RPC_PORT:-50111}"
METRICS_PORT="${METRICS_PORT:-9021}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-20480}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-2}"
GPU_MEM="${GPU_MEM:-0.95}"

# Benchmark
PREFIX_TOKENS="${PREFIX_TOKENS:-16385}"
NUM_PREFIXES="${NUM_PREFIXES:-48}"
OVERFLOW_PREFIXES="${OVERFLOW_PREFIXES:-48}"
SEED="${SEED:-42}"
OVERFLOW_SEED="${OVERFLOW_SEED:-1042}"
FILL_CONCURRENCY="${FILL_CONCURRENCY:-1}"
MEASURE_CONCURRENCY="${MEASURE_CONCURRENCY:-2}"
CUSTOM_OUTPUT_LEN="${CUSTOM_OUTPUT_LEN:-8}"
SETTLE_SEC="${SETTLE_SEC:-90}"

# Mooncake
SEGMENT_SIZE="${SEGMENT_SIZE:-256MB}"
LOCAL_BUFFER_SIZE="${LOCAL_BUFFER_SIZE:-8MB}"
SSD_GET_WAIT_MS="${SSD_GET_WAIT_MS:-2000}"
SSD="${SSD:-$ROOT/ssd}"
LOGDIR="${LOGDIR:-$ROOT/logs}"
DATADIR="${DATADIR:-$ROOT/data}"
RESULTDIR="${RESULTDIR:-$HERE/results}"
CFG_A="${CFG_A:-$HERE/mooncake_a.json}"
CFG_B="${CFG_B:-$HERE/mooncake_b.json}"

# Platform profile (ascend | h20): provides MOONCAKE_PROTOCOL,
# MOONCAKE_DEVICE_NAME, BLOCK_SIZE, KV_JSON, VLLM_EXTRA_ARGS,
# platform_vllm_env.
PLATFORM="${PLATFORM:-ascend}"
# shellcheck disable=SC1090
. "$HERE/platforms/$PLATFORM.env" || {
  echo "UNKNOWN_PLATFORM $PLATFORM (expected: ascend | h20)" >&2
  return 1 2>/dev/null || exit 1
}

# Generate the per-arm client configs from the template so protocol /
# paths / sizing always match this environment (never a stale committed
# file from another machine).
_gen_cfg() {
  local prefetch="$1" out="$2"
  sed -e "s|@PROTOCOL@|$MOONCAKE_PROTOCOL|g" \
      -e "s|@DEVICE_NAME@|$MOONCAKE_DEVICE_NAME|g" \
      -e "s|@RPC_PORT@|$RPC_PORT|g" \
      -e "s|@SEGMENT_SIZE@|$SEGMENT_SIZE|g" \
      -e "s|@LOCAL_BUFFER_SIZE@|$LOCAL_BUFFER_SIZE|g" \
      -e "s|@SSD@|$SSD|g" \
      -e "s|@PREFETCH@|$prefetch|g" \
      -e "s|@WAIT_MS@|$SSD_GET_WAIT_MS|g" \
      "$HERE/mooncake.json.tmpl" >"$out"
}
_gen_cfg false "$CFG_A"
_gen_cfg true "$CFG_B"

ARM="${ARM:-a}"
case "$ARM" in
  b|B) ARM=b; MOONCAKE_JSON=$CFG_B ;;
  *) ARM=a; MOONCAKE_JSON=$CFG_A ;;
esac

MASTER_LOG=$LOGDIR/master.log
VLLM_LOG=$LOGDIR/vllm.log
MASTER_PIDFILE=$LOGDIR/master.pid
VLLM_PIDFILE=$LOGDIR/vllm.pid

export ROOT HERE PKG RUNTIME MODEL SERVED_NAME
export NPU HTTP_PORT RPC_PORT METRICS_PORT MAX_MODEL_LEN MAX_NUM_SEQS GPU_MEM
export PREFIX_TOKENS NUM_PREFIXES OVERFLOW_PREFIXES SEED OVERFLOW_SEED
export FILL_CONCURRENCY MEASURE_CONCURRENCY CUSTOM_OUTPUT_LEN SETTLE_SEC
export SEGMENT_SIZE LOCAL_BUFFER_SIZE SSD_GET_WAIT_MS SSD
export LOGDIR DATADIR RESULTDIR CFG_A CFG_B ARM MOONCAKE_JSON
export MASTER_LOG VLLM_LOG MASTER_PIDFILE VLLM_PIDFILE
export PLATFORM MOONCAKE_PROTOCOL MOONCAKE_DEVICE_NAME BLOCK_SIZE KV_JSON
export MOONCAKE_CONFIG_PATH=$MOONCAKE_JSON
export MOONCAKE_OFFLOAD_FILE_STORAGE_PATH=$SSD
export MOONCAKE_SSD_GET_WAIT_MS=$SSD_GET_WAIT_MS
export MOONCAKE_OFFLOAD_BUCKET_KEYS_LIMIT=1
export GLOG_logtostderr=1
export MC_METADATA_SERVER=P2PHANDSHAKE
export LOCAL_HOSTNAME=127.0.0.1
export GLOG_v=1
export PYTHONUNBUFFERED=1

mkdir -p "$LOGDIR" "$DATADIR" "$RESULTDIR" "$SSD"
