# 3 · Phase 1 form guide: how to get every answer

The form asks for **real terminal output, not descriptions**. This guide shows how to get each answer and what the evaluator checks. It also lists the mistakes that cost marks.

If `settings.env` has `VPC_MODE=default`, read every `10.0.1.x` below as `172.31.250.x`.

Before you start: the project is running (`make` finished with `All services up`). See [`1-SETUP-GUIDE.md`](1-SETUP-GUIDE.md).

---

## Step 1. Collect everything with one command (about 2 minutes)

```bash
YOU ▸ make form
```

It switches the clients to Phase 1 DNS mode, then runs **every command exactly as the form words it**, on the machine the form asks for. It saves:

| File | Contents |
|---|---|
| `evidence/form/FORM.md` | all answers A1–D3, each as the real terminal output with its prompt line, e.g. `ubuntu@node-4:~$ dig app.team1.test` |
| `evidence/form/client-dns-tcp-tls.pcap` | the packet capture for Section C (open it in Wireshark) |
| `evidence/form/tls-keys.log` | TLS keys, so Wireshark can decrypt that capture |

When it finishes, everything is restored to normal.

Open `FORM.md` in any editor (VS Code, TextEdit) or on GitHub. Each form box has its own heading. You copy from the code blocks (the grey boxes), **not the ``` lines**.

**Texts marked "Draft"** (C1, C2, C3, D2, D3 layer) already contain your real IPs, ports, TTL and cipher. **Rewrite them in your own words.** The form gives 0–1 marks for vague or copied text, and four teams with identical sentences looks bad.

## Step 2. Take the screenshots `make form` cannot take

1. **A1:** the EC2 console instance list.
   - Open AWS Academy → **AWS** (the green dot) → search "EC2" → **Instances**.
   - Tick the columns *Name*, *Instance state*, *Private IPv4 address* (gear icon).
   - Screenshot the four rows node-1 … node-4.
2. **Section C:** three Wireshark screenshots.
   - Open `evidence/form/client-dns-tcp-tls.pcap` in Wireshark.
   - Screenshot with filter `dns`, then `tcp.flags.syn==1`, then `tls` (details under C1–C3 below).

## Step 3. Fill the form, box by box

Below, for each box: **what to paste**, **where it comes from**, **how to do it by hand**, and **what the evaluator checks**.

---

### Section A: Identity, LAN, DNS (marks: Identity & LAN /5 · DNS Config /5 · DNS Proof /5)

#### A1: Machine IPs and roles

**Paste:** the first block of FORM.md → A1. It looks like this (your IPs are the same; the interface is usually `ens5`):

```
Mac 1 / DNS + client:          10.0.1.11  (ens5)   instance/hostname node-1
Mac 2 / edge:                  10.0.1.12  (ens5)   instance/hostname node-2
Mac 3 / backend A:             10.0.1.13  (ens5)   instance/hostname node-3
Mac 4 / backend B + client:    10.0.1.14  (ens5)   instance/hostname node-4
```

Then paste the four `ip -4 -brief address` blocks and the `aws ec2 describe-instances` table under it. Add the EC2 console screenshot from Step 2.
Add one sentence: *"We used four AWS EC2 instances in one VPC subnet 10.0.1.0/24 (with the teacher's permission) instead of four physical Macs."*

**By hand:** on each node `hostname; ip -4 -brief address show ens5`.

**Checked:** each role, its private IP and its interface; cloud instance names with private VPC IPs.

#### A2: dnsmasq configuration

**Paste:** FORM.md → A2 (on node-1, the config without comment lines). The lines the evaluator looks for:

```
interface=ens5
listen-address=10.0.1.11
address=/app.team1.test/10.0.1.12
address=/api.team1.test/10.0.1.12
local-ttl=30
```

**By hand:** `node-1 ▸ grep -vE '^\s*(#|$)' /etc/dnsmasq.d/cn-team.conf`

**Checked:** the `address=` lines with your edge IP, `listen-address=` that is **not** 127.0.0.1, and an `interface=` line. All three are there.

> Our file is `/etc/dnsmasq.d/cn-team.conf` (Ubuntu loads every file in that folder) rather than `dnsmasq.conf`. Say so in one line if you want.

#### A3: `dig app.team1.test` from a client

**Paste:** FORM.md → A3, the full `dig` block, run on **node-4** (Mac 4).

**By hand:** `node-4 ▸ dig app.team1.test`

**Checked:**
- `;; ANSWER SECTION:` → `app.team1.test. 30 IN A 10.0.1.12` (the edge)
- `;; SERVER: 10.0.1.11#53(10.0.1.11)` (our DNS server, not 8.8.8.8)

**Mistakes:**
- Running it on node-1 (the DNS server itself).
- Seeing `SERVER: 127.0.0.53`. That means the clients are in Phase 2 mode; run `make form` or set `PHASE=1` and run `make converge`.

#### A4: `dig @8.8.8.8 app.team1.test`

**Paste:** FORM.md → A4.

