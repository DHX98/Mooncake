#!/bin/bash
set -euo pipefail
export ROOT=/home/tester/prefetch_916/perf_test_prefetch_v3_verify
export RESULTDIR="$ROOT/results"
export LOGDIR="$ROOT/logs"
export DATADIR="$ROOT/data"
export SSD="$ROOT/ssd"
export MEASURE_CONCURRENCY=4
export MAX_NUM_SEQS=4
export GLOG_v=1
export GLOG_logtostderr=1
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
cd "$ROOT/scripts"
echo "===== VERIFY START $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
echo "HEAD=$(git -C /home/tester/prefetch_916/src/Mooncake rev-parse --short HEAD)"
echo "BRANCH=$(git -C /home/tester/prefetch_916/src/Mooncake branch --show-current)"
echo "STORE=$(md5sum /usr/local/python3.12.13/lib/python3.12/site-packages/mooncake/libmooncake_store.so | awk '{print $1}')"
echo "CONC=$MEASURE_CONCURRENCY MAX_NUM_SEQS=$MAX_NUM_SEQS GLOG_v=$GLOG_v ROOT=$ROOT"
grep -n 'GLOG_v\|--v=1' "$ROOT/scripts/env.sh" "$ROOT/scripts/serve.sh" || true
./run_ab.sh
echo "===== VERIFY DONE $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="
