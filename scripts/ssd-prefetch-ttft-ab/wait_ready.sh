#!/bin/bash
# Block until vLLM /v1/models answers. Default 15 minutes.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"
sec="${1:-900}"
deadline=$(( $(date +%s) + sec ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ -f "$VLLM_PIDFILE" ] && ! kill -0 "$(cat "$VLLM_PIDFILE")" 2>/dev/null; then
    echo "VLLM_DEAD"
    tail -n 80 "$VLLM_LOG" || true
    exit 1
  fi
  if curl -sS "http://127.0.0.1:${HTTP_PORT}/v1/models" 2>/dev/null | grep -q "$SERVED_NAME"; then
    echo "ready :$HTTP_PORT $SERVED_NAME"
    exit 0
  fi
  sleep 5
done
echo "NOT_READY :$HTTP_PORT"
tail -n 80 "$VLLM_LOG" || true
exit 1
