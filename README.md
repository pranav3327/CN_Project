# Private Network Service Platform

A small private network that serves one website, `app.team1.test`, across four machines: DNS, a TLS edge with load balancing, and two backend services. One command builds and verifies all of it.

Computer Networks project, Semester 5. The brief asks for four Macs on one Wi-Fi. This version runs the same design on four Ubuntu instances in one AWS subnet, so every protocol, port and command is identical, and the whole environment can be rebuilt from scratch in about five minutes.

## Architecture

```
                 private subnet 172.31.250.0/24
  node-1  .11   DNS (dnsmasq), test client
  node-2  .12   edge: nginx, TLS termination, round-robin load balancer
  node-3  .13   Backend A on :3001
  node-4  .14   Backend B on :3002, test client

  client ──DNS udp/53──▶ node-1
  client ──HTTPS tcp/443──▶ node-2 ──HTTP──▶ node-3:3001 | node-4:3002
  laptop ──SSH tcp/22 (own IP only)──▶ all nodes
```

A request for `https://app.team1.test/api/status` goes through these steps:

1. node-1 resolves the name to the edge.
2. The connection is encrypted with a certificate from the team's private CA.
3. nginx decrypts it.
4. nginx forwards it round-robin to one of the two backends, over plain HTTP inside the subnet.

Each backend identifies itself with an `X-Backend` header, which makes load balancing and failover directly observable.

The subnet is `172.31.250.0/24` inside the account's default VPC (`VPC_MODE=default`), or `10.0.1.0/24` in a dedicated VPC (`VPC_MODE=new`). Host numbers `.11`–`.14` are fixed either way.

## What it demonstrates

- **LAN:** four hosts on one subnet, fixed addressing, full reachability.
- **DNS:** a private zone in dnsmasq. Non-project names are forwarded upstream.
- **HTTPS:** a private certificate authority trusted by every host. Verification passes without `-k`.
- **Load balancing:** nginx round-robin with passive health checks and retry on the other backend.
- **Caching:** `Cache-Control`, `ETag` and `304 Not Modified` on conditional requests.
- **Packets:** DNS, the TCP handshake, the TLS handshake and encrypted application data, captured and decryptable in Wireshark.
- **Failures:** wrong DNS server, wrong DNS record, one backend down, both backends down, and wrong port. Each one is isolated to the layer that breaks.

## Stack

Terraform, AWS EC2, Ubuntu 24.04, dnsmasq, nginx, Python (standard library), systemd, OpenSSL, tcpdump/tshark, tmux, Bash.

## Getting started

Requirements: macOS or Linux with `terraform`, `awscli` and `tmux`, and an AWS Academy Learner Lab session.

```bash
brew tap hashicorp/tap && brew install hashicorp/tap/terraform
brew install awscli tmux

make creds   # paste the AWS Academy credentials block
make         # infrastructure → boot → configure → verify → open the dashboard
```

The first run takes four to six minutes and ends with `All services up`. Every later run only repairs what differs, so `make` is also how you resume after the lab stops the instances.

All settings live in `settings.env`: team name, domain, TTL, region, instance type and VPC mode.

## Usage

| Command | Purpose |
|---|---|
| `make` | Build or repair everything, then open the dashboard |
| `make tmux` | Open the dashboard: one shell per machine plus a local control shell |
| `make live-p1` | Run the full Phase 1 demonstration (13 scenes) |
| `make scene SCENE=lb` | Run a single scene; `make scenes` lists them |
| `make form` | Collect every Phase 1 form answer into `evidence/form/FORM.md` |
| `make restore` | Return every machine to the known-good state |
| `make status` | Machines, addresses and service states |
| `make stop` / `make start` | Pause or resume the instances |
| `make down` | Delete every AWS resource |
| `make help` | All targets |

The dashboard has three windows:
- `Ctrl-b 0`: the four machine shells and your control shell.
- `Ctrl-b 1`: live service logs.
- `Ctrl-b 2`: live packets.

Each demonstration scene types its commands into the correct machine's shell, verifies the result and saves the output as evidence.

Every machine has helper commands for the common checks: `cn-info`, `cn-pingall`, `cn-probe`, `cn-capture`, `cn-follow`, `cn-wire` and `cn-diagnose`.

## How it works

- **Infrastructure:** Terraform creates the subnet, an SSH key, four instances with fixed private addresses, and a security group that allows all traffic between the four machines and only SSH from the operator's IP. cloud-init handles the OS layer only.
- **Configuration:** `scripts/converge.sh` renders the templates in `config/`, installs a file only when its content differs, and restarts only what changed. It verifies each layer before moving on:
  - DNS must answer before clients are switched to it.
  - `nginx -t` must pass before nginx reloads.
  - Twelve end-to-end HTTPS requests run at the end.
- **Idempotence:** the same command builds, repairs and resets the platform. `make restore` undoes every demonstration and fault.
- **Evidence:** form answers, packet captures, an IP inventory, per-scene terminal snapshots and check results are written to `evidence/`.

## Security

- Only SSH is reachable from the internet, and only from the operator's current public IP. The service itself is private.
- SSH is key-only. The generated key is stored with mode `0600` and never committed.
- Instances require IMDSv2.
- Only TLS 1.2 and 1.3 are allowed, with RSA-2048 keys and SAN-based certificates. The CA private key never leaves the edge node.
- Backends run as unprivileged dynamic users on ports above 1024.

Two known trade-offs, accepted for this scope:
- Traffic between the edge and the backends is plain HTTP inside the private subnet.
- The edge is a single point of failure.

## Project layout

```
infra/      Terraform: network, security group, key, instances, cloud-init
scripts/    converge, dashboard, live demonstration, form collection, fault injection
config/     dnsmasq, nginx and systemd templates, and the backend service
node-bin/   helper commands installed on every machine
docs/       setup guide, Phase 1 walkthrough, form guide, architecture, requirements coverage
evidence/   form output, packet capture, inventory and check results
```

## Documentation

- [Setup guide](docs/1-SETUP-GUIDE.md): from a fresh Mac to a running platform.
- [Phase 1 walkthrough](docs/2-PHASE1-WALKTHROUGH.md): every task and failure demonstration, automated and by hand.
- [Form guide](docs/3-FORM-GUIDE.md): how each Phase 1 form answer is produced.
- [Architecture](docs/architecture.md): request flow, OSI mapping, design decisions and cloud equivalents.
- [Requirements coverage](docs/requirements-coverage.md): every item of the brief and where it is implemented.

## Notes

- AWS Academy credentials expire with the lab session. Run `make creds` again when Terraform reports expired credentials.
- Public IPs change whenever instances stop. `make` picks up the new addresses automatically.
- Four `t3.small` instances cost about $0.08 per hour in total. `make stop` between sessions saves credit.