**By hand:** `node-4 ▸ dig @8.8.8.8 app.team1.test`

**Checked:** `status: NXDOMAIN`, meaning Google's public DNS says the name does not exist. Our domain is private.

#### A5: Ping between all pairs

**Paste:** FORM.md → A5, the four `cn-pingall` blocks (one per machine, 12 directions). Then add a short summary:

```
node-1 → node-2 (10.0.1.12): 4 packets, 0% loss
node-1 → node-3 (10.0.1.13): 4 packets, 0% loss
node-1 → node-4 (10.0.1.14): 4 packets, 0% loss
node-2 → node-3: 0% loss        node-2 → node-4: 0% loss        node-3 → node-4: 0% loss
(and the reverse directions, all 0% loss)
Pings go machine to machine over the private VPC IPs, not via the internet.
```

**By hand:** on each node `cn-pingall`, or `ping -c 4 10.0.1.12` etc.

---

### Section B: HTTPS and load balancing (marks: HTTPS /5 · Load Balancing /5)

> ⚠ **Never use `-k`** in anything you paste. `-k` = 0 marks for HTTPS. Our setup never needs it.

#### B1: `curl -v https://app.team1.test`

**Paste:** FORM.md → B1, the complete output.

**By hand:** `node-4 ▸ curl -v https://app.team1.test`

**Checked** (point to these lines):
- `* SSL connection using TLSv1.3 / …`: the TLS handshake
- `*  subject: CN=app.team1.test` and `subjectAltName: host "app.team1.test" matched`: the certificate matches the domain
- `*  SSL certificate verify ok.`: trusted without `-k`
- `< HTTP/2 200`: success
- the command uses the domain, not an IP

#### B2: Load balancing (6 responses)

**Paste:** FORM.md → B2. There are two blocks:
1. The exact form command `for i in {1..6}; do curl -s https://app.team1.test/api/status; echo; done`. Each JSON shows `"backend": "A"` or `"B"`, alternating.
2. The same 6 requests showing just the header lines `x-backend: A`, `x-backend: B`, … The form mentions the *X-Backend header*, and `curl -s` alone only prints the body, so include both.

**By hand:** `node-4 ▸ for i in {1..6}; do curl -si https://app.team1.test/api/status | grep -i '^x-backend'; done`

**Checked:** both A and B appear. Ours alternate exactly.

#### B3: nginx configuration

**Paste:** FORM.md → B3 (the whole `cn-edge.conf`), or just these parts:
- the `upstream backends { server 10.0.1.13:3001 …; server 10.0.1.14:3002 …; }` block;
- the `server { listen 443 ssl http2; … ssl_certificate …; ssl_certificate_key …; location / { proxy_pass http://backends; … } }` block.

**By hand:** `node-2 ▸ cat /etc/nginx/conf.d/cn-edge.conf`

**Checked:** both backend IP:ports, `ssl_certificate` and `ssl_certificate_key`, and `proxy_pass` to the upstream. All present.

---

### Section C: Wireshark (marks: DNS /3 · TCP /3 · TLS /2)

You don't upload the file, but the descriptions must name **specific IPs, ports, packet types and what each proves**.

**Get your numbers:**
- `FORM.md → C` has the `cn-capture` output and the three Draft texts already filled with your values.
- For screenshots, open `evidence/form/client-dns-tcp-tls.pcap` in Wireshark (double-click it).

The capture has two HTTPS requests:
- the **first** is TLS 1.2, where the certificate is readable;
- the **second** is TLS 1.3.

**By hand** (if you want to capture yourself): `node-4 ▸ sudo cn-capture`, then `YOU ▸ scp -F .generated/ssh_config node-4:/tmp/cn-client.pcap evidence/`.

#### C1: DNS

**In Wireshark:** type `dns` in the filter bar and press Enter. Click the **query**, then the **response**. In the middle pane expand *Domain Name System → Answers*.

**Write** (your own words, your numbers from the Draft):
- **Query:** "Standard query A app.team1.test" from the client 10.0.1.14, source port (e.g. 51034, an ephemeral port), to the DNS server 10.0.1.11 on **UDP port 53**.
- **Response:** from 10.0.1.11:53 back to the same client port. Answer: `app.team1.test A 10.0.1.12`, **TTL 30**.
- **What it proves:** our private DNS answered and pointed the client to the edge. The client may cache it for 30 s.

#### C2: TCP three-way handshake

**In Wireshark:** filter `tcp.flags.syn==1` shows the SYN and the SYN-ACK. Then right-click the SYN → *Follow → TCP Stream*, or clear the filter, to see the ACK right after.

**Write:**
- **SYN:** 10.0.1.14:**<ephemeral port>** → 10.0.1.12:**443**, Seq=0 (relative).
- **SYN-ACK:** 10.0.1.12:443 → 10.0.1.14:<port>, Seq=0, Ack=1. The server acknowledges and sends its own starting number.
- **ACK:** 10.0.1.14 → 10.0.1.12:443, Seq=1, Ack=1. The connection is established.
- **What it establishes:** a reliable, ordered, connection-oriented channel. Both sides agree starting sequence numbers so lost or out-of-order data can be detected and resent. It happens **before** any TLS data.

