# Requirements coverage – every item of the brief

Scene names refer to `make scene SCENE=<name>`; all scenes are part of `make live-p1`, `make live-p2` or `make live`.

## Phase 1

| Brief item | Where it is implemented | Shown by / evidence |
|---|---|---|
| A · machines on one LAN | Terraform VPC + subnet 10.0.1.0/24, fixed IPs | scene `topology` |
| A · record IP, prefix/mask, gateway, interface, MAC | `cn-info` | `topology` → `evidence/inventory.md` |
| A · ping every pair | `cn-pingall` | scene `lan` (4 × 3 pings) |
| A · topology diagram | docs/architecture.md (mermaid) + printed in `topology` | |
| B · dnsmasq on Mac 1 with app/api → Mac 2 | config/dnsmasq.conf on node-1 | scene `dns` |
| B · ≥ 2 other machines use it | systemd-resolved drop-in on all nodes | `dns` (node-2, node-3, node-4 resolve) |
| B · verify with dig / nslookup | | `dns` |
| B · explain DNS vs TCP | presenter notes | `dns` |
| C · two backends, GET / and GET /api/status JSON | config/backend.py, systemd units | `https`, `lb` |
| C · backend identifier + X-Backend header | backend.py | `lb`, `headers` |
| C · bind to the LAN interface, ports 3001/3002 | 0.0.0.0:3001 / :3002 | `topology` (listening ports) |
| D · single entry point, round-robin | nginx upstream on node-2 | scene `lb` |
| D · verify alternation, explain | | `lb` (A,B,A,B + nginx log) |
| E · self-signed / local CA certificate | scripts/remote/pki.sh (private CA + SAN cert) | `https` |
| E · nginx TLS on 443 | config/nginx-edge.conf | `https` |
| E · CA trusted by every client, no -k | update-ca-certificates on all nodes | `https` (curl -v, s_client) |
| E · explain handshake | presenter notes | `https`, `capture` |
| F · Cache-Control, ETag, curl -I, 304 | /api/cached | scene `cache` |
| F · explain fresh / conditional / full | | `cache` |
| G · DNS query/response | cn-capture | scene `capture` → `evidence/pcap/*.pcap` |
| G · TCP three-way handshake + ports | cn-capture section 2 | `capture` |
| G · ClientHello, ServerHello, Certificate, ChangeCipherSpec, encrypted data | cn-capture section 3–4 (TLS 1.2 + 1.3) | `capture` |
| G · HTTP headers (curl -v) | | `https`, `headers` |
| G · load balancing visible | edge→backend capture, nginx log | `capture`, `lb` |
| G · port identification (ephemeral, 53/udp, 443/tcp) | | `capture` |
| Topic · HTTP/1.1 vs HTTP/2 | ALPN | `headers` |
| Topic · HTTP/3 (explanation only) | presenter notes | `headers` |
| Topic · email protocols (explanation only) | team viva notes | |
| Topic · OSI mapping, cloud equivalents | docs/architecture.md | `topology` notes |
| Failure 1 · wrong DNS server | `cn-resolver set` | `fail_dns_server` |
| Failure 2 · wrong DNS record | `cn-dns set` | `fail_dns_record` |
| Failure 3 · one backend stopped | systemctl stop backend-a | `fail_one_backend` |
| Failure 4 · both stopped → 502 | | `fail_both_backends` |
| Failure 5 · wrong destination port | nc/curl to 8443, SYN→RST capture | `fail_wrong_port` |

## Phase 2

| Brief item | Implementation | Scene |
|---|---|---|
| A · backup DNS on another machine, clients list both | dnsmasq on node-3, resolvers list both (PHASE=2) | `ext_a` |
| A · stop primary, clients continue; explain DNS vs app failure | | `ext_a` |
| B · TTL 30 | `TTL=30` in settings.env | `ext_b` |
| B · record change, cached until expiry, manual flush | `cn-dns set`, `cn-ttlwatch`, `resolvectl flush-caches` | `ext_b` |
| C · only Mac 2 reaches 3001/3002 | `cn-fw on` (iptables) | `ext_c` |
| C · rollback copy + restore original | `/root/cn-fw.rollback`, `cn-fw off` | `ext_c` |
| D · nginx detects unavailability, stop/restart A | max_fails / fail_timeout / proxy_next_upstream | `ext_d` |
| D · identify single point of failure | presenter notes, architecture.md | `ext_d` |
| E · standby nginx with identical config on Mac 3/4 | node-3 nginx, same file + certificate | `ext_e` |
| E · DNS cutover, TTL effects on cached vs fresh clients | | `ext_e` |
| F · faculty-injected fault, layer-by-layer diagnosis | `cn-diagnose` on all 4 machines; practice: `make fault` | `ext_f` |

## Final demo (brief Section 8) – `make live`

| Step | Scene |
|---|---|
| 1 topology + IP inventory | `topology` |
| 2 LAN connectivity | `lan` |
| 3 DNS resolution | `dns` |
| 4 HTTPS by name, trusted cert | `https` |
| 5 load balancing | `lb` |
| 6 packet evidence | `capture` |
| 7 caching | `cache` |
| 8 backend failure | `fail_one_backend` |
| 9 Phase 2 extensions | `ext_a`, `ext_b`, `ext_e` (run `make live-p2` for all six) |
| 10 injected fault | `ext_f` |
| 11 viva | `viva` |

## Deliverables

| Deliverable | Where |
|---|---|
| Architecture document | docs/architecture.md |
| Configuration bundle | config/, infra/, node-bin/ |
| Backend source | config/backend.py |
| Evidence folder | evidence/ (inventory, pcap, live scene captures, terminal logs, REPORT.md) |
| Phase 2 final report | docs/phase2-report.md (template) + `make report` |
| Presentation | build from docs/architecture.md diagrams + evidence |

## Phase 1 submission form → `make form`

| Form item | Command run (machine) | Marks |
|---|---|---|
| A1 IPs and roles | `ip -4 -brief address` on all 4 + `aws ec2 describe-instances` (+ console screenshot) | Identity & LAN /5 |
| A2 dnsmasq config | config lines incl. `address=`, `listen-address=`, `interface=` (node-1) | DNS Config /5 |
| A3 dig from a client | `dig app.team1.test` (node-4) → SERVER 10.0.1.11, answer 10.0.1.12 | DNS Proof /5 |
| A4 public DNS | `dig @8.8.8.8 app.team1.test` → NXDOMAIN | DNS Proof |
| A5 ping all pairs | `cn-pingall` on all 4 (4 packets each, 12 directed pairs) | Identity & LAN |
| B1 HTTPS | `curl -v https://app.team1.test` (node-4, no -k) | HTTPS /5 |
| B2 load balancing | 6 × `curl -s …/api/status` + X-Backend headers | Load Balancing /5 |
| B3 nginx config | `/etc/nginx/conf.d/cn-edge.conf` (node-2) | Load Balancing |
| C1–C3 Wireshark | `cn-capture` + pcap + drafts with real values | Wireshark /8 |
| D1 caching headers | `curl -sI …/api/status` → `Cache-Control: public, max-age=60`, ETag, Date, X-Backend | Caching /4 |
| D2 explanation | draft text | Caching |
| D3 failure | Option A: before → stop backend-a → after → error log → restore → after | Failure Demo /5 |
