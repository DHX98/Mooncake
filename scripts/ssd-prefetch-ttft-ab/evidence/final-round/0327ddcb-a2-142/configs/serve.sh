#!/bin/bash
# Start or stop mooncake_master + vLLM for one arm.
#   ARM=a ./serve.sh start
#   ARM=b ./serve.sh start
#   ./serve.sh stop
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"

# Never leave a proxy on the serving path.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
unset MOONCAKE_GLOBAL_SEGMENT_SIZE

write_json() {
  python3 - "$MOONCAKE_JSON" "$SSD" "$ARM" "$SEGMENT_SIZE" "$SSD_GET_WAIT_MS" <<'PY'
import json, sys
path, ssd, arm, seg, wait = sys.argv[1:6]
with open(path, encoding="utf-8") as fh:
    cfg = json.load(fh)
cfg["ssd_offload_path"] = ssd
cfg["enable_ssd_prefetch"] = arm == "b"
cfg["ssd_get_wait_ms"] = int(wait)
cfg["global_segment_size"] = seg
with open(path, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
print("json", path, "prefetch", cfg["enable_ssd_prefetch"], "seg", seg, "wait", wait)
PY
}

start_master() {
  write_json
  mkdir -p "$SSD" "$LOGDIR"
  : >"$MASTER_LOG"
  nohup "$PKG/mooncake_master" \
    --rpc_port="$RPC_PORT" \
    --metrics_port="$METRICS_PORT" \
    --enable_offload=true \
    --offload_on_evict=true \
    --promotion_on_hit=false \
    --default_kv_lease_ttl=${KV_LEASE_TTL_MS:-2000} \
    --root_fs_dir="$SSD" \
    --eviction_high_watermark_ratio=0.6 \
    --eviction_ratio=0.4 \
    --memory_allocator=offset \
    --logtostderr=true \
    >"$MASTER_LOG" 2>&1 &
  echo $! >"$MASTER_PIDFILE"
  sleep 2
  if grep -aE 'unknown command line flag' "$MASTER_LOG" >/dev/null; then
    echo "MASTER_UNKNOWN_FLAG  do not drop --promotion_on_hit=false"
    tail -n 40 "$MASTER_LOG"
    exit 1
  fi
  echo "master pid=$(cat "$MASTER_PIDFILE") rpc=:$RPC_PORT"
}

start_vllm() {
  export LD_LIBRARY_PATH="$PKG${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export PYTHONPATH="$RUNTIME${PYTHONPATH:+:$PYTHONPATH}"
  export MOONCAKE_CONFIG_PATH="$MOONCAKE_JSON"
  export MOONCAKE_OFFLOAD_FILE_STORAGE_PATH="$SSD"
  export MOONCAKE_SSD_GET_WAIT_MS="$SSD_GET_WAIT_MS"
  export MOONCAKE_OFFLOAD_BUCKET_KEYS_LIMIT=1
  export MC_METADATA_SERVER=P2PHANDSHAKE
  export LOCAL_HOSTNAME=127.0.0.1
  ulimit -u 65535 || true
  unset MOONCAKE_MASTER || true
  unset MOONCAKE_GLOBAL_SEGMENT_SIZE || true

  # Platform-specific env (visibility devices, fabric/NCCL) from
  # platforms/$PLATFORM.env, sourced via env.sh.
  platform_vllm_env

  nohup vllm serve "$MODEL" \
    --host "${VLLM_HOST:-<host-ip>}" \
    --port "$HTTP_PORT" \
    --served-model-name "$SERVED_NAME" \
    --trust-remote-code \
    --enforce-eager \
    --no-enable-prefix-caching \
    --tensor-parallel-size "${TP_SIZE:-8}" \
    --data-parallel-size 1 \
    --max-model-len "$MAX_MODEL_LEN" \
    --block-size "$BLOCK_SIZE" \
    --kv-transfer-config "$KV_JSON" \
    --max-num-batched-tokens "$MAX_MODEL_LEN" \
    --max-num-seqs "$MAX_NUM_SEQS" \
    --gpu-memory-utilization "$GPU_MEM" \
    "${VLLM_EXTRA_ARGS[@]}" \
    >"$VLLM_LOG" 2>&1 &
  echo $! >"$VLLM_PIDFILE"
  echo "vllm pid=$(cat "$VLLM_PIDFILE") http=:$HTTP_PORT arm=$ARM platform=$PLATFORM"
}

stop_all() {
  if [ -f "$VLLM_PIDFILE" ]; then
    kill "$(cat "$VLLM_PIDFILE")" 2>/dev/null || true
    rm -f "$VLLM_PIDFILE"
  fi
  if [ -f "$MASTER_PIDFILE" ]; then
    kill "$(cat "$MASTER_PIDFILE")" 2>/dev/null || true
    rm -f "$MASTER_PIDFILE"
  fi
  pkill -f "vllm serve $MODEL" 2>/dev/null || true
  pkill -9 -f "VLLM::EngineCore" 2>/dev/null || true
  pkill -9 -f "VLLM::Worker" 2>/dev/null || true
  pkill -f "mooncake_master --rpc_port=$RPC_PORT" 2>/dev/null || true
  sleep 2
  echo "stopped :$HTTP_PORT :$RPC_PORT"
}

case "${1:-}" in
  start) start_master; start_vllm ;;
  stop) stop_all ;;
  *) echo "usage: ARM=a|b $0 start|stop"; exit 2 ;;
esac
