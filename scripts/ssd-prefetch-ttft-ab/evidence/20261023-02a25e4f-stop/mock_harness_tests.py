#!/usr/bin/env python3
"""Mock-only harness tests. No model, NPU, network, or product binary is used."""
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

SOURCE = Path(sys.argv[1]).resolve()
OUT = Path(sys.argv[2]).resolve()
OUT.mkdir(parents=True, exist_ok=True)
RESULTS = []
REAL_ENV = len(sys.argv) > 3 and sys.argv[3] in ('real', 'worker-real', 'mixed-real')

ENV = r'''#!/bin/bash
ROOT=${TEST_ROOT:?}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG=$HERE/bin; RUNTIME=$HERE; MODEL=mock-model; SERVED_NAME=mock-model
ARM=${ARM:-a}; LOGDIR=${LOGDIR:-$ROOT/base-logs}; RESULTDIR=${RESULTDIR:-$ROOT/results}
DATADIR=${DATADIR:-$ROOT/data}; SSD=$ROOT/ssd
CFG_A=${CFG_A:-$ROOT/a.json}; CFG_B=${CFG_B:-$ROOT/b.json}
MOONCAKE_JSON=$CFG_A; [ "$ARM" != b ] || MOONCAKE_JSON=$CFG_B
mkdir -p "$LOGDIR" "$RESULTDIR" "$DATADIR" "$SSD" "$(dirname "$CFG_A")" "$(dirname "$CFG_B")"
printf '{}\n' >"$CFG_A"; printf '{}\n' >"$CFG_B"
MASTER_LOG=$LOGDIR/master.log; VLLM_LOG=$LOGDIR/vllm.log
MASTER_PIDFILE=$LOGDIR/master.pid; VLLM_PIDFILE=$LOGDIR/vllm.pid
HTTP_PORT=19981; RPC_PORT=19982; METRICS_PORT=19983; NPU=mock
SEGMENT_SIZE=256MB; SSD_GET_WAIT_MS=2000; LOCAL_BUFFER_SIZE=8MB
PLATFORM=mock; TP_SIZE=8; BLOCK_SIZE=128; KV_JSON='{}'; VLLM_EXTRA_ARGS=()
MAX_MODEL_LEN=20480; MAX_NUM_SEQS=4; GPU_MEM=0.95
NUM_PREFIXES=12; OVERFLOW_PREFIXES=12; PREFIX_TOKENS=16385
SEED=42; OVERFLOW_SEED=1042; FILL_CONCURRENCY=1; MEASURE_CONCURRENCY=4
CUSTOM_OUTPUT_LEN=8; SETTLE_SEC=${SETTLE_SEC:-0}
platform_vllm_env() { :; }
export ROOT HERE PKG RUNTIME MODEL SERVED_NAME ARM LOGDIR RESULTDIR DATADIR SSD CFG_A CFG_B
export MOONCAKE_JSON MASTER_LOG VLLM_LOG MASTER_PIDFILE VLLM_PIDFILE
export HTTP_PORT RPC_PORT METRICS_PORT NPU SEGMENT_SIZE SSD_GET_WAIT_MS LOCAL_BUFFER_SIZE
export PLATFORM TP_SIZE MAX_MODEL_LEN MAX_NUM_SEQS GPU_MEM NUM_PREFIXES OVERFLOW_PREFIXES
export PREFIX_TOKENS SEED OVERFLOW_SEED FILL_CONCURRENCY MEASURE_CONCURRENCY CUSTOM_OUTPUT_LEN SETTLE_SEC
'''

MOCK_SERVE = r'''#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/env.sh"
attempt=base; [[ "$LOGDIR" != */attempt-*/* ]] || attempt=$(basename "$(dirname "$LOGDIR")")
printf '%s %s %s settle=%s\n' "$1" "$ARM" "$attempt" "$SETTLE_SEC" >>"$ROOT/trace"
if [ "$1" = start ]; then
  if [ "$ARM" = b ]; then
    test -f "$RUN_DIR/arm-a/valid-attempt.txt"
    grep -q 'arm=a' "$(cat "$RUN_DIR/arm-a/valid-attempt.txt")/logs/master.log"
  fi
  printf 'arm=%s attempt=%s master\n' "$ARM" "$attempt" >"$MASTER_LOG"
  printf 'arm=%s attempt=%s api\n' "$ARM" "$attempt" >"$VLLM_LOG"
  if [ "$MOCK_CASE" = startfailure ]; then exit 19; fi
else
  printf '{"ok":true}\n' >"$LOGDIR/stop-status.json"
  if [[ "$attempt" != base && "$MOCK_CASE" = shutdown ]]; then
    printf 'Failed to unregister client\n' >>"$VLLM_LOG"
    printf '{"ok":false}\n' >"$LOGDIR/stop-status.json"
    exit 1
  fi
  if [[ "$attempt" != base && "$MOCK_CASE" = latelease ]]; then
    printf 'LEASE_EXPIRED on final cleanup\n' >>"$MASTER_LOG"
  fi
fi
'''

