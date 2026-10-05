#!/usr/bin/env bash
# make live / live-p1 / live-p2 / scene – the choreographed live demonstration.
#
# Commands are TYPED into the four server terminals (tmux send-keys), so the audience
# sees them run on the right machine. Each typed command ends with `cn_done <id> $?`,
# which prints a marker; the engine watches the pane for it to know the command
# finished. Verification checks run silently over SSH and print ✔/✘ here.
#
# Idempotent: every run starts with `converge` (known-good state), every scene
# restores what it broke, and Ctrl-C restores everything.
#
# Options (env / make vars): AUTO=1 no pauses · FROM=<n> start at scene n ·
#                            ONLY=<scene> · PACE=<seconds between commands>
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
need_cluster

S=cn
PACE="${PACE:-1.2}"
AUTO="${AUTO:-0}"
RUNID="$(date +%H%M%S)"
SEQ=0
D="$DOMAIN"
RUN_DIR="$EVID/live/$(date +%Y%m%d-%H%M%S)"
RESULTS="$EVID/results.tsv"
SCENE_NAME="-"

# ============================== engine ==============================================

in_session() { [ -n "${TMUX:-}" ] && [ "$(tmux display-message -p '#S' 2>/dev/null)" = "$S" ]; }
pane() { tmux show-options -t "$S" -v "@p${1#node-}"; }

label() {   # label <node> <what this terminal shows in this scene>
  tmux set-option -p -t "$(pane "$1")" @title "$1 | $(short_of "$1") | $2"
}
reset_labels() { local n; for n in $NODES; do label "$n" "$(ip_of "$n")"; done; }

type_in() {   # type_in <node> <command>  -> sets LAST_ID
  local p; p="$(pane "$1")"; SEQ=$((SEQ + 1)); LAST_ID="$RUNID$SEQ"
  tmux send-keys -t "$p" -l -- "$2; cn_done $LAST_ID \$?"
  tmux send-keys -t "$p" Enter
}
wait_id() {   # wait_id <node> <id> [timeout] -> exit status of the typed command
  local p t=0 max="${3:-90}" line rc
  p="$(pane "$1")"
  while [ "$t" -lt $((max * 4)) ]; do
    line="$(tmux capture-pane -p -J -t "$p" -S -3000 | grep -F -- "-- done #$2 (exit" | tail -1 || true)"
    if [ -n "$line" ]; then
      rc="$(echo "$line" | sed -n 's/.*(exit \([0-9]*\)).*/\1/p')"
      return "${rc:-0}"
    fi
    sleep 0.25; t=$((t + 1))
  done
  printf '    %s(timeout waiting for %s)%s\n' "$RED" "$1" "$RST"; return 124
}
run_in() {    # run_in <node> <command> [timeout]   type, wait, pause briefly
  # A failing command is often the point of a scene (failure demos): never abort,
  # just remember its status in LAST_RC.
  type_in "$1" "$2"
  LAST_RC=0; wait_id "$1" "$LAST_ID" "${3:-90}" || LAST_RC=$?
  sleep "$PACE"
}
start_in() {  # start_in <node> <command>   type, don't wait (use wait_for later)
  type_in "$1" "$2"; eval "BG_${1#node-}=$LAST_ID"
}
wait_for() {  # wait_for <node> [timeout]   wait for the last start_in on that node
  local v="BG_${1#node-}"; wait_id "$1" "${!v}" "${2:-120}" || true
}
all_run() {   # all_run <command>   same command on all four, in parallel
  local n; for n in $NODES; do start_in "$n" "$1"; done
  for n in $NODES; do wait_for "$n" "${2:-60}"; done; sleep "$PACE"
}
follow() {    # follow <node> <cmd> <label>   start a live view (stopped by stop_all)
  label "$1" "$3"
  tmux send-keys -t "$(pane "$1")" -l -- "$2"; tmux send-keys -t "$(pane "$1")" Enter
  FOLLOWING="$FOLLOWING $1"
}
stop_all() {  # Ctrl-C every live view, then make sure every shell is back at a prompt
  local n
  for n in $FOLLOWING; do tmux send-keys -t "$(pane "$n")" C-c; done
  FOLLOWING=""; sleep 0.5
  for n in $NODES; do type_in "$n" "true"; wait_id "$n" "$LAST_ID" 15 >/dev/null || true; done
}
clear_all() {
  local n p
  for n in $NODES; do
    p="$(pane "$n")"; tmux send-keys -t "$p" C-c; tmux send-keys -t "$p" -l -- "clear"; tmux send-keys -t "$p" Enter
  done
  sleep 0.4
  for n in $NODES; do tmux clear-history -t "$(pane "$n")"; done
}

