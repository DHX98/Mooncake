#!/bin/bash
# Store-level decomposition orchestrator: one mooncake_master per arm,
# python driver per arm, minutes per arm instead of hours.
#
#   bash scripts/ssd-prefetch-ttft-ab/store_matrix.sh
#
# Env:
#   ARMS="e0 e1a e1b e1c e2a e2b e2c"   (default all; e1d only with overlay)
#   STORE_PY_DIR   site-packages dir holding libmooncake_store.so + bindings
#   MASTER_BIN     mooncake_master binary (from the 2fc4ebe2 build)
#   OVERLAY_DIR_E1D  decoupled-kick build libs (only needed for arm e1d)
#   ROOT           work dir (SSD dirs, logs, results live under it)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

ARMS="${ARMS:-e0 e1a e1b e1c e2a e2b e2c}"
STORE_PY_DIR="${STORE_PY_DIR:?site-packages dir with the store libs}"
MASTER_BIN="${MASTER_BIN:?mooncake_master from the 2fc4ebe2 build}"
ROOT="${ROOT:-/tmp/store-matrix}"
RESULTDIR="${RESULTDIR:-$HERE/results-store}"
RPC_PORT="${RPC_PORT:-50211}"
mkdir -p "$ROOT" "$RESULTDIR"

arm_cfg() { # sets PREFETCH / WAIT / ONHIT / THRESH for arm $1
  case "$1" in
    e0)  PREFETCH=false; WAIT=0;   ONHIT=false; THRESH=2 ;;
    e1a) PREFETCH=true;  WAIT=0;   ONHIT=false; THRESH=2 ;;
    e1b) PREFETCH=true;  WAIT=500; ONHIT=false; THRESH=2 ;;
    e1c) PREFETCH=true;  WAIT=500; ONHIT=false; THRESH=2 ;;
    e1d) PREFETCH=true;  WAIT=0;   ONHIT=false; THRESH=2 ;;
    e2a) PREFETCH=true;  WAIT=500; ONHIT=false; THRESH=2 ;;
    e2b) PREFETCH=false; WAIT=0;   ONHIT=true;  THRESH=2 ;;
    e2c) PREFETCH=true;  WAIT=500; ONHIT=true;  THRESH=2 ;;
    *) echo "BAD_ARM $1"; exit 2 ;;
  esac
}

stop_master() {
  [ -f "$ROOT/master.pid" ] && kill "$(cat "$ROOT/master.pid")" 2>/dev/null || true
  rm -f "$ROOT/master.pid"
  pkill -f "mooncake_master --rpc_port=$RPC_PORT" 2>/dev/null || true
  sleep 1
}

for arm in $ARMS; do
  arm_cfg "$arm"
  ssd="$ROOT/ssd_$arm"
  mkdir -p "$ssd"
  find "$ssd" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  mlog="$ROOT/master_$arm.log"

  if [ "$arm" = e1d ]; then
    ov="${OVERLAY_DIR_E1D:-}"
    [ -n "$ov" ] && [ -d "$ov" ] || {
      echo "e1d needs OVERLAY_DIR_E1D (decoupled-kick build) — skipping e1d"
      continue
    }
    cp -a "$ov"/. "$STORE_PY_DIR"/
  fi
  md5sum "$STORE_PY_DIR"/libmooncake_store.so* 2>/dev/null \
    > "$RESULTDIR/build_$arm.md5.log" || true

  stop_master
  : >"$mlog"
  nohup "$MASTER_BIN" \
    --rpc_port="$RPC_PORT" \
    --default_kv_lease_ttl=2000 \
    --root_fs_dir="$ssd" \
    --enable_offload=true \
    --offload_on_evict=true \
    --promotion_on_hit="$ONHIT" \
    --promotion_admission_threshold="$THRESH" \
    --eviction_high_watermark_ratio=0.6 \
    --eviction_ratio=0.4 \
    --memory_allocator=offset \
    --logtostderr=true \
    >"$mlog" 2>&1 &
  echo $! >"$ROOT/master.pid"
  sleep 2

  echo "########## ARM $arm prefetch=$PREFETCH wait=$WAIT on_hit=$ONHIT ##########"
  ARM="$arm" \
    MASTER_SERVER="127.0.0.1:$RPC_PORT" \
    MC_METADATA_SERVER="${MC_METADATA_SERVER:-P2PHANDSHAKE}" \
    LOCAL_HOSTNAME=127.0.0.1 \
    PREFETCH_ENABLED="$PREFETCH" \
    SSD_GET_WAIT_MS="$WAIT" \
    KV_LEASE_TTL_MS=2000 \
    MOONCAKE_OFFLOAD_FILE_STORAGE_PATH="$ssd" \
    MOONCAKE_OFFLOAD_HEARTBEAT_INTERVAL_SECONDS=2 \
    MOONCAKE_OFFLOAD_BUCKET_KEYS_LIMIT=10 \
    RESULTDIR="$RESULTDIR" \
    PYTHONPATH="${PYTHONPATH:-}" \
    python3 "$HERE/store_matrix.py" 2>&1 | tee "$RESULTDIR/store_matrix_${arm}.log"

  stop_master
  # Hard gate: lease fix must hold here too.
  if grep -aq "LEASE_EXPIRED" "$mlog" "$RESULTDIR/store_matrix_${arm}.log"; then
    echo "LEASE_EXPIRED seen in arm $arm — INVESTIGATE BEFORE TRUSTING" \
      | tee -a "$RESULTDIR/store_matrix_${arm}.log"
  fi
done

echo
echo "########## store matrix done — summary ##########"
python3 "$HERE/summarize_store_matrix.py" "$RESULTDIR" $ARMS