MOCK_BENCH = r'''#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/env.sh"
attempt=$(basename "$(dirname "$LOGDIR")")
phase=${1%.json}; phase=${phase#*_}
printf 'bench %s %s %s settle=%s conc=%s nprompts=%s\n' "$ARM" "$attempt" "$phase" "$SETTLE_SEC" "$CONC" "${NPROMPTS:-$NUM_PREFIXES}" >>"$ROOT/trace"
success=12
if [[ "$MOCK_CASE" = fillzero* && "$phase" = fill ]]; then success=0; fi
printf 'Successful requests: %s\n' "$success" >"$RESULTDIR/${1%.json}.bench.log"
if [[ "$MOCK_CASE" = fillzero_replica && "$phase" = fill ]]; then
  printf 'SSD prefetch: RegisterPrefetchTask failed: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG"
fi
if [[ "$MOCK_CASE" = fillzero_generic_registration && "$phase" = fill ]]; then
  printf 'RegisterPrefetchTask failed: REPLICA_IS_NOT_READY\nmetadata query failed: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG"
fi
if [[ "$MOCK_CASE" = benchfailure && "$phase" = r1 ]]; then exit 42; fi
if [[ "$phase" = overflow && "$ARM" = a ]]; then
  case "$MOCK_CASE" in
    lease) printf 'LEASE_EXPIRED\n' >>"$MASTER_LOG" ;;
    lease_replica) printf 'LEASE_EXPIRED\nSSD prefetch: RegisterPrefetchTask failed: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG" ;;
    lease_generic_registration) printf 'LEASE_EXPIRED\nRegisterPrefetchTask failed: REPLICA_IS_NOT_READY\nmetadata query failed: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG" ;;
    generic) printf 'query: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG" ;;
    prefetch_query) printf 'SSD prefetch: metadata query failed for key=mock: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG" ;;
    prefetch_keys) printf 'SSD prefetch: PrefetchKeys failed for key=mock: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG" ;;
    adjacent_reg_success) printf 'RegisterPrefetchTask success for another key\nquery failed: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG" ;;
    split_registration) printf 'RegisterPrefetchTask failed\nREPLICA_IS_NOT_READY\n' >>"$MASTER_LOG" ;;
    mixed_generic_registration) printf 'RegisterPrefetchTask failed: REPLICA_IS_NOT_READY\nmetadata query failed: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG" ;;
    replica_once) if [[ "$attempt" = attempt-1 ]]; then printf 'SSD prefetch: RegisterPrefetchTask failed for key=mock: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG"; fi ;;
    replica_twice) printf 'RegisterPrefetchTask failed: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG" ;;
  esac
fi
if [[ "$phase" = overflow && "$ARM" = b && "$MOCK_CASE" = replica_b && "$attempt" = attempt-1 ]]; then
  printf 'SSD prefetch: RegisterPrefetchTask failed: REPLICA_IS_NOT_READY\n' >>"$MASTER_LOG"
fi
'''