# ---- presenter output (this terminal) ----
scene_header() {   # scene_header <title> <maps-to>
  SCENE_NO=$((SCENE_NO + 1))
  printf '\n%s┏━━ Scene %s/%s  %s %s\n┗━━ %s%s\n' "$B$MAG" "$SCENE_NO" "$SCENE_TOTAL" "$1" "$RST$DIM" "$2" "$RST"
  printf '\n== Scene %s: %s  (%s)\n' "$SCENE_NO" "$1" "$2" >> "$LOG"
}
say() { printf '  %s»%s %s\n' "$YEL" "$RST" "$*"; printf '  > %s\n' "$*" >> "$LOG"; }
act() { printf '  %s▸ %s%s\n' "$CYN" "$*" "$RST"; printf '  * %s\n' "$*" >> "$LOG"; }
check() {   # check <description> <node> <command>   silent verification
  local r=PASS
  if on_q "$2" "$3" >/dev/null; then printf '  %s✔%s %s\n' "$GRN" "$RST" "$1"
  else r=FAIL; printf '  %s✘ %s%s\n' "$RED" "$1" "$RST"; FAILS=$((FAILS + 1)); fi
  printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$SCENE_NAME" "$1" "$r" >> "$RESULTS"
  printf '  [%s] %s\n' "$r" "$1" >> "$LOG"
}
check_pane() {  # check_pane <description> <node> <grep -E pattern> [absent]
  local out r=PASS
  out="$(tmux capture-pane -p -J -t "$(pane "$2")" -S -3000)"
  if [ "${4:-}" = absent ]; then echo "$out" | grep -Eq -- "$3" && r=FAIL
  else echo "$out" | grep -Eq -- "$3" || r=FAIL; fi
  if [ "$r" = PASS ]; then printf '  %s✔%s %s\n' "$GRN" "$RST" "$1"
  else printf '  %s✘ %s%s\n' "$RED" "$1" "$RST"; FAILS=$((FAILS + 1)); fi
  printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$SCENE_NAME" "$1" "$r" >> "$RESULTS"
  printf '  [%s] %s\n' "$r" "$1" >> "$LOG"
}
hold() {   # hold <what happens next>: pause for explanation (AUTO: short wait)
  if [ "$AUTO" = 1 ]; then sleep 2; return; fi
  printf '  %s⏸  %s – Enter%s ' "$DIM" "$1" "$RST"; read -r _ </dev/tty || true
}
end_scene() {
  stop_all
  local n dir="$RUN_DIR/$(printf '%02d' "$SCENE_NO")-$SCENE_NAME"
  mkdir -p "$dir"
  for n in $NODES; do tmux capture-pane -p -J -t "$(pane "$n")" -S -3000 > "$dir/$n.txt"; done
  cp "$LOG" "$dir/control.txt" 2>/dev/null || true
  [ "$AUTO" = 1 ] && { sleep 2; return; }
  local a
  printf '\n  %s[Enter] next scene   [r] repeat   [q] quit%s ' "$B" "$RST"
  read -r a </dev/tty || true
  case "$a" in r|R) REPEAT=1 ;; q|Q) echo; say "stopping – restoring the baseline"; "$ROOT/scripts/converge.sh" restore >/dev/null && echo "  restored."; exit 0 ;; esac
}

# ============================== scenes ==============================================
# Each scene: header → what to say → commands in the right terminals → checks → restore.

scene_topology() {
  scene_header "Topology and IP inventory" "Task A · demo step 1"
  cat <<EOF | tee -a "$LOG"
                 AWS VPC  ·  subnet ${SUBNET_CIDR:-10.0.1.0/24} = the private LAN
     ┌──────────────┐  DNS :53   ┌──────────────┐  HTTPS :443  ┌──────────────┐
     │ node-1 Mac 1 │◀───────────│ node-4 Mac 4 │─────────────▶│ node-2 Mac 2 │
     │ dnsmasq      │            │ client + B   │              │ nginx edge   │
     │ $NODE1_IP    │            │ $NODE4_IP    │              │ $NODE2_IP    │
     └──────────────┘            └──────▲───────┘              └───┬──────┬───┘
                                        │ HTTP :3002 (round-robin) │      │ HTTP :3001
                                        └──────────────────────────┘      ▼
                                                                ┌──────────────┐
                                                                │ node-3 Mac 3 │
                                                                │ backend A    │
                                                                │ $NODE3_IP    │
                                                                └──────────────┘
EOF
  say "Four machines on ONE private subnet – the AWS VPC plays the role of the lab Wi-Fi."
  say "Cloud equivalents: node-1 ≈ Route 53 private zone, node-2 ≈ ALB/CDN edge, node-3/4 ≈ targets."
  local n; for n in $NODES; do label "$n" "identity (Task A)"; done
  all_run "cn-info"
  for n in $NODES; do check "$n has its fixed LAN address $(ip_of "$n")" "$n" "ip -4 addr | grep -q ' $(ip_of "$n")/24'"; done
  inventory_md
  say "Saved the IP / MAC / gateway table to evidence/inventory.md"
  end_scene
}

inventory_md() {
  local n row f="$EVID/inventory.md"
  mkdir -p "$EVID"
  {
    echo "# IP and service inventory  ($(date '+%F %T'))"; echo
    echo "| Machine | Role | Interface | IPv4/prefix | Mask | Gateway | MAC | Listening |"
    echo "|---|---|---|---|---|---|---|---|"
    for n in $NODES; do
      row="$(on_q "$n" 'i=$(cn-iface); c=$(ip -4 -o addr show dev $i | awk "{print \$4}");
        m=$(python3 -c "import ipaddress,sys;print(ipaddress.ip_interface(sys.argv[1]).netmask)" $c);
        g=$(ip route show default | awk "{print \$3; exit}");
        l=$(sudo ss -lntupH | awk "{print \$1\"/\"\$5}" | grep -E ":(53|80|443|3001|3002)$" | grep -v 127.0.0 | sed "s/0.0.0.0://; s/.*://" | sort -u | tr "\n" " ");
        echo "$i | $c | $m | $g | $(cat /sys/class/net/$i/address) | $l"' || echo "? | ? | ? | ? | ? | ?")"
      echo "| $n | $(role_of "$n") | $row |"
    done
  } > "$f"
}

