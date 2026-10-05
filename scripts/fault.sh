#!/usr/bin/env bash
# Practice for Extension F: inject ONE hidden fault, diagnose it, then `make restore`.
#   fault.sh inject [name] [--quiet]    random fault unless a name is given
#   fault.sh reveal                     show what was injected
#   fault.sh list
# Every fault is undone by `make restore` (the idempotent converge).
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
need_cluster

FAULTS="dns-down dns-wrong-record client-resolver edge-down edge-port-blocked edge-bad-upstream edge-wrong-cert backends-down backends-firewalled"

describe() {
  case "$1" in
    dns-down)            echo "DNS layer: dnsmasq stopped on BOTH DNS servers" ;;
    dns-wrong-record)    echo "DNS layer: app/api point to $NODE4_IP (a machine without a web server)" ;;
    client-resolver)     echo "DNS layer (client): node-4 uses the AWS resolver, which does not know .$DOMAIN" ;;
    edge-down)           echo "Application layer at the edge: nginx stopped on node-2" ;;
    edge-port-blocked)   echo "Transport layer: node-2 firewall DROPs tcp/443 (connection times out)" ;;
    edge-bad-upstream)   echo "Edge config: nginx upstream ports changed to 3901/3902 (502)" ;;
    edge-wrong-cert)     echo "TLS layer: nginx serves a certificate for wrong.$DOMAIN from an unknown CA" ;;
    backends-down)       echo "Application layer behind the edge: both backend services stopped (502)" ;;
    backends-firewalled) echo "Transport layer behind the edge: backends reject the edge (502)" ;;
    *) die "unknown fault '$1' – one of: $FAULTS" ;;
  esac
}

inject() {
  case "$1" in
    dns-down)
      on_q node-1 "sudo systemctl stop dnsmasq"; on_q node-3 "sudo systemctl stop dnsmasq" ;;
    dns-wrong-record)
      on_q node-1 "sudo cn-dns set $NODE4_IP"; on_q node-3 "sudo cn-dns set $NODE4_IP" ;;
    client-resolver)
      on_q node-4 "sudo cn-resolver set 169.254.169.253" ;;
    edge-down)
      on_q node-2 "sudo systemctl stop nginx" ;;
    edge-port-blocked)
      on_q node-2 "sudo iptables -I INPUT 1 -p tcp --dport 443 -m comment --comment cn-fault -j DROP" ;;
    edge-bad-upstream)
      on_q node-2 "sudo sed -i 's/:3001 /:3901 /; s/:3002 /:3902 /' /etc/nginx/conf.d/cn-edge.conf && sudo systemctl reload nginx" ;;
    edge-wrong-cert)
      on_q node-2 "sudo openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=wrong.$DOMAIN \
                   -keyout /etc/nginx/cn-tls/tls.key -out /etc/nginx/cn-tls/tls.crt >/dev/null 2>&1 && sudo systemctl reload nginx" ;;
    backends-down)
      on_q node-3 "sudo systemctl stop backend-a"; on_q node-4 "sudo systemctl stop backend-b" ;;
    backends-firewalled)
      on_q node-3 "sudo iptables -I INPUT 1 -s $NODE2_IP -p tcp --dport 3001 -m comment --comment cn-fault -j REJECT --reject-with tcp-reset"
      on_q node-4 "sudo iptables -I INPUT 1 -s $NODE2_IP -p tcp --dport 3002 -m comment --comment cn-fault -j REJECT --reject-with tcp-reset" ;;
  esac
  for n in $NODES; do on_q "$n" "sudo resolvectl flush-caches" || true; done
}

cmd_list() { local f; for f in $FAULTS; do printf '  %-20s %s\n' "$f" "$(describe "$f")"; done; }

cmd_inject() {
  local name="" quiet=0 a
  for a in "$@"; do case "$a" in --quiet) quiet=1 ;; *) name="$a" ;; esac; done
  if [ -z "$name" ]; then
    # shellcheck disable=SC2086
    set -- $FAULTS; name="$(eval echo "\${$(( (RANDOM % $#) + 1 ))}")"
  fi
  describe "$name" >/dev/null
  inject "$name" >/dev/null
  mkdir -p "$GEN"; echo "$name" > "$GEN/last-fault"
  if [ "$quiet" = 1 ]; then describe "$name"
  else echo "A fault has been injected. Diagnose from node-4:  cn-diagnose   (reveal: make fault-reveal · fix all: make restore)"; fi
}

cmd_reveal() {
  [ -f "$GEN/last-fault" ] || { echo "no practice fault active"; exit 0; }
  local f; f="$(cat "$GEN/last-fault")"; echo "$f: $(describe "$f")"
}

dispatch "$@"
