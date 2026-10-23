#!/bin/bash
# Full fill / overflow / r1 / r2 protocol, with per-attempt evidence and gates.
# A = SSD offload only. B = offload + prefetch. Primary result = r1 screen log.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/env.sh"

BASE_LOGDIR="$LOGDIR"
RUN_DIR="${RUN_DIR:-$RESULTDIR/ab-$(date -u +%Y%m%dT%H%M%S)-$$}"
mkdir -p "$RUN_DIR"
# Never allow a second invocation to replace a previous run's evidence.
if ! mkdir "$RUN_DIR/.run-owned"; then
  echo "RUN_DIR_ALREADY_USED $RUN_DIR" >&2
  exit 1
fi
exec > >(tee -a "$RUN_DIR/controller.log") 2>&1
ACTIVE=0
ATTEMPT_RC=0
ATTEMPT_REASON=not_started
ATTEMPT_PHASE=none
BASE_SETTLE_SEC="$SETTLE_SEC"

finish_controller() {
  local original_rc=$? cleanup_rc=0
  trap - EXIT INT TERM
  if [ "$ACTIVE" = 1 ]; then
    "$HERE/serve.sh" stop || cleanup_rc=$?
  fi
  python3 - "$RUN_DIR/controller-status.json" "$original_rc" "$cleanup_rc" <<'PY'
import json, pathlib, sys
path, original, cleanup = pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
path.write_text(json.dumps(dict(original_rc=original, cleanup_rc=cleanup,
                               ok=original == 0 and cleanup == 0), indent=2) + '\n')
PY
  # A cleanup failure must not hide the original controller/benchmark error.
  if [ "$original_rc" = 0 ] && [ "$cleanup_rc" != 0 ]; then original_rc=73; fi
  exit "$original_rc"
}
trap finish_controller EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