scene_lan() {
  scene_header "Everyone on the same private LAN" "Task A · demo step 2"
  say "Every machine pings the other three – ICMP directly across the subnet, no router hop."
  local n; for n in $NODES; do label "$n" "ping the other three"; done
  all_run "cn-pingall"
  for n in $NODES; do check "$n reaches all 3 other machines" "$n" "! cn-pingall | grep -q FAILED"; done
  end_scene
}

scene_dns() {
  scene_header "Private DNS: app.$D resolves through the team DNS" "Task B · demo step 3"
  follow node-1 "cn-follow dns" "DNS SERVER – live query log"
  label node-2 "client: which DNS server?"; label node-3 "client: which DNS server?"; label node-4 "client: dig"
  start_in node-2 "cn-resolver show; getent hosts app.$D"
  start_in node-3 "cn-resolver show; getent hosts app.$D"
  wait_for node-2; wait_for node-3
  say "Every other machine is configured to use node-1 ($NODE1_IP) as its DNS server."
  run_in node-4 "cn-resolver show"
  run_in node-4 "dig app.$D"
  say "SERVER: $NODE1_IP#53 (UDP) · ANSWER: app.$D A $NODE2_IP · TTL $TTL – watch node-1's log."
  run_in node-4 "dig @8.8.8.8 app.$D | grep -E 'status|SERVER'"
  say "Google's public DNS says NXDOMAIN: the name exists only in our private DNS."
  run_in node-4 "nslookup api.$D"
  run_in node-4 "dig @$NODE1_IP nothere.$D | grep status"
  say "Unknown names in our zone → NXDOMAIN, answered locally, never forwarded to the internet."
  say "DNS only finds the IP. The TCP + TLS connection to that IP is a separate, later step."
  check "dig @node-1 app.$D = edge $NODE2_IP" node-4 "[ \"\$(dig +short @$NODE1_IP app.$D)\" = $NODE2_IP ]"
  local n; for n in node-2 node-3 node-4; do
    check "$n resolves app.$D via team DNS" "$n" "getent hosts app.$D | grep -q $NODE2_IP"
  done
  end_scene
}

scene_https() {
  scene_header "HTTPS by name, certificate verified (no -k)" "Task E · demo step 4"
  follow node-2 "cn-follow nginx" "EDGE – live nginx log"
  follow node-3 "cn-follow backend" "backend A – live log"
  label node-1 "client: trust store"; label node-4 "client: HTTPS"
  run_in node-1 "openssl x509 -in /usr/local/share/ca-certificates/cn-team-ca.crt -noout -subject -fingerprint -sha256"
  say "Our private CA is installed in every client's system trust store."
  run_in node-4 "curl -v \$URL/api/status" 30
  say "Handshake: ClientHello (SNI=app.$D, ALPN h2) → ServerHello → Certificate → key exchange → Finished."
  say "'SSL certificate verify ok' – signed by our CA and the name matches the SAN. No -k anywhere."
  run_in node-4 "echo | openssl s_client -connect app.$D:443 -servername app.$D 2>/dev/null | openssl x509 -noout -subject -issuer -ext subjectAltName -dates"
  run_in node-4 "curl -sI http://app.$D/ | head -3"
  say "Plain HTTP on :80 only redirects (301) to HTTPS."
  check "HTTPS from node-4 verifies without -k" node-4 "curl -sf -o /dev/null https://app.$D/api/status"
  check "HTTPS from node-1 verifies without -k" node-1 "curl -sf -o /dev/null https://app.$D/api/status"
  end_scene
}

scene_headers() {
  scene_header "HTTP request/response headers, HTTP/1.1 vs HTTP/2" "Task G (headers) · HTTP versions"
  follow node-2 "cn-follow nginx" "EDGE – live nginx log"
  label node-4 "client: headers"
  run_in node-4 "curl -sv --http1.1 -o /dev/null \$URL/api/status 2>&1 | grep -E '^[<>]'"
  run_in node-4 "curl -sv -o /dev/null \$URL/api/status 2>&1 | grep -E 'ALPN|^[<>]'"
  say "Same request: HTTP/1.1 text headers vs HTTP/2 (binary frames, negotiated by ALPN inside TLS)."
  say "Custom headers: X-Backend (who served it) and X-Edge (which edge). HTTP/3 = QUIC over UDP – explanation only."
  say "In Wireshark these headers are invisible: they travel inside TLS Application Data."
  check "HTTP/2 negotiated" node-4 "curl -s -o /dev/null -w '%{http_version}' https://app.$D/ | grep -q 2"
  end_scene
}

scene_lb() {
  scene_header "Load balancing across both backends" "Task D · demo step 5"
  follow node-2 "cn-follow nginx" "EDGE – which backend got it"
  follow node-3 "cn-follow backend" "backend A – live log"
  follow node-4 "cn-follow backend" "backend B – live log"
  label node-1 "client: 8 requests to the same name"
  sleep 1
  run_in node-1 "cn-probe 8 0.7" 30
  say "Same name, same IP, same port ($NODE2_IP:443) every time – nginx alternates A, B, A, B (round-robin)."
  say "The client never learns the backend IPs; only nginx knows them (upstream block). least_conn is the alternative."
  check "both backends answered through the edge" node-1 "o=\$(for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w '%header{x-backend}' https://app.$D/api/status; done); echo \$o | grep -q A && echo \$o | grep -q B"
  end_scene
}

