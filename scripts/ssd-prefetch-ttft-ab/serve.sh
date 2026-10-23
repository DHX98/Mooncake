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
  python3 - "$MOONCAKE_JSON" "$SSD" "$ARM" "$SEGMENT_SIZE" "$SSD_GET_WAIT_MS" \
      "${PREFETCH_OVERRIDE:-}" <<'PY'
import json, sys
path, ssd, arm, seg, wait, prefetch_ov = sys.argv[1:7]
with open(path, encoding="utf-8") as fh:
    cfg = json.load(fh)
cfg["ssd_offload_path"] = ssd
# Matrix arms pass PREFETCH_OVERRIDE ("true"/"false"); the original a/b
# harness leaves it unset and keeps the arm == "b" rule.
cfg["enable_ssd_prefetch"] = (
    prefetch_ov.lower() == "true" if prefetch_ov else arm == "b"
)
cfg["ssd_get_wait_ms"] = int(wait)
cfg["global_segment_size"] = seg
with open(path, "w", encoding="utf-8") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
print("json", path, "prefetch", cfg["enable_ssd_prefetch"], "seg", seg, "wait", wait)
PY
}

# Each service has a private session and a supervisor which records its exit
# status. PID start times prevent stale pidfiles from targeting a reused PID.
launch_service() {
  local role="$1" logfile="$2" pidfile="$3"
  shift 3
  if [ -e "$pidfile" ] || [ -e "$pidfile.owner.json" ]; then
    echo "START_STATE_EXISTS $role $pidfile (run stop first)" >&2
    return 1
  fi
  rm -f "$pidfile.exit"
  nohup setsid bash -c '
    status=$1; pidfile=$2; shift 2
    "$@" & child=$!
    printf "%s\n" "$child" >"$pidfile"
    set +e
    wait "$child"
    rc=$?
    printf "%s\n" "$rc" >"$status"
    # Keep the recorded session leader alive while orphaned workers drain.
    # This also lets stop identify workers if the API exited before stop ran.
    python3 -c '\''
import os, pathlib, sys, time
leader = int(sys.argv[1])
while True:
    alive = False
    for entry in pathlib.Path("/proc").iterdir():
        if not entry.name.isdigit() or int(entry.name) in (leader, os.getpid()):
            continue
        try:
            fields = (entry / "stat").read_text().rsplit(")", 1)[1].split()
            if int(fields[3]) == leader and fields[0] not in ("Z", "X"):
                alive = True
                break
        except (FileNotFoundError, ProcessLookupError):
            pass
    if not alive:
        break
    time.sleep(.25)
'\'' "$$"
    exit "$rc"
  ' _ "$pidfile.exit" "$pidfile" "$@" >"$logfile" 2>&1 &
  local supervisor=$!
  python3 - "$role" "$pidfile" "$supervisor" "$@" <<'PY'
import json, os, pathlib, sys, time
role, pidfile, supervisor = sys.argv[1], pathlib.Path(sys.argv[2]), int(sys.argv[3])
def proc(pid):
    try:
        fields = pathlib.Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return dict(pid=pid, state=fields[0], ppid=int(fields[1]), pgid=int(fields[2]),
                    sid=int(fields[3]), start=int(fields[19]))
    except (FileNotFoundError, ProcessLookupError):
        return None
for _ in range(100):
    try:
        target = int(pidfile.read_text().strip())
        break
    except (FileNotFoundError, ValueError):
        time.sleep(.05)
else:
    raise SystemExit("SERVICE_PID_MISSING " + role)
root = proc(supervisor)
if root is None or root['pgid'] != supervisor or root['sid'] != supervisor:
    raise SystemExit("SERVICE_SESSION_MISSING " + role)
members = []
for entry in pathlib.Path('/proc').iterdir():
    if entry.name.isdigit():
        item = proc(int(entry.name))
        if item and item['sid'] == supervisor:
            members.append(item)
owner = dict(role=role, root=root, target=proc(target), target_pid=target,
             members=members, command=sys.argv[4:],
             boot_id=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip())
pathlib.Path(str(pidfile) + '.owner.json').write_text(json.dumps(owner, indent=2) + '\n')
print(f"SERVICE_STARTED role={role} pid={target} session={supervisor}")
PY
}

