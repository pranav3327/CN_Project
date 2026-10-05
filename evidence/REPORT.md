# Evidence report – team1  (2026-10-05 15:57:59)

## Automatic checks (latest result of each)

| Scene | Check | Result | When |
|---|---|---|---|
| topology | node-1 has its fixed LAN address 172.31.250.11 | ✅ PASS | 2026-10-05 15:38:32 |
| topology | node-2 has its fixed LAN address 172.31.250.12 | ✅ PASS | 2026-10-05 15:38:33 |
| topology | node-3 has its fixed LAN address 172.31.250.13 | ✅ PASS | 2026-10-05 15:38:33 |
| topology | node-4 has its fixed LAN address 172.31.250.14 | ✅ PASS | 2026-10-05 15:38:34 |
| lan | node-1 reaches all 3 other machines | ✅ PASS | 2026-10-05 15:39:53 |
| lan | node-2 reaches all 3 other machines | ✅ PASS | 2026-10-05 15:40:03 |
| lan | node-3 reaches all 3 other machines | ✅ PASS | 2026-10-05 15:40:13 |
| lan | node-4 reaches all 3 other machines | ✅ PASS | 2026-10-05 15:40:22 |
| dns | dig @node-1 app.team1.test = edge 172.31.250.12 | ✅ PASS | 2026-10-05 15:40:33 |
| dns | node-2 resolves app.team1.test via team DNS | ✅ PASS | 2026-10-05 15:40:34 |
| dns | node-3 resolves app.team1.test via team DNS | ✅ PASS | 2026-10-05 15:40:34 |
| dns | node-4 resolves app.team1.test via team DNS | ✅ PASS | 2026-10-05 15:40:35 |
| https | HTTPS from node-4 verifies without -k | ✅ PASS | 2026-10-05 15:40:45 |
| https | HTTPS from node-1 verifies without -k | ✅ PASS | 2026-10-05 15:40:46 |
| headers | HTTP/2 negotiated | ✅ PASS | 2026-10-05 15:41:14 |
| lb | both backends answered through the edge | ✅ PASS | 2026-10-05 15:42:03 |
| cache | conditional request returns 304 | ✅ PASS | 2026-10-05 15:42:53 |
| capture | capture has the DNS answer 172.31.250.12 | ✅ PASS | 2026-10-05 15:44:19 |
| capture | capture has the TCP handshake to :443 | ✅ PASS | 2026-10-05 15:44:20 |
| capture | capture has Certificate + ChangeCipherSpec | ✅ PASS | 2026-10-05 15:44:21 |
| fail_dns_server | with the wrong resolver the name does not resolve | ✅ PASS | 2026-10-05 15:45:02 |
| fail_dns_server | resolver restored | ✅ PASS | 2026-10-05 15:51:12 |
| fail_dns_record | record now points to the wrong IP | ✅ PASS | 2026-10-05 15:51:23 |
| fail_dns_record | record fixed | ✅ PASS | 2026-10-05 15:53:47 |
| fail_one_backend | Backend A down: every request 200 from B | ✅ PASS | 2026-10-05 15:54:04 |
| fail_one_backend | no failed request during the outage | ✅ PASS | 2026-10-05 15:54:04 |
| fail_both_backends | edge returns 502 | ✅ PASS | 2026-10-05 15:55:35 |
| fail_wrong_port | 443 open, 8443 refused | ✅ PASS | 2026-10-05 15:57:37 |

Totals over all runs: 32 passed, 0 failed.

## Evidence files

- IP / MAC / gateway inventory: `evidence/inventory.md`
- Packet capture: `evidence/pcap/client-dns-tcp-tls.pcap`
- Packet capture: `evidence/pcap/edge-to-backend.pcap`
- Live run `evidence/live/20261005-002931/`: 2 scenes (each: one file per terminal + control)
- Live run `evidence/live/20261005-153750/`: 14 scenes (each: one file per terminal + control)
- Raw timestamped terminal recordings: `evidence/terminal-logs/`