scene_cache() {
  scene_header "HTTP caching: Cache-Control, ETag, 304 Not Modified" "Task F · demo step 7"
  follow node-2 "cn-follow nginx" "EDGE – watch 200 vs 304"
  follow node-3 "cn-follow backend" "backend A – live log"
  follow node-4 "cn-follow backend" "backend B – live log"
  label node-1 "client: caching"
  sleep 1
  run_in node-1 "curl -si \$URL/api/cached"
  say "Full response: 200 + body, Cache-Control: public, max-age=60, ETag."
  run_in node-1 'E=$(curl -sI $URL/api/cached | awk '"'"'tolower($1)=="etag:"{print $2}'"'"' | tr -d "\r"); echo "ETag = $E"'
  run_in node-1 'curl -si -H "If-None-Match: $E" $URL/api/cached'
  run_in node-1 'curl -sI -H "If-None-Match: $E" $URL/api/cached | grep -iE "^(HTTP|x-backend|etag)"'
  say "Conditional request: 'still ETag X?' → 304 Not Modified, NO body – from A or B (same ETag on both)."
  run_in node-1 "curl -sI \$URL/api/status | grep -i cache-control"
  say "Fresh hit: within max-age a browser sends NOTHING (DevTools: 'from disk cache')."
  say "Conditional: after max-age it revalidates → 304.  Full: no copy / changed → 200 + body.  CDNs do the same at the edge."
  check "conditional request returns 304" node-1 "e=\$(curl -sI https://app.$D/api/cached | awk 'tolower(\$1)==\"etag:\"{print \$2}' | tr -d '\r'); curl -s -o /dev/null -w '%{http_code}' -H \"If-None-Match: \$e\" https://app.$D/api/cached | grep -q 304"
  end_scene
}

scene_capture() {
  scene_header "Packet evidence: DNS → TCP → TLS → HTTP" "Task G · demo step 6"
  follow node-1 "cn-wire dns" "DNS SERVER – packets on :53"
  follow node-2 "cn-wire edge" "EDGE – edge→backend packets (plain HTTP)"
  follow node-3 "cn-follow backend" "backend A – live log"
  label node-4 "client: capture one request"
  sleep 2
  on_q node-2 "sudo rm -f /tmp/cn-edge.pcap; sudo timeout 25 tcpdump -i \$(cn-iface) -U -w /tmp/cn-edge.pcap 'tcp port 3001 or tcp port 3002'" &
  local bg=$!
  sleep 1
  run_in node-4 "sudo cn-capture" 60
  say "1 DNS: ephemeral UDP port → $NODE1_IP:53, answer $NODE2_IP.   2 TCP: SYN → SYN-ACK → ACK to :443 (seq/ack)."
  say "3 TLS 1.2: ClientHello, ServerHello, Certificate (readable!), ChangeCipherSpec, Finished. TLS 1.3 encrypts the certificate."
  say "4 Everything after the handshake is 'Application Data' – encrypted. node-2 shows the SAME request in plain HTTP to the backend."
  wait "$bg" 2>/dev/null || true
  mkdir -p "$EVID/pcap"
  scp -q -F "$SSH_CFG" node-4:/tmp/cn-client.pcap "$EVID/pcap/client-dns-tcp-tls.pcap" || true
  scp -q -F "$SSH_CFG" node-4:/tmp/cn-keys.log    "$EVID/pcap/tls-keys.log" || true
  on_q node-2 "sudo cat /tmp/cn-edge.pcap" > "$EVID/pcap/edge-to-backend.pcap" || true
  say "Saved evidence/pcap/*.pcap – Wireshark: Preferences → Protocols → TLS → key log = evidence/pcap/tls-keys.log"
  check "capture has the DNS answer $NODE2_IP" node-4 "sudo tshark -n -r /tmp/cn-client.pcap -Y 'dns.a==$NODE2_IP' 2>/dev/null | grep -q ."
  check "capture has the TCP handshake to :443" node-4 "sudo tshark -n -r /tmp/cn-client.pcap -Y 'tcp.flags.syn==1 && tcp.flags.ack==1 && tcp.srcport==443' 2>/dev/null | grep -q ."
  check "capture has Certificate + ChangeCipherSpec" node-4 "sudo tshark -n -r /tmp/cn-client.pcap -Y 'tls.handshake.type==11' 2>/dev/null | grep -q . && sudo tshark -n -r /tmp/cn-client.pcap -Y 'tls.record.content_type==20' 2>/dev/null | grep -q ."
  end_scene
}

