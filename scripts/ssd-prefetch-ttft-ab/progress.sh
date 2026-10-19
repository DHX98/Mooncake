#!/bin/bash
# Progress heartbeat for long harness runs. Source it, then:
#   progress_init "label" "$RESULTDIR"
#   progress_start                      # spawn the heartbeat
#   progress_state "arm 3 pure: fill"   # at every phase transition
#   progress_stop                       # final tick + final push
#
# Local:  $RESULTDIR/PROGRESS.md — rolling log, one entry per
#         PROGRESS_INTERVAL seconds (default 600), trimmed to ~240 lines.
# Remote: branch ssd-prefetch/v3-progress — amended + force-pushed every
#         PROGRESS_PUSH_EVERY seconds (default 1800), best-effort only:
#         network failures never break the run. Set PROGRESS_REMOTE_SRC to
#         a local clone of the fork to enable pushing.

PROGRESS_INTERVAL="${PROGRESS_INTERVAL:-600}"
PROGRESS_PUSH_EVERY="${PROGRESS_PUSH_EVERY:-1800}"
PROGRESS_BRANCH="${PROGRESS_BRANCH:-ssd-prefetch/v3-progress}"

progress_init() {
  PROGRESS_LABEL="$1"
  PROGRESS_DIR="$2"
  PROGRESS_FILE="$PROGRESS_DIR/PROGRESS.md"
  PROGRESS_STATE_FILE="$PROGRESS_DIR/.progress_state"
  mkdir -p "$PROGRESS_DIR"
  {
    echo "# live progress — $PROGRESS_LABEL"
    echo "started: $(date '+%F %T') host: $(hostname 2>/dev/null || echo '?')"
    echo
  } > "$PROGRESS_FILE"
  echo "starting" > "$PROGRESS_STATE_FILE"
}

progress_state() { echo "$*" > "$PROGRESS_STATE_FILE"; }

_progress_tick() {
  {
    echo "## $(date '+%F %T') — $PROGRESS_LABEL — $(cat "$PROGRESS_STATE_FILE" 2>/dev/null || echo '?')"
    local latest
    latest=$(ls -t "$PROGRESS_DIR"/*.log 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
      echo "log: $(basename "$latest")"
      tr '\r' '\n' < "$latest" 2>/dev/null \
        | grep -aE '%\||it/s|Successful|probe|trial|####|-----|VERDICT' \
        | tail -n 3
    fi
    echo
  } >> "$PROGRESS_FILE"
  if [ "$(wc -l < "$PROGRESS_FILE")" -gt 240 ]; then
    { head -n 4 "$PROGRESS_FILE"; echo "…(older ticks trimmed)…"; \
      tail -n 220 "$PROGRESS_FILE"; } > "$PROGRESS_FILE.tmp"
    mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"
  fi
}

_progress_push() {
  [ -n "${PROGRESS_REPO_DIR:-}" ] || return 0
  cp "$PROGRESS_FILE" "$PROGRESS_REPO_DIR/PROGRESS.md" 2>/dev/null || return 0
  git -C "$PROGRESS_REPO_DIR" add PROGRESS.md >/dev/null 2>&1 || return 0
  if ! git -C "$PROGRESS_REPO_DIR" commit -q --amend --no-edit >/dev/null 2>&1; then
    git -C "$PROGRESS_REPO_DIR" commit -q -m "live progress" >/dev/null 2>&1 || return 0
  fi
  # Command-line proxy overrides the machine gitconfig. The run itself
  # stays proxy-free; only this push uses PROGRESS_HTTP_PROXY.
  proxy="${PROGRESS_HTTP_PROXY:-}"
  cred="${PROGRESS_CRED_FILE:-}"
  args=(-C "$PROGRESS_REPO_DIR")
  if [ -n "$cred" ]; then
    args+=(-c "credential.helper=store --file $cred")
  fi
  if [ -n "$proxy" ]; then
    args+=(-c "http.proxy=$proxy" -c "https.proxy=$proxy")
  fi
  git "${args[@]}" push -f origin "HEAD:refs/heads/$PROGRESS_BRANCH" >/dev/null 2>&1 || true
}

progress_start() {
  if [ -n "${PROGRESS_REMOTE_SRC:-}" ] && [ -z "${PROGRESS_REPO_DIR:-}" ]; then
    PROGRESS_REPO_DIR="$PROGRESS_DIR/.progress-repo"
    rm -rf "$PROGRESS_REPO_DIR"
    git -C "$PROGRESS_REMOTE_SRC" worktree add --detach "$PROGRESS_REPO_DIR" >/dev/null 2>&1 \
      || git clone -q "$PROGRESS_REMOTE_SRC" "$PROGRESS_REPO_DIR" >/dev/null 2>&1 \
      || unset PROGRESS_REPO_DIR
  fi
  (
    last_push=$(date +%s)
    while true; do
      sleep "$PROGRESS_INTERVAL"
      _progress_tick
      now=$(date +%s)
      if [ $((now - last_push)) -ge "$PROGRESS_PUSH_EVERY" ]; then
        _progress_push
        last_push=$now
      fi
    done
  ) &
  PROGRESS_PID=$!
  echo "progress heartbeat pid=$PROGRESS_PID file=$PROGRESS_FILE every=${PROGRESS_INTERVAL}s push_every=${PROGRESS_PUSH_EVERY}s branch=$PROGRESS_BRANCH"
}

progress_stop() {
  [ -n "${PROGRESS_PID:-}" ] && kill "$PROGRESS_PID" 2>/dev/null || true
  progress_state "DONE $(date '+%F %T')"
  _progress_tick
  _progress_push
}
