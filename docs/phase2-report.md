# Phase 2 Final Report – <Team name>

Members: … · Date: … · Domain: team1.test

> Run `make live-p2` (or `make live`) first; then `make report` produces
> `evidence/REPORT.md` with every automatic check and the evidence file list.

## 1. What changed from Phase 1

- **Machines:** the four Macs are replaced by four EC2 instances on one private subnet 10.0.1.0/24 (fixed IPs .11–.14). Roles are unchanged.
- **Ext A:** backup dnsmasq on node-3. Clients list 10.0.1.11 then 10.0.1.13.
- **Ext B:** record TTL is 30 s (`local-ttl=30`).
- **Ext C:** iptables isolation on node-3/node-4 (`cn-fw`), with a rollback copy.
- **Ext D:** nginx passive health checks (`max_fails=1 fail_timeout=10s`, `proxy_next_upstream`).
- **Ext E:** standby nginx on node-3 with identical configuration and certificate.

## 2. Extensions: test and result

For each: what we did · command/evidence · expected · observed · explanation.

### A – Backup DNS
- Evidence: `evidence/live/<run>/NN-ext_a/`
- Observed: …
- Explanation: …

### B – TTL and caching
- Observed: the client kept the old answer for … s (TTL countdown in node-4.txt); after flushing …

### C – Service isolation
- Observed: node-1 refused, node-2 allowed, service still worked through the edge; rollback restored.

### D – High availability
- Observed: … requests, 0 failed while Backend A was down; A resumed after …
- Single point of failure: node-2 (edge) – proposed mitigation: …

### E – Edge migration
- Observed: fresh client switched immediately; cached client switched after ≈ TTL (… s).

### F – Fault diagnosis
- Fault injected by faculty: …
- Layer where it first failed: …
- How we found it: …
- Fix: …

## 3. Troubleshooting findings

(problems met during the project, their cause and fix)

## 4. Learning summary per extension

A: … B: … C: … D: … E: … F: …

## 5. Evidence index

(paste the "Evidence files" section of evidence/REPORT.md)