scene_fail_dns_server() {
  scene_header "Failure: client uses the wrong DNS server" "Phase 1 failure demo 1"
  follow node-1 "cn-follow dns" "DNS SERVER – node-4's queries stop arriving"
  follow node-2 "cn-follow nginx" "EDGE – live nginx log"
  label node-4 "client: WRONG DNS server"
  run_in node-4 "sudo cn-resolver set 169.254.169.253"
  say "node-4 now asks the AWS resolver – a real DNS server that simply doesn't know our private zone."
  run_in node-4 "dig app.$D | grep -E 'status|SERVER'"
  run_in node-4 "curl -sS --max-time 5 \$URL/api/status"
  run_in node-4 "ping -c 2 -q $NODE2_IP | tail -2"
  run_in node-4 "curl -s --resolve app.$D:443:$NODE2_IP -o /dev/null -w 'by IP: HTTP %{http_code}\n' \$URL/api/status"
  say "Name lookup fails, but the IP path is perfectly fine: DNS and IP connectivity are independent layers."
  check "with the wrong resolver the name does not resolve" node-4 "! getent hosts app.$D"
  hold "restore the resolver"
  run_in node-4 "sudo cn-resolver reset && dig +short app.$D"
  check "resolver restored" node-4 "getent hosts app.$D | grep -q $NODE2_IP"
  end_scene
}

set_record() {   # set_record <ip>: change app/api on the DNS server(s) – typed where visible
  run_in node-1 "sudo cn-dns set $1"
  if [ "$PHASE" = 2 ]; then on_q node-3 "sudo cn-dns set $1" >/dev/null; say "(backup DNS on node-3 updated too)"; fi
}

scene_fail_dns_record() {
  scene_header "Failure: DNS record points to the wrong IP" "Phase 1 failure demo 2"
  label node-1 "DNS SERVER – edit the record"
  follow node-2 "cn-follow nginx" "EDGE – no request arrives"
  label node-4 "client"
  set_record "$NODE1_IP"
  run_in node-4 "sudo resolvectl flush-caches; dig +short app.$D"
  run_in node-4 "curl -sS --max-time 5 \$URL/api/status"
  say "Resolution SUCCEEDS – but sends the client to $NODE1_IP, where nothing listens on 443 → connection refused."
  say "DNS is a directory, not a connection. It happily gives a wrong answer."
  check "record now points to the wrong IP" node-4 "[ \"\$(dig +short app.$D)\" = $NODE1_IP ]"
  hold "fix the record"
  set_record "$NODE2_IP"
  run_in node-4 "sudo resolvectl flush-caches; dig +short app.$D"
  check "record fixed" node-4 "[ \"\$(dig +short app.$D)\" = $NODE2_IP ]"
  end_scene
}

scene_fail_one_backend() {
  scene_header "Failure: one backend stops – the service continues" "Phase 1 failure demo 3 · demo step 8"
  follow node-2 "cn-follow nginx" "EDGE – upstream errors + retries"
  follow node-4 "cn-follow backend" "backend B – takes all traffic"
  label node-3 "backend A – about to stop"; label node-1 "client: continuous requests"
  sleep 1
  start_in node-1 "cn-probe 24 0.5"
  sleep 3
  run_in node-3 "sudo systemctl stop backend-a; systemctl is-active backend-a"
  wait_for node-1 40
  say "nginx got 'connection refused' from A, retried the request on B (proxy_next_upstream) and marked A down for 10 s."
  say "The client never saw an error."
  check "Backend A down: every request 200 from B" node-4 "[ \"\$(for i in 1 2 3 4; do curl -s -o /dev/null -w '%{http_code}%header{x-backend} ' https://app.$D/api/status; done)\" = '200B 200B 200B 200B ' ]"
  check_pane "no failed request during the outage" node-1 '(000|5[0-9][0-9])  -> ' absent
  hold "restart Backend A"
  run_in node-3 "sudo systemctl start backend-a; systemctl is-active backend-a"
  say "After fail_timeout (10 s) nginx tries A again and round-robin resumes."
  sleep 8
  run_in node-1 "cn-probe 6 1" 20
  end_scene
}

scene_fail_both_backends() {
  scene_header "Failure: both backends stopped → 502" "Phase 1 failure demo 4"
  follow node-2 "cn-follow nginx" "EDGE – no upstream left"
  label node-1 "client"; label node-3 "backend A"; label node-4 "backend B"
  start_in node-3 "sudo systemctl stop backend-a; systemctl is-active backend-a"
  start_in node-4 "sudo systemctl stop backend-b; systemctl is-active backend-b"
  wait_for node-3; wait_for node-4
  run_in node-1 "dig +short app.$D"
  run_in node-1 "curl -sv \$URL/api/status 2>&1 | grep -E 'Connected to|SSL connection|verify ok|^< HTTP|^< x-edge|^< server'"
  run_in node-1 "curl -s \$URL/api/status | head -4"
  say "DNS works, TCP works, TLS works (nginx answers), but there is nobody behind it → 502 Bad Gateway."
  say "This shows where the edge ends and the backend begins. No X-Backend header: no backend answered."
  check "edge returns 502" node-1 "[ \"\$(curl -s -o /dev/null -w '%{http_code}' https://app.$D/api/status)\" = 502 ]"
  hold "start both backends"
  start_in node-3 "sudo systemctl start backend-a; systemctl is-active backend-a"
  start_in node-4 "sudo systemctl start backend-b; systemctl is-active backend-b"
  wait_for node-3; wait_for node-4
  sleep 2
  run_in node-1 "cn-probe 4 0.5" 20
  end_scene
}

