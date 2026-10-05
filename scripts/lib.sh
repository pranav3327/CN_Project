#!/usr/bin/env bash
# Shared helpers for every laptop-side script. bash 3.2+ (macOS default) compatible.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$ROOT/.generated"
EVID="$ROOT/evidence"
SSH_CFG="$GEN/ssh_config"
NODES="node-1 node-2 node-3 node-4"

# shellcheck source=../settings.env
. "$ROOT/settings.env"
TTL="${TTL:-30}"
PHASE="${PHASE_OVERRIDE:-${PHASE:-2}}"
URL="https://app.$DOMAIN"

# Written by Terraform (IPs, key). Absent until `make up` has run once.
load_cluster() {
  if [ -f "$GEN/cluster.env" ]; then
    # shellcheck source=/dev/null
    . "$GEN/cluster.env"
  fi
}
load_cluster
NODE1_IP="${NODE1_IP:-10.0.1.11}"; NODE2_IP="${NODE2_IP:-10.0.1.12}"
NODE3_IP="${NODE3_IP:-10.0.1.13}"; NODE4_IP="${NODE4_IP:-10.0.1.14}"
EDGE_IP="$NODE2_IP"; STANDBY_IP="$NODE3_IP"

# ---- output -------------------------------------------------------------------
if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
  BLU=$'\033[34m'; MAG=$'\033[35m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  B=; DIM=; RED=; GRN=; YEL=; BLU=; MAG=; CYN=; RST=
fi
LOG=/dev/null   # extra copy of everything printed by the helpers below

die()     { printf '%sERROR:%s %s\n' "$RED$B" "$RST" "$*" >&2; exit 1; }
info()    { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$LOG"; }
section() { printf '\n%s━━ %s %s\n' "$B$BLU" "$*" "$RST"; printf '\n== %s\n' "$*" >> "$LOG"; }
# report <ok|changed|failed|skip> <where> <what>   (Ansible-style converge output)
CHANGED=0; FAILED=0
report() {
  local c="$GRN"
  case "$1" in changed) c="$YEL"; CHANGED=$((CHANGED + 1)) ;; failed) c="$RED"; FAILED=$((FAILED + 1)) ;; skip) c="$DIM" ;; esac
  printf '  %s%-8s%s %-7s %s\n' "$c" "$1" "$RST" "$2" "$3"
  printf '  %-8s %-7s %s\n' "$1" "$2" "$3" >> "$LOG"
  if [ -n "${COUNTS:-}" ]; then echo "$1" >> "$COUNTS"; fi   # survives subshells
}

# ---- nodes --------------------------------------------------------------------
ip_of() {
  case "$1" in
    node-1) echo "$NODE1_IP" ;; node-2) echo "$NODE2_IP" ;;
    node-3) echo "$NODE3_IP" ;; node-4) echo "$NODE4_IP" ;;
    *) die "unknown node '$1'" ;;
  esac
}
role_of() {
  case "$1" in
    node-1) echo "Mac 1 - primary DNS (dnsmasq) + test client" ;;
    node-2) echo "Mac 2 - edge: nginx reverse proxy, TLS, load balancer" ;;
    node-3) echo "Mac 3 - Backend A :3001 (+ backup DNS, standby edge)" ;;
    node-4) echo "Mac 4 - Backend B :3002 + test client" ;;
  esac
}
short_of() {
  case "$1" in
    node-1) echo "DNS + client" ;; node-2) echo "edge" ;;
    node-3) echo "backend A" ;;    node-4) echo "backend B + client" ;;
  esac
}

need_cluster() {
  load_cluster
  [ -f "$SSH_CFG" ] && [ -f "$GEN/cluster.env" ] || die "no infrastructure yet – run: make up"
  local n v
  for n in 1 2 3 4; do
    v="NODE${n}_PUB"
    [ -n "${!v:-}" ] || die "node-$n has no public IP (stopped?) – run: make up   (or: make start)"
  done
}

# ---- remote execution ---------------------------------------------------------
on()    { local n="$1"; shift; ssh -F "$SSH_CFG" "$n" "$@"; }
on_q()  { local n="$1"; shift; ssh -n -F "$SSH_CFG" "$n" "$@" 2>/dev/null; }   # quiet, no stdin

# push_file <node> <remote-path> <mode>  < content
# Installs the file only if the content differs. Prints "ok" or "changed".
push_file() {
  on "$1" "sudo sh -c 't=\$(mktemp); cat > \"\$t\"; mkdir -p \"\$(dirname $2)\";
    if cmp -s \"\$t\" $2; then rm -f \"\$t\"; echo ok;
    else install -m $3 \"\$t\" $2; rm -f \"\$t\"; echo changed; fi'"
}

# render <template>: replace @PLACEHOLDERS@ with values
render() {
  sed -e "s|@TEAM@|$TEAM|g"           -e "s|@DOMAIN@|$DOMAIN|g"      -e "s|@TTL@|$TTL|g" \
      -e "s|@NODE1_IP@|$NODE1_IP|g"   -e "s|@NODE2_IP@|$NODE2_IP|g" \
      -e "s|@NODE3_IP@|$NODE3_IP|g"   -e "s|@NODE4_IP@|$NODE4_IP|g" \
      -e "s|@APP_IP@|${APP_IP:-$EDGE_IP}|g" -e "s|@SELF_IP@|${SELF_IP:-}|g" -e "s|@IFACE@|${IFACE:-}|g" \
      -e "s|@UNIT@|${UNIT:-}|g" -e "s|@BACKEND_ID@|${BACKEND_ID:-}|g" -e "s|@PORT@|${PORT:-}|g" \
      "$1"
}

# DNS servers the clients use in this phase
dns_servers() { if [ "$PHASE" = 1 ]; then echo "$NODE1_IP"; else echo "$NODE1_IP $NODE3_IP"; fi; }

# ---- dispatcher: script.sh some-command -> cmd_some_command -------------------
dispatch() {
  local name="${1:-}" cmd
  [ -n "$name" ] || die "usage: $0 <command>"
  shift
  cmd="cmd_$(echo "$name" | tr '-' '_')"
  declare -F "$cmd" >/dev/null || die "unknown command '$name' – see: make help"
  "$cmd" "$@"
}