FAKE_SERVICE = r'''#!/usr/bin/env python3
import os, pathlib, resource, signal, subprocess, sys, time
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
role = 'master' if pathlib.Path(sys.argv[0]).name == 'mooncake_master' else 'vllm'
mode = os.environ.get('MOCK_SERVICE_MODE', 'graceful')
events = pathlib.Path(os.environ['TEST_ROOT']) / 'events'
def event(text):
    with events.open('a') as fh: fh.write(text + '\n')
    print(text, flush=True)
if len(sys.argv) > 1 and sys.argv[1] == 'mockworker':
    if mode == 'hang': signal.signal(signal.SIGTERM, signal.SIG_IGN)
    if mode == 'workersegfault':
        signal.signal(signal.SIGTERM, lambda *_: os.kill(os.getpid(), signal.SIGSEGV))
    event('worker_ready')
    while True: time.sleep(.05)
worker = None
if role == 'vllm':
    worker = subprocess.Popen([sys.executable, sys.argv[0], 'mockworker'])
def term(signum, frame):
    event(role + '_term')
    if role == 'vllm' and mode == 'segfault': os.kill(os.getpid(), signal.SIGSEGV)
    if role == 'vllm' and mode == 'unregister': event('Failed to unregister client')
    if role == 'vllm' and mode == 'internalterm':
        event('[shutdown] Executor: workers still running after grace period; sending SIGTERM count=1')
    if role == 'vllm' and mode == 'internalkill':
        event('[shutdown] Executor: workers still running after SIGTERM; sending SIGKILL count=1')
    if role == 'vllm' and mode == 'internalmanager':
        event('[shutdown] Process manager: force killing remaining processes count=1')
        event('[shutdown] Process manager: force killing remaining process mock pid 1')
    if role == 'vllm' and mode == 'graceful':
        event('[shutdown] Process manager: send sigterm to process mock')
    if worker and mode != 'hang':
        worker.terminate(); worker.wait(timeout=3)
        if mode == 'workersegfault':
            event('Worker proc mock died unexpectedly (exit code: ' + str(worker.returncode) + '), shutting down executor.')
        else:
            event('Worker mock exitcode=' + str(worker.returncode))
        event('worker_drained')
    raise SystemExit(0)
signal.signal(signal.SIGTERM, term)
event(role + '_ready')
while True: time.sleep(.05)
'''

def put(path, text):
    path.write_text(text)
    path.chmod(0o755)

def fixture(name):
    p = OUT / name
    p.mkdir()
    (p / 'bin').mkdir()
    if REAL_ENV:
        shutil.copy2(SOURCE / 'env.sh', p / 'env.sh')
        shutil.copy2(SOURCE / 'mooncake.json.tmpl', p / 'mooncake.json.tmpl')
        shutil.copytree(SOURCE / 'platforms', p / 'platforms')
    else:
        put(p / 'env.sh', ENV)
    put(p / 'bin' / 'sleep', '#!/bin/bash\nprintf "sleep %s\\n" "$*" >>"$TEST_ROOT/trace"\n')
    env = dict(os.environ, TEST_ROOT=str(p), PATH=str(p / 'bin') + ':' + os.environ['PATH'],
               RUN_DIR=str(p / 'run'), MOCK_CASE=name, SHUTDOWN_TIMEOUT_SEC='1',
               MASTER_SHUTDOWN_TIMEOUT_SEC='2')
    if REAL_ENV:
        env.update(ROOT=str(p), PKG=str(p / 'bin'), RUNTIME=str(p), MODEL='mock-model',
                   LOGDIR=str(p / 'base-logs'), RESULTDIR=str(p / 'results'),
                   DATADIR=str(p / 'data'), SSD=str(p / 'ssd'), CFG_A=str(p / 'base-a.json'),
                   CFG_B=str(p / 'base-b.json'), NUM_PREFIXES='12', OVERFLOW_PREFIXES='12',
                   MEASURE_CONCURRENCY='4', MAX_NUM_SEQS='4', FILL_CONCURRENCY='1',
                   PREFIX_TOKENS='16385', SETTLE_SEC='0', PLATFORM='ascend')
        for name in ('env.sh', 'mooncake.json.tmpl', 'platforms/ascend.env'):
            assert (p / name).read_bytes() == (SOURCE / name).read_bytes()
    return p, env