scene_fail_wrong_port() {
  scene_header "Failure: host reachable, wrong port" "Phase 1 failure demo 5"
  label node-2 "EDGE – only 80/443 listen"
  run_in node-2 "sudo ss -lntp | grep -E ':(80|443) '"
  follow node-2 "sudo tshark -n -l -i \$(cn-iface) -f 'tcp port 443 or tcp port 8443' 2>/dev/null" "EDGE – SYN and RST packets"
  label node-1 "client"
  sleep 2
  run_in node-1 "ping -c 1 -q app.$D | tail -1"
  run_in node-1 "nc -zv -w 3 app.$D 443"
  run_in node-1 "nc -zv -w 3 app.$D 8443"
  run_in node-1 "curl -sS --max-time 5 https://app.$D:8443/"
  say "Same IP, reachable. Port 443 accepts; port 8443 has no listener → the kernel answers SYN with RST (see node-2)."
  say "IP address = which machine. Port = which service on that machine."
  check "443 open, 8443 refused" node-1 "nc -z -w 3 app.$D 443 && ! nc -z -w 3 app.$D 8443"
  end_scene
}

need_phase2() {
  [ "$PHASE" = 2 ] || die "Phase 2 scenes need PHASE=2 (set it in settings.env, or use make live-p2)"
}

scene_ext_a() {
  need_phase2
  scene_header "Backup DNS: the primary fails, clients keep resolving" "Extension A · demo step 9"
  follow node-3 "cn-follow dns" "BACKUP DNS – live query log"
  label node-1 "PRIMARY DNS – about to stop"; label node-2 "direct queries"; label node-4 "client"
  run_in node-4 "cn-resolver show; resolvectl status | grep -i 'current dns'"
  say "Clients list two DNS servers: node-1 (primary) then node-3 (backup)."
  run_in node-1 "sudo systemctl stop dnsmasq; systemctl is-active dnsmasq"
  run_in node-2 "dig +time=2 +tries=1 @$NODE1_IP app.$D | grep -E 'status|refused|timed out'; dig +short @$NODE3_IP app.$D"
  run_in node-4 "sudo resolvectl flush-caches; dig app.$D +noall +answer"
  run_in node-4 "resolvectl status | grep -i 'current dns'"
  run_in node-4 "cn-probe 3 0.5" 20
  say "The query went to node-3 (see its log); the service keeps working."
  say "DNS failure = names stop resolving (servers fine).  App failure = names resolve, but 502/refused."
  check "name resolves with the primary DNS down" node-4 "getent hosts app.$D | grep -q $NODE2_IP"
  hold "restart the primary DNS"
  run_in node-1 "sudo systemctl start dnsmasq; systemctl is-active dnsmasq"
  say "systemd-resolved stays on the backup until IT fails – it does not switch back on its own."
  end_scene
}

scene_ext_b() {
  need_phase2
  scene_header "TTL: cached answers survive a record change until they expire" "Extension B · demo step 9"
  label node-1 "PRIMARY DNS"; label node-3 "BACKUP DNS"; label node-2 "asks the server directly"
  label node-4 "client: cached answer + remaining TTL"
  start_in node-1 "cn-dns show"; start_in node-3 "cn-dns show"; wait_for node-1; wait_for node-3
  run_in node-4 "sudo resolvectl flush-caches; dig app.$D +noall +answer"
  start_in node-4 "cn-ttlwatch $((TTL + 15)) 3"
  sleep 5
  say "Now change the record on BOTH DNS servers: app.$D → $NODE3_IP"
  start_in node-1 "sudo cn-dns set $NODE3_IP"; start_in node-3 "sudo cn-dns set $NODE3_IP"
  wait_for node-1; wait_for node-3
  run_in node-2 "dig +short @$NODE1_IP app.$D"
  say "The server answers the NEW address immediately – but node-4 keeps its cached answer until the TTL reaches 0."
  wait_for node-4 $((TTL + 30))
  check "after the TTL expired the client got the new address" node-4 "[ \"\$(dig +short app.$D)\" = $NODE3_IP ]"
  say "Change it back and flush the cache manually:"
  start_in node-1 "sudo cn-dns set $NODE2_IP"; start_in node-3 "sudo cn-dns set $NODE2_IP"
  wait_for node-1; wait_for node-3
  run_in node-4 "dig +short app.$D"
  say "Still the old answer – it is cached until the TTL expires."
  run_in node-4 "sudo resolvectl flush-caches; dig +short app.$D"
  say "Production migrations lower the TTL days in advance so the cutover spreads within seconds, not hours."
  check "after flushing the client sees the edge again" node-4 "[ \"\$(dig +short app.$D)\" = $NODE2_IP ]"
  end_scene
}