The raw (non-relative) sequence numbers are in the Draft if you want to quote them.

#### C3: TLS handshake and why HTTP is unreadable

**In Wireshark:** filter `tls`. In the Info column you see:

1. `Client Hello (SNI=app.team1.test)`
2. `Server Hello, Certificate, Server Key Exchange, Server Hello Done` (the TLS 1.2 request)
3. `Client Key Exchange, Change Cipher Spec, Encrypted Handshake Message`
4. `Change Cipher Spec, Encrypted Handshake Message`
5. then only `Application Data`

Click the Client Hello and expand *Transport Layer Security → Handshake Protocol → Cipher Suites* to see the offered list.

**Write:**
- **ClientHello** from 10.0.1.14 to 10.0.1.12:443: supported versions TLS 1.3/1.2, **N cipher suites offered** (N is in the Draft), SNI app.team1.test.
- **ServerHello** chooses one cipher (in the Draft). **Certificate:** CN=app.team1.test, issued by "team1 Private CA".
- **ChangeCipherSpec:** from here on both sides encrypt. Everything afterwards shows only as **Application Data**.
- **Why HTTP is unreadable:** the method, path, headers and body are inside encrypted TLS records. Wireshark has no session keys, so it cannot read them. (With our key log file it *can* decrypt them, which proves the HTTP is really inside.)
- **TLS 1.3 note:** in the second request even the certificate is encrypted. That's why we also forced one TLS 1.2 request.

---

### Section D: Caching and failure (marks: Caching /4 · Failure Demo /5)

#### D1: `curl -sI https://app.team1.test/api/status`

**Paste:** FORM.md → D1. It contains:

```
HTTP/2 200
date: …
content-type: application/json
x-backend: A
cache-control: public, max-age=60
etag: "…"
x-edge: node-2
```

Also paste the second block (the `If-None-Match` request that returns **304**) as the bonus.

**By hand:** `node-4 ▸ curl -sI https://app.team1.test/api/status`

**Checked:** `cache-control` (yes: max-age=60), `etag` (yes), `date` (yes), `x-backend` (yes).

#### D2: What Cache-Control tells the client

Rewrite the Draft in your own words. It needs 2–4 sentences, plus the bonus:
- `public, max-age=60` means any cache (browser or proxy) may keep the response and reuse it for 60 seconds without contacting the server.
- During those 60 s the client sends nothing: a fresh cache hit.
- After 60 s the copy is stale. The client asks again with `If-None-Match: <ETag>`.
- **Bonus (ETag / 304):** if the content hasn't changed, the server answers **304 Not Modified** with no body, and the client keeps using its copy. If it changed, it gets 200 with the new body and a new ETag.

#### D3: Failure demonstration (also in the video)

We use **Option A: stop one backend**. `FORM.md → D3` already contains, as real output:
1. **Before:** 6 requests, `X-Backend: A`, `B`, `A`, `B`, …
2. **Action:** `sudo systemctl stop backend-a` on node-3, showing `inactive`.
3. **After:** 6 requests, all `200 X-Backend: B`.
4. The nginx error log line on node-2: `connect() failed (111: Connection refused) … upstream: "http://10.0.1.13:3001/…"`.
5. **Restore:** `sudo systemctl start backend-a`, then 6 requests with A back again.

**Write the five parts:**
1. **Option:** A, stop one backend.
2. **Before:** paste the first block, both backends alternate.
3. **After:** paste the second block. Every request still returns 200, all from B.
4. **Layer affected:** the application layer behind the edge (Backend A's HTTP service on node-3). At the transport layer, port 3001 now refuses TCP connections. DNS, IP, TCP to the edge and TLS were not affected. nginx detected the refused connection, retried the request on B and marked A as down for 10 s, so users saw no error.
5. **Restored:** `systemctl start backend-a`. After nginx's 10 s `fail_timeout`, round-robin resumed (paste the last block).

**By hand / for the video:** `make scene SCENE=fail_one_backend` shows it live in the 4 terminals, or follow Failure 3 in [`2-PHASE1-WALKTHROUGH.md`](2-PHASE1-WALKTHROUGH.md).

---

## Final check before submitting

- [ ] No `-k` anywhere in what you pasted
- [ ] A3 shows `SERVER: 10.0.1.11` (not 127.0.0.53) and was run on node-4
- [ ] A4 shows `NXDOMAIN`
- [ ] B1 uses `https://app.team1.test`, not an IP, and shows `verify ok` and `200`
- [ ] B2 shows both A and B
- [ ] C1–C3 name real IPs, ports, packet types and TTL, written in your own words
- [ ] D3 has all five parts, and the same demo is in the video
- [ ] EC2 console screenshot (A1) and Wireshark screenshots (C) attached
- [ ] Your team's domain is used everywhere instead of `team1.test`