empty_ssd() {
  case "$SSD" in
    *ssd_dsv4*|*ssd_8b*|*prefetch_2646*|*prefetch-2646*)
      echo "REFUSING_OTHER_SSD $SSD"; return 1 ;;
    /tmp|/tmp/*) echo "SSD_IS_TMP $SSD"; return 1 ;;
  esac
  mkdir -p "$SSD"
  find "$SSD" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  echo "emptied $SSD"
}

# 70 = any expired lease; 71 = prefetch registration not ready; 74 = an
# unqualified not-ready occurrence needing review. Preserve all matching lines.
scan_logs() {
  python3 - "$LOGDIR" "$RESULTDIR" "$ATTEMPT_DIR/gate-$1.json" <<'PY'
import json, pathlib, re, sys
logdir, results, output = map(pathlib.Path, sys.argv[1:])
files = [logdir / 'master.log', logdir / 'vllm.log'] + sorted(results.glob('*.bench.log'))
matches = dict(lease=[], registration_not_ready=[], other_not_ready=[])
registration = re.compile(r'\bRegisterPrefetchTask\b|prefetch[^\n]*regist|regist[^\n]*prefetch', re.I)
for path in files:
    if not path.exists():
        continue
    lines = path.read_text(errors='replace').splitlines()
    for i, line in enumerate(lines):
        item = dict(file=str(path), line=i + 1, text=line)
        if 'LEASE_EXPIRED' in line:
            matches['lease'].append(item)
        if 'REPLICA_IS_NOT_READY' in line:
            # Thread-interleaved adjacent records do not prove registration.
            # Classify only an explicit registration marker on this error line;
            # retain neighboring lines as evidence for ambiguous cases.
            context = '\n'.join(lines[max(0, i - 1):min(len(lines), i + 2)])
            item['context'] = context
            category = 'registration_not_ready' if registration.search(line) else 'other_not_ready'
            matches[category].append(item)
rc = 70 if matches['lease'] else 74 if matches['other_not_ready'] else 71 if matches['registration_not_ready'] else 0
output.write_text(json.dumps(dict(rc=rc, matches=matches), indent=2) + '\n')
if rc:
    print('ARM_LOG_GATE rc=' + str(rc) + ' evidence=' + str(output))
raise SystemExit(rc)
PY
}

run_step() {
  local phase="$1" step_rc=0 gate_rc=0
  shift
  ATTEMPT_PHASE="$phase"
  "$@" || step_rc=$?
  scan_logs "$phase" || gate_rc=$?
  if [ "$gate_rc" != 0 ]; then
    ATTEMPT_REASON="log_gate_$gate_rc"
    return "$gate_rc"
  fi
  if [ "$step_rc" != 0 ]; then
    ATTEMPT_REASON="${phase}_rc_$step_rc"
    return "$step_rc"
  fi
}

check_fill() {
  python3 - "$RESULTDIR/${ARM}_fill.bench.log" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(errors='replace') if path.exists() else ''
counts = re.findall(r'Successful requests:\s*(\d+)', text)
n = int(counts[-1]) if counts else 0
print('FAIL_FAST_FILL success', n)
if n <= 0:
    print('FILL_ZERO_ABORT')
    raise SystemExit(72)
PY
}

attempt_protocol() {
  local arm="$1" rc=0 fill_rc=0
  run_step start "$HERE/serve.sh" start || return $?
  run_step ready "$HERE/wait_ready.sh" || return $?
  echo "----- fill (write prefixes into the store) -----"
  DATASET="$DATADIR/prompts.jsonl" CONC="$FILL_CONCURRENCY" \
    run_step fill "$HERE/bench.sh" "${arm}_fill.json" || rc=$?
  # Even a failed benchmark may report zero successes. Preserve the immediate
  # fill gate, while expired leases / registration errors retain their reason.
  check_fill || fill_rc=$?
  if [ "$rc" = 70 ]; then return "$rc"; fi
  if [ "$fill_rc" != 0 ]; then ATTEMPT_REASON=fill_zero; return "$fill_rc"; fi
  if [ "$rc" != 0 ]; then return "$rc"; fi

  echo "----- overflow (evict fill keys out of DRAM onto SSD) -----"
  DATASET="$DATADIR/overflow.jsonl" CONC="$FILL_CONCURRENCY" \
    NPROMPTS="$OVERFLOW_PREFIXES" BSEED="$OVERFLOW_SEED" \
    run_step overflow "$HERE/bench.sh" "${arm}_overflow.json" || return $?
  echo "----- settle ${SETTLE_SEC}s (leases / offload) -----"
  run_step settle sleep "$SETTLE_SEC" || return $?
  echo "----- measure r1 c=${MEASURE_CONCURRENCY} (PRIMARY) -----"
  DATASET="$DATADIR/prompts.jsonl" CONC="$MEASURE_CONCURRENCY" \
    run_step r1 "$HERE/bench.sh" "${arm}_r1.json" || return $?
  echo "----- measure r2 c=${MEASURE_CONCURRENCY} (contamination check) -----"
  DATASET="$DATADIR/prompts.jsonl" CONC="$MEASURE_CONCURRENCY" \
    run_step r2 "$HERE/bench.sh" "${arm}_r2.json" || return $?
}

one_attempt() {
  local arm="$1" number="$2" settle="$3" protocol_rc=0 stop_rc=0 final_gate=0
  ATTEMPT_DIR="$RUN_DIR/arm-${arm}/attempt-${number}"
  export ARM="$arm" LOGDIR="$ATTEMPT_DIR/logs" RESULTDIR="$ATTEMPT_DIR/results"
  export CFG_A="$ATTEMPT_DIR/mooncake_a.json" CFG_B="$ATTEMPT_DIR/mooncake_b.json"
  export SETTLE_SEC="$settle"
  mkdir -p "$ATTEMPT_DIR"
  # env.sh derives log/pidfile names from LOGDIR; no shared paths survive here.
  # shellcheck disable=SC1091
  . "$HERE/env.sh"
  ATTEMPT_REASON=ok
  ATTEMPT_PHASE=start
  python3 - "$ATTEMPT_DIR/config.json" <<'PY'
import json, os, pathlib, sys
keys = 'ARM MODEL PKG RUNTIME HTTP_PORT RPC_PORT METRICS_PORT PLATFORM NPU TP_SIZE MAX_MODEL_LEN MAX_NUM_SEQS GPU_MEM PREFIX_TOKENS NUM_PREFIXES OVERFLOW_PREFIXES SEED OVERFLOW_SEED FILL_CONCURRENCY MEASURE_CONCURRENCY CUSTOM_OUTPUT_LEN SETTLE_SEC SEGMENT_SIZE LOCAL_BUFFER_SIZE SSD_GET_WAIT_MS SSD LOGDIR RESULTDIR DATADIR CFG_A CFG_B'.split()
pathlib.Path(sys.argv[1]).write_text(json.dumps({k: os.environ.get(k) for k in keys}, indent=2) + '\n')
PY
  echo "########## ARM $arm attempt=$number settle=$settle evidence=$ATTEMPT_DIR ##########"
  ACTIVE=1
  attempt_protocol "$arm" || protocol_rc=$?
  "$HERE/serve.sh" stop || stop_rc=$?
  ACTIVE=0
  scan_logs final || final_gate=$?
  ATTEMPT_RC="$protocol_rc"
  if [ "$final_gate" != 0 ] && { [ "$protocol_rc" != 72 ] || [ "$final_gate" = 70 ]; }; then
    ATTEMPT_RC="$final_gate"
    ATTEMPT_REASON="log_gate_$final_gate"
  fi
  if [ "$stop_rc" != 0 ]; then
    ATTEMPT_RC=73
    ATTEMPT_REASON=shutdown_failed
  fi
  python3 - "$ATTEMPT_DIR/attempt-status.json" "$ATTEMPT_RC" "$ATTEMPT_REASON" \
      "$ATTEMPT_PHASE" "$protocol_rc" "$stop_rc" "$settle" <<'PY'
import json, pathlib, sys
p, rc, reason, phase, protocol, stop, settle = sys.argv[1:]
pathlib.Path(p).write_text(json.dumps(dict(rc=int(rc), reason=reason, phase=phase,
    protocol_rc=int(protocol), stop_rc=int(stop), settle_sec=settle,
    valid=int(rc) == 0), indent=2) + '\n')
PY
  echo "ARM_ATTEMPT_STATUS arm=$arm attempt=$number rc=$ATTEMPT_RC reason=$ATTEMPT_REASON"
}

one_arm() {
  local arm="$1"
  one_attempt "$arm" 1 "$BASE_SETTLE_SEC"
  if [ "$ATTEMPT_RC" = 71 ]; then
    echo "REGISTRATION_NOT_READY_RETRY arm=$arm SETTLE_SEC=700 failed_evidence=$ATTEMPT_DIR"
    empty_ssd
    one_attempt "$arm" 2 700
  fi
  if [ "$ATTEMPT_RC" != 0 ]; then
    echo "ARM_INVALID_STOP arm=$arm rc=$ATTEMPT_RC reason=$ATTEMPT_REASON evidence=$ATTEMPT_DIR"
    return "$ATTEMPT_RC"
  fi
  # All final logs/config/process state exist before the next arm may start.
  test -f "$LOGDIR/master.log"
  test -f "$LOGDIR/vllm.log"
  test -f "$LOGDIR/stop-status.json"
  test -f "$CFG_A"
  test -f "$CFG_B"
  scan_logs archived
  printf '%s\n' "$ATTEMPT_DIR" >"$RUN_DIR/arm-${arm}/valid-attempt.txt"
  echo "ARM_VALID_ARCHIVED arm=$arm evidence=$ATTEMPT_DIR"
}

# Stop the base LOGDIR's owned service before deleting any SSD contents. A stale
# pidfile never authorizes a broad process-name kill, and stop failures are fatal.
echo "A/B evidence: $RUN_DIR (base logs: $BASE_LOGDIR)"
"$HERE/serve.sh" stop
empty_ssd
python3 "$HERE/gen_dataset.py" \
  --num-prefixes "$NUM_PREFIXES" --prefix-tokens "$PREFIX_TOKENS" \
  --seed "$SEED" --out-prefix "$DATADIR/prompts"
python3 "$HERE/gen_dataset.py" \
  --num-prefixes "$OVERFLOW_PREFIXES" --prefix-tokens "$PREFIX_TOKENS" \
  --seed "$OVERFLOW_SEED" --out-prefix "$DATADIR/overflow"
one_arm a
empty_ssd
one_arm b

echo "########## done ##########"
echo "Read valid-attempt.txt under $RUN_DIR/arm-a and arm-b; primary logs are results/a_r1.bench.log and results/b_r1.bench.log."
echo "gain_pct = (A - B) / A * 100 on median / mean / p99 of r1"