scene_ext_c() {
  need_phase2
  scene_header "Service isolation: backends reachable only from the edge" "Extension C"
  label node-1 "client: direct to backends?"; label node-2 "EDGE: direct to backends?"
  label node-3 "backend A firewall"; label node-4 "backend B firewall"
  run_in node-1 "nc -zv -w 2 $NODE3_IP 3001; nc -zv -w 2 $NODE4_IP 3002"
  say "Before: anyone on the LAN can bypass the edge and talk to the backends directly."
  start_in node-3 "sudo cn-fw on"; start_in node-4 "sudo cn-fw on"; wait_for node-3; wait_for node-4
  run_in node-1 "nc -zv -w 2 $NODE3_IP 3001; nc -zv -w 2 $NODE4_IP 3002"
  run_in node-2 "nc -zv -w 2 $NODE3_IP 3001; nc -zv -w 2 $NODE4_IP 3002"
  run_in node-1 "cn-probe 4 0.5" 20
  say "Client refused, edge allowed – and the service still works through the edge."
  say "Same idea as macOS pf. Cloud equivalent: a backend security group that only allows the edge's group."
  check "client cannot reach backend A directly" node-1 "! nc -z -w 2 $NODE3_IP 3001"
  check "edge can still reach both backends" node-2 "nc -z -w 2 $NODE3_IP 3001 && nc -z -w 2 $NODE4_IP 3002"
  hold "roll back the firewall from the saved copy"
  start_in node-3 "sudo cn-fw off"; start_in node-4 "sudo cn-fw off"; wait_for node-3; wait_for node-4
  run_in node-1 "nc -zv -w 2 $NODE3_IP 3001"
  check "original rules restored" node-1 "nc -z -w 2 $NODE3_IP 3001"
  end_scene
}

scene_ext_d() {
  need_phase2
  scene_header "High availability: nginx routes around a dead backend" "Extension D"
  label node-2 "EDGE – health-check config"
  run_in node-2 "grep -A5 'upstream backends' /etc/nginx/conf.d/cn-edge.conf"
  say "Passive health check: max_fails=1 fail_timeout=10s + proxy_next_upstream."
  follow node-2 "cn-follow nginx" "EDGE – errors, retries, recovery"
  follow node-4 "cn-follow backend" "backend B – live log"
  label node-3 "backend A – stop / start"; label node-1 "client: 40 requests, 2 per second"
  sleep 1
  start_in node-1 "cn-probe 40 0.5"
  sleep 4
  run_in node-3 "sudo systemctl stop backend-a; systemctl is-active backend-a"
  sleep 6
  run_in node-3 "sudo systemctl start backend-a; systemctl is-active backend-a"
  wait_for node-1 60
  check_pane "zero failed requests while A was down" node-1 '(000|5[0-9][0-9])  -> ' absent
  check_pane "A served requests again after it came back" node-1 'backend=A'
  say "Remaining single point of failure: the edge itself (node-2)."
  say "Fix: two edges behind a floating IP / cloud load balancer, or health-checked DNS failover (next: Extension E)."
  end_scene
}

scene_ext_e() {
  need_phase2
  scene_header "Edge migration by DNS cutover (TTL effects)" "Extension E · demo step 9"
  label node-3 "STANDBY EDGE"
  run_in node-3 "systemctl is-active nginx && curl -s --resolve app.$D:443:$NODE3_IP -o /dev/null -w 'standby edge: HTTP %{http_code}  X-Edge %header{x-edge}\n' \$URL/api/status"
  follow node-3 "cn-follow nginx" "STANDBY EDGE – live log"
  follow node-2 "cn-follow nginx" "OLD EDGE – live log"
  label node-4 "client A: cached answer"; label node-1 "PRIMARY DNS + client B: fresh lookup"
  run_in node-4 "sudo resolvectl flush-caches; dig +short app.$D"
  start_in node-4 "cn-probe $((TTL + 12)) 1"
  sleep 4
  say "CUTOVER: app.$D → standby edge $NODE3_IP"
  set_record "$NODE3_IP"
  run_in node-1 "sudo resolvectl flush-caches; cn-probe 3 0.5" 20
  say "A fresh lookup goes to the standby at once. node-4 keeps hitting the OLD edge until its TTL runs out."
  wait_for node-4 $((TTL + 40))
  check_pane "node-4 used the old edge first" node-4 'edge=node-2'
  check_pane "node-4 moved to the standby edge after the TTL" node-4 'edge=node-3'
  hold "cut back to node-2"
  set_record "$NODE2_IP"
  on_q node-4 "sudo resolvectl flush-caches"; on_q node-1 "sudo resolvectl flush-caches"
  run_in node-4 "cn-probe 2 0.5" 20
  end_scene
}

scene_ext_f() {
  scene_header "Troubleshooting: an injected fault, diagnosed layer by layer" "Extension F · demo step 10"
  local n a fault=""
  for n in $NODES; do label "$n" "waiting for the fault"; done
  if [ "$AUTO" = 1 ]; then a=p
  else
    say "Faculty: inject one fault now (any machine).  Or press [p] to inject a random practice fault."
    printf '  %s[Enter] fault is in place   [p] practice fault%s ' "$B" "$RST"; read -r a </dev/tty || true
  fi
  if [ "$a" = p ] || [ "$a" = P ]; then fault="$("$ROOT/scripts/fault.sh" inject --quiet)"; say "practice fault injected (hidden – revealed at the end)"; fi
  while true; do
    say "Method: 1 DNS → 2 IP → 3 TCP → 4 TLS → 5 HTTP → edge → backend. Stop at the first FAIL."
    label node-4 "CLIENT view: layer by layer"; label node-1 "DNS server check"
    label node-2 "EDGE check"; label node-3 "BACKEND check"
    start_in node-4 "cn-diagnose"; start_in node-1 "cn-diagnose dns"
    start_in node-2 "cn-diagnose edge"; start_in node-3 "cn-diagnose backend"
    for n in $NODES; do wait_for "$n" 60; done
    [ "$AUTO" = 1 ] && break
    printf '  %s[Enter] re-check   [s] solved/next   [r] restore everything (make restore)%s ' "$B" "$RST"
    read -r a </dev/tty || true
    case "$a" in s|S) break ;; r|R) "$ROOT/scripts/converge.sh" restore | tail -2 ;; esac
    clear_all
  done
  [ -n "$fault" ] && say "the practice fault was: $fault"
  say "restoring the baseline"; "$ROOT/scripts/converge.sh" restore >/dev/null 2>&1 || true
  check "system healthy again" node-4 "cn-diagnose | grep -q 'all checks pass'"
  end_scene
}

