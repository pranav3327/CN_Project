#!/usr/bin/env bash
# The dashboard. Window "live" = the 5 terminals:
#
#   ┌──────────────────────┬──────────────────────┐
#   │ node-1  DNS + client │ node-2  edge nginx   │   4 real SSH shells
#   ├──────────────────────┼──────────────────────┤   (make live types into them)
#   │ node-3  backend A    │ node-4  backend B    │
#   ├──────────────────────┴──────────────────────┤
#   │ YOU – laptop shell in the repo (make …)      │   5th terminal
#   └─────────────────────────────────────────────┘
#
# Extra windows: "logs" (all service logs live) and "wire" (live packets).
# Every pane is recorded with timestamps in evidence/terminal-logs/<date>/.
# Keys: Ctrl-b 0/1/2 switch window · Ctrl-b z zoom pane · Ctrl-b d detach · mouse on
#
# Usage: tmux.sh [--no-attach]
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
need_cluster
command -v tmux >/dev/null || die "tmux not installed (macOS: brew install tmux)"

S=cn
ATTACH=1; [ "${1:-}" = --no-attach ] && ATTACH=0

open_session() {
  [ "$ATTACH" = 1 ] || return 0
  tmux select-window -t "$S:live" 2>/dev/null || true
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "$S"; else tmux attach -t "$S"; fi
}
if tmux has-session -t "$S" 2>/dev/null; then open_session; exit 0; fi

LOGDIR="$EVID/terminal-logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOGDIR"
Q_CFG="$(printf '%q' "$SSH_CFG")"
Q_ROOT="$(printf '%q' "$ROOT")"

shell_cmd() {   # interactive SSH shell; Enter reconnects if it drops
  echo "while true; do ssh -F $Q_CFG -t $1; printf '\\n[%s disconnected] press Enter to reconnect ' $1; read -r _; done"
}
live_cmd() {    # long-running remote command; reconnects automatically
  echo "while true; do ssh -F $Q_CFG -t $1 $2; echo '[$1: stream ended – reconnecting in 3s]'; sleep 3; done"
}
control_cmd() {
  echo "cd $Q_ROOT && printf '\\033[1mCN project – control terminal\\033[0m  (repo: %s)\\n  make live      full final demo (Section 8)\\n  make live-p1   Phase 1 review   ·   make live-p2   Phase 2 review\\n  make help      everything else\\n\\n' $Q_ROOT && exec \${SHELL:-/bin/bash}"
}

decorate() {    # decorate <pane-id> <title> <log-name>
  tmux set-option -p -t "$1" @title "$2"
  tmux pipe-pane -o -t "$1" "$(printf '%q %q' "$ROOT/scripts/tslog.sh" "$LOGDIR/$3.log")"
}
window_opts() {
  tmux set-option -w -t "$1" remain-on-exit on
  tmux set-option -w -t "$1" pane-border-status top
  tmux set-option -w -t "$1" pane-border-format ' #{?pane_active,#[bold],}#{@title} '
}
split() {       # split <target> <title> <log> <cmd> [tmux args]  -> pane id
  local t="$1" title="$2" log="$3" cmd="$4" id; shift 4
  id="$(tmux split-window -d -P -F '#{pane_id}' -t "$t" -c "$ROOT" "$@" "$cmd")"
  decorate "$id" "$title" "$log"; echo "$id"
}
title_of() { echo "$1 | $(short_of "$1") | $(ip_of "$1")"; }

# ---- window 1: live (the 5 terminals) -------------------------------------------
p1="$(tmux new-session -d -P -F '#{pane_id}' -s "$S" -n live -c "$ROOT" -x 240 -y 64 "$(shell_cmd node-1)")"
tmux set-option -t "$S" mouse on
tmux set-option -t "$S" history-limit 50000
tmux set-option -t "$S" status-left '#[bold] CN #[default]'
tmux set-option -t "$S" status-right ' #(date +%H:%M:%S) '
tmux set-option -t "$S" status-interval 1
window_opts "$p1"; decorate "$p1" "$(title_of node-1)" node-1
p2="$(split "$p1" "$(title_of node-2)" node-2 "$(shell_cmd node-2)" -h -l 50%)"
p3="$(split "$p1" "$(title_of node-3)" node-3 "$(shell_cmd node-3)" -v -l 50%)"
p4="$(split "$p2" "$(title_of node-4)" node-4 "$(shell_cmd node-4)" -v -l 50%)"
pc="$(split "$p3" "YOU | laptop | $ROOT" control "$(control_cmd)" -f -v -l 30%)"
tmux set-option -t "$S" @p1 "$p1"; tmux set-option -t "$S" @p2 "$p2"
tmux set-option -t "$S" @p3 "$p3"; tmux set-option -t "$S" @p4 "$p4"
tmux set-option -t "$S" @pc "$pc"; tmux set-option -t "$S" @logdir "$LOGDIR"

# ---- window 2: logs -------------------------------------------------------------
l1="$(tmux new-window -d -P -F '#{pane_id}' -t "$S:" -n logs -c "$ROOT" "$(live_cmd node-1 'cn-follow dns')")"
window_opts "$l1"; decorate "$l1" "DNS primary | node-1 dnsmasq" log-dns-primary
q="$(split "$l1" "EDGE | node-2 nginx" log-edge "$(live_cmd node-2 'cn-follow nginx')" -h)"
q="$(split "$q" "BACKEND A | node-3 :3001" log-backend-a "$(live_cmd node-3 'cn-follow backend')")"
tmux select-layout -t "$l1" tiled >/dev/null
q="$(split "$q" "BACKEND B | node-4 :3002" log-backend-b "$(live_cmd node-4 'cn-follow backend')")"
tmux select-layout -t "$l1" tiled >/dev/null
q="$(split "$q" "DNS backup | node-3 dnsmasq" log-dns-backup "$(live_cmd node-3 'cn-follow dns')")"
tmux select-layout -t "$l1" tiled >/dev/null
q="$(split "$q" "EDGE standby | node-3 nginx" log-edge-standby "$(live_cmd node-3 'cn-follow nginx')")"
tmux select-layout -t "$l1" tiled >/dev/null

# ---- window 3: wire -------------------------------------------------------------
w1="$(tmux new-window -d -P -F '#{pane_id}' -t "$S:" -n wire -c "$ROOT" "$(live_cmd node-4 'cn-wire client')")"
window_opts "$w1"; decorate "$w1" "PACKETS | client node-4 (DNS + HTTPS)" wire-client
q="$(split "$w1" "PACKETS | edge node-2 -> backends (plain HTTP)" wire-edge "$(live_cmd node-2 'cn-wire edge')" -v)"
q="$(split "$q" "PACKETS | DNS server node-1 (:53)" wire-dns "$(live_cmd node-1 'cn-wire dns')" -v)"
tmux select-layout -t "$w1" even-vertical >/dev/null

tmux select-window -t "$S:live"
tmux select-pane -t "$pc"
echo "dashboard ready – terminal logs: ${LOGDIR#"$ROOT"/}"
open_session