def run_script(p, env, script, *args, timeout=20):
    done = subprocess.run(['bash', str(p / script), *args], env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    (p / (script + '.' + (args[0] if args else 'run') + '.output')).write_text(done.stdout)
    return done

def check_controller(case, expected):
    p, env = fixture(case)
    shutil.copy2(SOURCE / 'run_ab.sh', p / 'run_ab.sh')
    put(p / 'serve.sh', MOCK_SERVE)
    put(p / 'bench.sh', MOCK_BENCH)
    put(p / 'wait_ready.sh', '#!/bin/bash\nexit 0\n')
    if REAL_ENV and case != 'controller_error':
        shutil.copy2(SOURCE / 'gen_dataset.py', p / 'gen_dataset.py')
    else:
        put(p / 'gen_dataset.py', 'import sys\n' + ('sys.exit(42)\n' if case == 'controller_error' else ''))
    assert not (p / 'run').exists(), 'must exercise a fresh run directory'
    done = run_script(p, env, 'run_ab.sh')
    assert done.returncode == expected, (case, done.returncode, done.stdout)
    trace = (p / 'trace').read_text()
    status = json.loads((p / 'run/controller-status.json').read_text())
    assert status['original_rc'] == expected
    if expected and case not in ('replica_b',):
        assert 'start b ' not in trace, trace
    if case == 'success':
        for arm in 'ab':
            for phase in ('fill', 'overflow', 'r1', 'r2'):
                assert f'bench {arm} attempt-1 {phase} ' in trace
        assert 'bench a attempt-1 overflow settle=0 conc=1 nprompts=12' in trace
        assert 'bench b attempt-1 r1 settle=0 conc=4 nprompts=12' in trace
        if REAL_ENV:
            for arm in 'ab':
                attempt = p / f'run/arm-{arm}/attempt-1'
                cfg = json.loads((attempt / f'mooncake_{arm}.json').read_text())
                assert cfg['protocol'] == 'ascend'
                assert cfg['enable_ssd_prefetch'] == (arm == 'b')
                config = json.loads((attempt / 'config.json').read_text())
                assert [config[k] for k in ('NUM_PREFIXES', 'OVERFLOW_PREFIXES', 'MEASURE_CONCURRENCY', 'MAX_NUM_SEQS')] == ['12', '12', '4', '4']
            for name in ('prompts', 'overflow'):
                lines = (p / f'data/{name}.jsonl').read_text().splitlines()
                assert len(lines) == 12
    if case == 'fillzero': assert ' overflow ' not in trace and ' r1 ' not in trace
    if case in ('lease', 'generic', 'replica_twice'): assert ' r1 ' not in trace
    if case in ('replica_once', 'replica_b'):
        retried = 'a' if case == 'replica_once' else 'b'
        other = 'b' if retried == 'a' else 'a'
        assert f'start {retried} attempt-2 settle=700' in trace
        assert f'start {other} attempt-2' not in trace
        assert 'sleep 700' in trace
        failed = json.loads((p / f'run/arm-{retried}/attempt-1/attempt-status.json').read_text())
        assert failed['rc'] == 71 and failed['stop_rc'] == 0
    if case == 'replica_twice':
        assert trace.count('start a') == 2 and 'attempt-3' not in trace
    if case == 'shutdown': assert 'attempt-2' not in trace
    if expected == 74: assert 'attempt-2' not in trace
    RESULTS.append(dict(test='controller_' + case, passed=True, rc=done.returncode))

def alive(pid):
    try:
        stat = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        return stat[0] not in ('Z', 'X')
    except FileNotFoundError:
        return False

def check_serve(mode, expected):
    p, env = fixture('service_' + mode)
    env['MOCK_SERVICE_MODE'] = mode
    shutil.copy2(SOURCE / 'serve.sh', p / 'serve.sh')
    put(p / 'bin/vllm', FAKE_SERVICE)
    put(p / 'bin/mooncake_master', FAKE_SERVICE)
    # This deliberately shares the same command text as the service but is not
    # in the service's recorded session. It must survive every stop path.
    sentinel = subprocess.Popen([str(p / 'bin/mooncake_master')], env=env,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        started = run_script(p, env, 'serve.sh', 'start')
        assert started.returncode == 0, started.stdout
        for _ in range(100):
            if (p / 'events').exists() and 'worker_ready' in (p / 'events').read_text(): break
            time.sleep(.02)
        stopped = run_script(p, env, 'serve.sh', 'stop')
        assert stopped.returncode == expected, (mode, stopped.returncode, stopped.stdout)
        assert sentinel.poll() is None, 'unrelated same-command process was killed'
        status = json.loads((p / 'base-logs/stop-status.json').read_text())
        evidence = Path(status['evidence'])
        assert (evidence / 'vllm.log').exists() and (evidence / 'master.log').exists()
        assert (evidence / 'processes-after-graceful.json').exists()
        if mode == 'graceful':
            events = (p / 'events').read_text()
            assert events.index('worker_drained') < events.index('master_term')
            assert not status['cleanup']
        if mode == 'hang':
            assert any('GRACEFUL_SHUTDOWN_TIMEOUT' in e for e in status['errors'])
            assert status['cleanup'], status
        if mode == 'segfault': assert any('SERVICE_EXIT_139' in e for e in status['errors'])
        if mode == 'unregister': assert any('LOG_SHUTDOWN_ERROR' in e for e in status['errors'])
        if mode == 'workersegfault':
            assert status['services'][0]['exit_code'] == 0
            assert any('LOG_SHUTDOWN_ERROR' in e and 'exit code: -11' in e for e in status['errors'])
        if mode in ('internalterm', 'internalkill', 'internalmanager'):
            assert status['services'][0]['exit_code'] == 0
            marker = 'force killing remaining process' if mode == 'internalmanager' else 'workers still running after'
            assert any('LOG_SHUTDOWN_ERROR' in e and marker in e for e in status['errors'])
        owned = json.loads((evidence / 'processes-before.json').read_text())
        assert all(item['pid'] != sentinel.pid for item in owned)
        assert all(not alive(item['pid']) for item in owned), owned
        RESULTS.append(dict(test='shutdown_' + mode, passed=True, rc=stopped.returncode))
    finally:
        sentinel.terminate()
        sentinel.wait(timeout=3)

def check_stale(live_pid):
    p, env = fixture('stale_' + str(live_pid))
    shutil.copy2(SOURCE / 'serve.sh', p / 'serve.sh')
    (p / 'base-logs').mkdir()
    sentinel = subprocess.Popen(['/bin/sleep', '30']) if live_pid else None
    try:
        (p / 'base-logs/vllm.pid').write_text(str(sentinel.pid if sentinel else 99999999))
        done = run_script(p, env, 'serve.sh', 'stop')
        assert done.returncode == (1 if live_pid else 0), done.stdout
        if sentinel: assert sentinel.poll() is None
        assert not (p / 'base-logs/vllm.pid').exists()
        RESULTS.append(dict(test='stale_pid_' + str(live_pid), passed=True, rc=done.returncode))
    finally:
        if sentinel: sentinel.terminate(); sentinel.wait(timeout=3)

if len(sys.argv) > 3 and sys.argv[3] == 'mixed-real':
    check_controller('mixed_generic_registration', 74)
    summary = dict(passed=len(RESULTS), real_environment=REAL_ENV, tests=RESULTS)
    summary['sources_sha256'] = {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
        for name in ('serve.sh', 'run_ab.sh', 'env.sh', 'mooncake.json.tmpl', 'platforms/ascend.env')}
    (OUT / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    raise SystemExit(0)

if len(sys.argv) > 3 and sys.argv[3] == 'worker-real':
    for mode in ('graceful', 'workersegfault', 'internalterm', 'internalkill', 'internalmanager'):
        check_serve(mode, 0 if mode == 'graceful' else 1)
    summary = dict(passed=len(RESULTS), real_environment=REAL_ENV, tests=RESULTS)
    summary['sources_sha256'] = {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
        for name in ('serve.sh', 'run_ab.sh', 'env.sh', 'mooncake.json.tmpl', 'platforms/ascend.env')}
    (OUT / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))
    raise SystemExit(0)

if len(sys.argv) > 3 and sys.argv[3] == 'extra':
    for case, expected in [('fillzero_replica', 72), ('lease_replica', 70),
                           ('startfailure', 19), ('benchfailure', 42)]:
        check_controller(case, expected)
    (OUT / 'summary.json').write_text(json.dumps(dict(passed=len(RESULTS), tests=RESULTS), indent=2) + '\n')
    print(json.dumps(dict(passed=len(RESULTS), tests=RESULTS), indent=2))
    raise SystemExit(0)

cases = [('success', 0), ('fillzero', 72), ('lease', 70),
                       ('generic', 74), ('replica_once', 0), ('replica_b', 0),
                       ('replica_twice', 71), ('shutdown', 73), ('latelease', 70),
                       ('controller_error', 42)]
if REAL_ENV:
    cases += [('prefetch_query', 74), ('prefetch_keys', 74), ('adjacent_reg_success', 74),
              ('split_registration', 74), ('fillzero_replica', 72), ('lease_replica', 70),
              ('startfailure', 19), ('benchfailure', 42), ('mixed_generic_registration', 74),
              ('lease_generic_registration', 70), ('fillzero_generic_registration', 72)]
for case, expected in cases:
    check_controller(case, expected)
for mode, expected in [('graceful', 0), ('hang', 1), ('segfault', 1), ('unregister', 1)]:
    check_serve(mode, expected)
check_stale(False)
check_stale(True)
summary = dict(passed=len(RESULTS), real_environment=REAL_ENV, tests=RESULTS)
if REAL_ENV:
    summary['original_sources_sha256'] = {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
        for name in ('env.sh', 'mooncake.json.tmpl', 'platforms/ascend.env', 'gen_dataset.py')}
    summary['harness_sources_sha256'] = {name: hashlib.sha256((SOURCE / name).read_bytes()).hexdigest()
        for name in ('serve.sh', 'run_ab.sh')}
(OUT / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