scene_viva() {
  scene_header "Individual viva" "demo step 11"
  say "Every member answers from understanding. Revise the team viva notes – one question per layer."
  say "Evidence for any question: evidence/live/, evidence/pcap/, evidence/inventory.md, evidence/terminal-logs/."
  end_scene
}

# ============================== sequences ============================================

seq_p1()    { echo topology lan dns https headers lb cache capture fail_dns_server fail_dns_record fail_one_backend fail_both_backends fail_wrong_port; }
seq_p2()    { echo ext_a ext_b ext_c ext_d ext_e ext_f; }
seq_final() { echo topology lan dns https lb capture cache fail_one_backend ext_a ext_b ext_e ext_f viva; }

on_interrupt() {
  trap - INT TERM
  printf '\n%sinterrupted – stopping live views and restoring the baseline…%s\n' "$YEL" "$RST"
  local n; for n in $NODES; do tmux send-keys -t "$(pane "$n")" C-c 2>/dev/null || true; done
  "$ROOT/scripts/converge.sh" restore | tail -2 || true
  exit 130
}

cmd_run() {   # run <p1|p2|final|scene-name>
  local what="${1:-final}" list
  case "$what" in
    p1) list="$(seq_p1)"; PHASE="${PHASE_OVERRIDE:-1}" ;;
    p2) list="$(seq_p2)"; PHASE="${PHASE_OVERRIDE:-2}" ;;
    final) list="$(seq_final)"; PHASE="${PHASE_OVERRIDE:-2}" ;;
    *) declare -F "scene_$what" >/dev/null || die "unknown scene '$what' – scenes: $(seq_p1) $(seq_p2) viva"; list="$what" ;;
  esac
  [ -n "${ONLY:-}" ] && list="$ONLY"
  if ! in_session; then   # start the dashboard and run this inside its control terminal
    "$ROOT/scripts/tmux.sh" --no-attach >/dev/null
    tmux send-keys -t "$(tmux show-options -t "$S" -v @pc)" -l -- \
      "PHASE_OVERRIDE=$PHASE AUTO=$AUTO FROM=${FROM:-1} ONLY=${ONLY:-} PACE=$PACE ./scripts/live.sh run $what"
    tmux send-keys -t "$(tmux show-options -t "$S" -v @pc)" Enter
    tmux select-window -t "$S:live"
    if [ -n "${TMUX:-}" ]; then exec tmux switch-client -t "$S"; else exec tmux attach -t "$S"; fi
  fi
  export PHASE_OVERRIDE="$PHASE"
  mkdir -p "$RUN_DIR"; LOG="$RUN_DIR/control.log"; : > "$LOG"
  [ -f "$RESULTS" ] || printf 'time\tscene\tcheck\tresult\n' > "$RESULTS"
  trap on_interrupt INT TERM

  # shellcheck disable=SC2086
  set -- $list; SCENE_TOTAL=$#
  printf '%sLive demo: %s  (%s scenes, PHASE=%s%s)%s\n' "$B" "$what" "$SCENE_TOTAL" "$PHASE" "$([ "$AUTO" = 1 ] && echo ', AUTO')" "$RST"
  local k=0 x; for x in $list; do k=$((k + 1)); printf '  %2d %-20s' "$k" "$x"; [ $((k % 4)) = 0 ] && echo; done; echo

  section "Preparing: known-good state (idempotent converge)"
  "$ROOT/scripts/converge.sh" all | grep -E 'changed|failed|All services|ERROR' || true
  section "Connecting to the four terminals"
  local n
  for n in $NODES; do
    tmux send-keys -t "$(pane "$n")" C-c
    tmux send-keys -t "$(pane "$n")" -l -- ". /etc/cn/shell.sh"; tmux send-keys -t "$(pane "$n")" Enter
  done
  sleep 1
  for n in $NODES; do
    type_in "$n" "true"
    if wait_id "$n" "$LAST_ID" 25 >/dev/null; then report ok "$n" "terminal ready"
    else die "$n's terminal does not respond – click it, press Enter to reconnect, then run again"; fi
  done

  FAILS=0; SCENE_NO=$(( ${FROM:-1} - 1 )); FOLLOWING=""
  local i=0 s
  for s in $list; do
    i=$((i + 1)); [ "$i" -lt "${FROM:-1}" ] && continue
    SCENE_NAME="$s"
    while true; do
      REPEAT=0; clear_all; reset_labels
      "scene_$s"
      [ "$REPEAT" = 1 ] && SCENE_NO=$((SCENE_NO - 1)) || break
    done
  done
  reset_labels
  printf '\n%s━━ Done: %s scenes, %s failed checks%s   evidence: %s\n' "$B" "$SCENE_TOTAL" "$FAILS" "$RST" "${RUN_DIR#"$ROOT"/}"
  "$ROOT/scripts/report.sh" >/dev/null 2>&1 || true
}

dispatch "$@"