start_master() {
  write_json
  mkdir -p "$SSD" "$LOGDIR"
  launch_service master "$MASTER_LOG" "$MASTER_PIDFILE" "$PKG/mooncake_master" \
    --rpc_port="$RPC_PORT" \
    --metrics_port="$METRICS_PORT" \
    --enable_offload=true \
    --offload_on_evict=true \
    --promotion_on_hit="${PROMOTION_ON_HIT:-false}" \
    --default_kv_lease_ttl=${KV_LEASE_TTL_MS:-2000} \
    --root_fs_dir="$SSD" \
    --eviction_high_watermark_ratio=0.6 \
    --eviction_ratio=0.4 \
    --memory_allocator=offset \
    --logtostderr=true
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

  launch_service vllm "$VLLM_LOG" "$VLLM_PIDFILE" vllm serve "$MODEL" \
    --host "${VLLM_HOST:-0.0.0.0}" \
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
    "${VLLM_EXTRA_ARGS[@]}"
  echo "vllm pid=$(cat "$VLLM_PIDFILE") http=:$HTTP_PORT arm=$ARM platform=$PLATFORM"
}

stop_all() {
  python3 - "$LOGDIR" "$VLLM_PIDFILE" "$MASTER_PIDFILE" \
      "$VLLM_LOG" "$MASTER_LOG" "$CFG_A" "$CFG_B" \
      "${SHUTDOWN_TIMEOUT_SEC:-120}" "${MASTER_SHUTDOWN_TIMEOUT_SEC:-20}" <<'PY'
import datetime, json, os, pathlib, re, shutil, signal, sys, time
logdir, vpid, mpid, vlog, mlog, cfga, cfgb = map(pathlib.Path, sys.argv[1:8])
timeouts = dict(vllm=float(sys.argv[8]), master=float(sys.argv[9]))
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
evidence = logdir / ('stop-' + stamp)
evidence.mkdir(parents=True)
boot = pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()
report = dict(evidence=str(evidence), services=[], errors=[], cleanup=[])
def write(name, data):
    (evidence / name).write_text(json.dumps(data, indent=2) + '\n')
def proc(pid):
    try:
        base = pathlib.Path(f'/proc/{pid}')
        fields = (base / 'stat').read_text().rsplit(')', 1)[1].split()
        return dict(pid=pid, state=fields[0], ppid=int(fields[1]), pgid=int(fields[2]),
                    sid=int(fields[3]), start=int(fields[19]),
                    command=(base / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace'))
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return None
def table():
    return {int(p.name): item for p in pathlib.Path('/proc').iterdir()
            if p.name.isdigit() and (item := proc(int(p.name))) is not None}
def matches(item, expected):
    return item and expected and item['pid'] == expected['pid'] and item['start'] == expected['start']
def live(item):
    return item and item['state'] not in ('Z', 'X')
def signal_exact(item, sig):
    if matches(proc(item['pid']), item):
        try:
            os.kill(item['pid'], sig)
        except ProcessLookupError:
            pass
def snapshot_files():
    for src in (vlog, mlog, cfga, cfgb):
        if src.exists():
            shutil.copy2(src, evidence / src.name)
states = []
for role, pidfile in (('vllm', vpid), ('master', mpid)):
    state = dict(role=role, pidfile=str(pidfile), errors=[], known={})
    ownerfile = pathlib.Path(str(pidfile) + '.owner.json')
    try:
        owner = json.loads(ownerfile.read_text())
        if owner['boot_id'] != boot:
            state['note'] = 'STALE_BOOT_ID'
        else:
            state['owner'] = owner
            for item in owner['members'] + [owner['root'], owner.get('target')]:
                if item:
                    state['known'][item['pid']] = item
    except FileNotFoundError:
        # Historical/unowned pidfiles are evidence only. Never signal their PID.
        if pidfile.exists():
            state['note'] = 'STALE_UNOWNED_PIDFILE'
            state['pidfile_text'] = pidfile.read_text(errors='replace')
            try:
                candidate = proc(int(state['pidfile_text'].strip()))
            except ValueError:
                candidate = None
            if live(candidate):
                state['errors'].append('UNOWNED_LIVE_PID')
                state['unowned_candidate'] = candidate
    except (ValueError, KeyError, TypeError) as exc:
        state['errors'].append('INVALID_OWNER_STATE: ' + str(exc))
    states.append(state)
def refresh(state):
    processes = table()
    known = state['known']
    active = {pid: processes[pid] for pid, old in known.items()
              if matches(processes.get(pid), old) and live(processes[pid])}
    # Expand only while an exact recorded process is alive. A stale PID/session
    # cannot grant ownership of a process from a later invocation.
    if active:
        sid = state['owner']['root']['sid']
        changed = True
        while changed:
            changed = False
            for pid, item in processes.items():
                if pid not in active and live(item) and (item['sid'] == sid or item['ppid'] in active):
                    known[pid] = item
                    active[pid] = item
                    changed = True
    return active
def scoped_snapshot():
    # Do not put unrelated container/host processes or their arguments in the
    # evidence. An unowned live stale-PID candidate is diagnostic only.
    items = {}
    for state in states:
        items.update(refresh(state))
        candidate = state.get('unowned_candidate')
        if candidate:
            current = proc(candidate['pid'])
            if matches(current, candidate):
                items[current['pid']] = current
    return list(items.values())
write('processes-before.json', scoped_snapshot())
for state in states:
    role = state['role']
    active = refresh(state)
    state['before'] = list(active.values())
    owner = state.get('owner')
    target = owner.get('target') if owner else None
    current = proc(owner['target_pid']) if owner else None
    if live(current) and matches(current, target):
        print(f"STOP_TERM role={role} pid={current['pid']}", flush=True)
        signal_exact(current, signal.SIGTERM)
    elif active:
        # The API has already died: workers must finish without being forced.
        state['note'] = 'API_ALREADY_EXITED'
    deadline = time.monotonic() + timeouts[role]
    while active and time.monotonic() < deadline:
        time.sleep(min(.25, max(0, deadline - time.monotonic())))
        active = refresh(state)
    state['after_graceful'] = list(active.values())
    if active:
        state['errors'].append('GRACEFUL_SHUTDOWN_TIMEOUT')
    statusfile = pathlib.Path(str(state['pidfile']) + '.exit')
    if owner:
        try:
            state['exit_code'] = int(statusfile.read_text().strip())
            if state['exit_code'] not in (0, 143):
                state['errors'].append('SERVICE_EXIT_' + str(state['exit_code']))
        except (FileNotFoundError, ValueError):
            state['errors'].append('SERVICE_EXIT_STATUS_MISSING')
    report['errors'].extend(role + ':' + error for error in state['errors'])
    # vLLM is always observed completely before the master receives TERM.
    report['services'].append({k: v for k, v in state.items() if k != 'known'})
snapshot_files()
write('processes-after-graceful.json', scoped_snapshot())
shutdown_errors = re.compile(
    r'segmentation fault|\bsegfault\b|\bSIGSEGV\b|'
    r'\bexit(?:code|[\s_-]+code)\s*[:=]?\s*-11\b|'
    r'workers still running after (?:grace period|SIGTERM);\s*sending SIG(?:TERM|KILL)|'
    r'\[shutdown\]\s*Process manager:\s*force killing remaining process(?:es)?\b|'
    r'unregister[^\n]*(?:fail|error)|'
    r'(?:fail|error)[^\n]*unregister', re.I)
for path in (vlog, mlog):
    if path.exists():
        for number, line in enumerate(path.read_text(errors='replace').splitlines(), 1):
            if shutdown_errors.search(line):
                report['errors'].append(f'LOG_SHUTDOWN_ERROR:{path.name}:{number}:{line}')
report['ok'] = not report['errors']
# Declare and save a failed graceful shutdown before any forceful cleanup.
write('stop-status.json', report)
print('STOP_STATUS ' + json.dumps(report), flush=True)
if report['errors']:
    for state in states:
        for item in refresh(state).values():
            report['cleanup'].append(dict(pid=item['pid'], start=item['start'], signal='SIGKILL'))
            signal_exact(item, signal.SIGKILL)
    time.sleep(.25)
    snapshot_files()
write('processes-after-cleanup.json', scoped_snapshot())
for state in states:
    remaining = list(refresh(state).values())
    if remaining:
        report['errors'].append(state['role'] + ':OWNED_PROCESSES_REMAIN_AFTER_CLEANUP')
    # Preserve owner/exit evidence before retiring stale control files.
    pidfile = pathlib.Path(state['pidfile'])
    for suffix in ('', '.owner.json', '.exit'):
        src = pathlib.Path(str(pidfile) + suffix)
        if src.exists():
            shutil.copy2(src, evidence / (state['role'] + src.name[len(pidfile.name):] + '.state'))
            if not remaining:
                src.unlink()
report['ok'] = not report['errors']
write('stop-status.json', report)
(logdir / 'stop-status.json').write_text(json.dumps(report, indent=2) + '\n')
print(f"STOP_FINAL ok={report['ok']} evidence={evidence}", flush=True)
raise SystemExit(0 if report['ok'] else 1)
PY
}

case "${1:-}" in
  start) start_master; start_vllm ;;
  stop) stop_all ;;
  *) echo "usage: ARM=a|b $0 start|stop"; exit 2 ;;
esac
