# 2 · Phase 1 walkthrough: every task, step by step

This covers everything the project brief asks for in Phase 1:
- Tasks A–G
- the five required failure demonstrations
- the explanation-only topics

For each one you get:

- **Goal**: what the brief asks for, in plain words.
- **Automatic**: one command that runs it in the 5 terminals for you.
- **By hand**: the exact commands to type yourself, on which machine, and what you should see. Do it by hand at least once, so you can explain it in the viva.
- **Explain it**: what to say.

Before you start: the project is running (`make` finished with `All services up`) and the 5 terminals are open. See [`1-SETUP-GUIDE.md`](1-SETUP-GUIDE.md).
`settings.env` should say `PHASE=1`; `make live-p1` and `make form` switch to Phase 1 by themselves anyway.

> "**node-4 ▸**" means: click the node-4 terminal and type there. "**YOU ▸**" means: the bottom terminal on your Mac.
> Replace `team1.test` with your own domain. If `settings.env` has `VPC_MODE=default`, every `10.0.1.x` below is `172.31.250.x` for you.

---

## The whole Phase 1 review in one command

```bash
YOU ▸ make live-p1
```

This runs 13 scenes in order:
- topology, lan, dns, https, headers, lb, cache, capture;
- then the five failures.

How a run behaves:
- For each scene the engine types the commands into the right machine and starts live logs in the other terminals.
- Your terminal shows talking points and ✔/✘ checks.
- After each scene: **Enter** = next, **r** = repeat, **q** = quit. **Ctrl-C** at any time stops it and repairs everything.

Options:

| Option | Effect |
|---|---|
| `make live-p1 AUTO=1` | runs without stopping (good for a quick rehearsal) |
| `make live-p1 FROM=9` | starts at scene 9 |
| `make scene SCENE=dns` | runs one scene only |
| `make live-p1 PACE=2` | waits 2 s between commands (good for recording) |

Each scene saves what every terminal showed into `evidence/live/<date>/<scene>/`.

---

## Task A: machines on one LAN, IP inventory, ping every pair

**Goal:** all machines on the same private network. For each one, write down IP, subnet prefix/mask, default gateway, active interface and MAC address. Show that every machine can ping every other one. Draw the topology.

**Automatic:** `YOU ▸ make scene SCENE=topology` then `make scene SCENE=lan`.
The first also writes the table to `evidence/inventory.md`.

**By hand** (do it in each of the four node terminals):

```bash
cn-info
```

Output (example from node-1):

```
machine       node-1  (Mac 1 - primary DNS (dnsmasq) + test client)
interface     ens5
ipv4/prefix   10.0.1.11/24
subnet mask   255.255.255.0
gateway       10.0.1.1
mac address   0a:1b:2c:3d:4e:5f
dns servers   10.0.1.11 (/etc/resolv.conf)
listening on:
  udp  10.0.1.11:53          dnsmasq
```

`cn-info` only combines these standard commands. You can show them instead:

```bash
ip -4 addr show ens5          # IP and /24 prefix
ip route | grep default       # gateway
ip link show ens5             # MAC address ("link/ether")
```

Ping:

```bash
cn-pingall                    # pings the other three, 4 packets each
ping -c 4 10.0.1.12           # or one by one
```

You want `4 packets transmitted, 4 received, 0% packet loss`. Run it on all four machines: that covers all 12 directions.

**Topology diagram:** `docs/architecture.md` (also drawn at the start of `make scene SCENE=topology`).

**Explain it:**
> "All four machines are in one subnet, 10.0.1.0/24. Mask 255.255.255.0 means the first three numbers identify the network, so they reach each other directly without a router. The gateway 10.0.1.1 is only used for traffic leaving the subnet. On AWS the VPC subnet plays the role of the lab Wi-Fi."

---

## Task B: our own DNS server

**Goal:** dnsmasq on Mac 1 answers `app.team1.test` and `api.team1.test` with Mac 2's IP. At least two other machines use it. Prove it with `dig`/`nslookup`. Explain how DNS differs from connecting.

**Automatic:** `YOU ▸ make scene SCENE=dns`

**By hand:**

1. **node-1 ▸** look at the configuration:
   ```bash
   grep -vE '^\s*(#|$)' /etc/dnsmasq.d/cn-team.conf
   ```
   Important lines:
   - `interface=ens5` and `listen-address=10.0.1.11`: listen on the LAN, not only on 127.0.0.1, so other machines can ask.
   - `address=/app.team1.test/10.0.1.12`: the answer.
   - `local=/team1.test/`: our zone, never asked on the internet.
   - `local-ttl=30`: answers may be cached for 30 s.

   The source of this file is `config/dnsmasq.conf` in the project.
2. **node-1 ▸** check the service and watch the questions arrive:
   ```bash
   systemctl status dnsmasq --no-pager | head -3
   cn-follow dns            # live log; leave it running
   ```
3. **node-4 ▸** which DNS server does this client use?
   ```bash
   cat /etc/resolv.conf     # nameserver 10.0.1.11
   ```
4. **node-4 ▸** ask:
   ```bash
   dig app.team1.test
   ```
   Check these lines:
   - `status: NOERROR`
   - `ANSWER SECTION: app.team1.test. 30 IN A 10.0.1.12`
   - `SERVER: 10.0.1.11#53(10.0.1.11) (UDP)`

   At the same moment node-1's log shows `query[A] app.team1.test from 10.0.1.14`.
5. **node-4 ▸** more proof:
   ```bash
   nslookup api.team1.test             # also 10.0.1.12
   dig @8.8.8.8 app.team1.test         # status: NXDOMAIN: Google's DNS has never heard of it
   ```
6. **node-2 ▸** and **node-3 ▸** show that other machines use it too:
   ```bash
   cat /etc/resolv.conf; getent hosts app.team1.test
   ```
7. Press **Ctrl-C** in node-1 to stop the log.

**Explain it:**
> "DNS is a phone book: it only turns a name into an IP address, over UDP port 53. Connecting to that IP is a separate step: TCP and TLS on port 443. We use .test because it is reserved for testing. .local is used by Bonjour/mDNS on Macs and would not reach our server."

---

## Task C: two backends

**Goal:** two small web services on Mac 3 (port 3001) and Mac 4 (port 3002). Each has `GET /` and `GET /api/status`, returns JSON saying which backend it is, sends an `X-Backend` header and listens on the LAN interface.

**Automatic:** shown inside the `lb` and `https` scenes.

**By hand:**

1. **node-3 ▸**
   ```bash
   systemctl status backend-a --no-pager | head -4     # active (running)
   sudo ss -lntp | grep 3001                          # 0.0.0.0:3001 python3
   curl -i http://localhost:3001/api/status           # X-Backend: A + JSON
   curl http://localhost:3001/                        # GET / also works
   ```
2. **node-4 ▸** the same for B:
   ```bash
   curl -i http://localhost:3002/api/status           # X-Backend: B
   ```
3. **node-2 ▸** the edge can reach both over the LAN:
   ```bash
   curl -s http://10.0.1.13:3001/api/status; curl -s http://10.0.1.14:3002/api/status
   ```

The code is `config/backend.py`: about 100 lines of Python using only the standard library. The service file is `config/backend.service`.

**Explain it:**
> "Each backend listens on 0.0.0.0, so it is reachable through the LAN interface. If it listened on 127.0.0.1, nginx on another machine could not reach it. `tcp_peer` in the JSON is nginx's address, because nginx opens its own connection; the real client is in X-Forwarded-For."

---

## Task D: one entry point with load balancing

**Goal:** nginx on Mac 2 is the only entry point and spreads requests over both backends (round-robin).

**Automatic:** `YOU ▸ make scene SCENE=lb`

**By hand:**

1. **node-2 ▸** the configuration:
   ```bash
   cat /etc/nginx/conf.d/cn-edge.conf
   ```
   - `upstream backends { server 10.0.1.13:3001 …; server 10.0.1.14:3002 …; }` is the list of workers.
   - `proxy_pass http://backends;` sends each request to the next one.

   The source is `config/nginx-edge.conf`.
2. **node-2 ▸** `cn-follow nginx`, then **node-3 ▸** `cn-follow` and **node-4 ▸** `cn-follow`. These are three live logs.
3. **node-1 ▸**
   ```bash
   for i in {1..6}; do curl -s https://app.team1.test/api/status | grep backend; done
   ```
   It alternates `"backend": "A"`, `"B"`, `"A"`, … and the logs on node-3 and node-4 light up in turn.
   `cn-probe 8` shows the same thing more readably.
4. Ctrl-C in the three log terminals.

**Explain it:**
> "The client always talks to the same name and IP, 10.0.1.12:443. Only nginx knows the backends. Round-robin takes them in turn. least_conn, which picks the least busy one, is the alternative."

---

## Task E: HTTPS with a trusted certificate (never `-k`)

**Goal:**
- a certificate for the domain;
- nginx serving HTTPS on 443;
- every client trusting the certificate, so `curl` works **without `-k`**;
- an explanation of the TLS handshake.

**Automatic:** `YOU ▸ make scene SCENE=https`

**How it was set up (by `make`, in `scripts/remote/pki.sh`):**
- On node-2 a private **certificate authority** (CA) is created: `/etc/cn-pki/ca.crt` and `ca.key`.
- It signs a server certificate for `app.team1.test` and `api.team1.test`: `/etc/cn-pki/tls.crt`.
- nginx uses it from `/etc/nginx/cn-tls/`.
- The CA certificate is copied to every machine's trust store: `/usr/local/share/ca-certificates/cn-team-ca.crt`, then `update-ca-certificates`.
- A copy is in the project folder: `certs/ca.crt`.

**By hand:**

1. **node-4 ▸**
   ```bash
   curl -v https://app.team1.test
   ```
   Look for these lines:
   - `* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384`
   - `* Server certificate:` with `subject: CN=app.team1.test`
   - `* subjectAltName: host "app.team1.test" matched cert's "app.team1.test"`
   - `* SSL certificate verify ok.`
   - `< HTTP/2 200`
2. **node-4 ▸** look at the certificate itself:
   ```bash
   echo | openssl s_client -connect app.team1.test:443 -servername app.team1.test 2>/dev/null \
     | openssl x509 -noout -subject -issuer -ext subjectAltName -dates
   ```
   The issuer is `CN = team1 Private CA`.
3. **node-4 ▸** the CA is in the trust store:
   ```bash
   ls -l /usr/local/share/ca-certificates/
   ```
4. **node-4 ▸** plain HTTP redirects to HTTPS:
   ```bash
   curl -sI http://app.team1.test | head -3     # 301 Moved Permanently, Location: https://...
   ```

**Explain it:**
1. ClientHello: TLS versions, cipher suites, the name we want (SNI).
2. ServerHello: the server picks the version and cipher.
3. Certificate: the server proves who it is. The client checks it is signed by a CA it trusts and that the name matches.
4. Key exchange: both sides compute the same secret key.
5. Finished: everything after this is encrypted.

> "`-k` would skip the identity check. We don't need it because we installed our own CA on every client, the same way companies do internally."

---

## Task F: HTTP caching (Cache-Control, ETag, 304)

**Goal:** cache headers on responses. Show them with `curl -I`. Show a repeat request answered from cache or with 304, and explain the difference.

**Automatic:** `YOU ▸ make scene SCENE=cache`

**By hand:**

1. **node-1 ▸**
   ```bash
   curl -sI https://app.team1.test/api/status
   ```
   You get `cache-control: public, max-age=60`, an `etag: "…"`, `date:` and `x-backend:`.
2. **node-1 ▸** the conditional request (304):
   ```bash
   E=$(curl -sI https://app.team1.test/api/cached | awk 'tolower($1)=="etag:"{print $2}' | tr -d '\r')
   echo "ETag = $E"
   curl -sI -H "If-None-Match: $E" https://app.team1.test/api/cached
   ```
   The answer is `HTTP/2 304` with no body. We use `/api/cached` for this because its content is identical on A and B, so the 304 works whichever backend answers.

**Explain it:**
- `max-age=60`: the client may reuse its copy for 60 s **without asking**. That is a *fresh hit*: no network at all.
- After 60 s it asks "do you still have version `<ETag>`?" (`If-None-Match`). If nothing changed, the answer is *304 Not Modified*, which is tiny and has no body.
- If the content changed, or the client has no copy, it gets a *full 200 response* with the body.

In a browser you can see this in DevTools → Network: "(disk cache)" or status 304.

---

## Task G: packet evidence

**Goal:** capture and point out:
- the DNS query and response;
- the TCP three-way handshake;
- the TLS ClientHello, ServerHello, Certificate and ChangeCipherSpec;
- encrypted application data;
- the HTTP headers;
- which ports are used.

**Automatic:** `YOU ▸ make scene SCENE=capture`
It saves `evidence/pcap/client-dns-tcp-tls.pcap` (client side), `edge-to-backend.pcap` (nginx → backends, plain HTTP) and `tls-keys.log`.

**By hand, the easy way. node-4 ▸**
```bash
sudo cn-capture
```
It makes two HTTPS requests (TLS 1.2 and TLS 1.3) while recording, then prints:
1. DNS: client port → 10.0.1.11:53, answer and TTL
2. TCP: SYN → SYN-ACK → ACK with sequence numbers
3. TLS: ClientHello, ServerHello, Certificate, ChangeCipherSpec
4. cipher suites offered and chosen, certificate names
5. how many Application Data records were encrypted
6. the same traffic **decrypted** using the saved keys, which shows the HTTP inside

**By hand, the manual way. node-4 ▸**
```bash
sudo tcpdump -i $(cn-iface) -U -w /tmp/my.pcap 'udp port 53 or tcp port 443' &
sleep 1
curl -s --tls-max 1.2 https://app.team1.test/api/status
sleep 1
sudo pkill tcpdump
```
**YOU ▸** copy it to your Mac:
```bash
scp -F .generated/ssh_config node-4:/tmp/my.pcap evidence/
```

**In Wireshark** (open the `.pcap` file):

| Filter | What you see | What it proves |
|---|---|---|
| `dns` | Query "A app.team1.test" 10.0.1.14:5xxxx → 10.0.1.11:53; response with the answer 10.0.1.12, TTL 30 | name resolution uses UDP/53 and our server |
| `tcp.flags.syn==1` | SYN 10.0.1.14:5xxxx → 10.0.1.12:443, then SYN-ACK back. The next packet (ACK) completes it | a TCP connection is set up before any data |
| `tls` | Client Hello → Server Hello, Certificate → Change Cipher Spec → Application Data | the TLS handshake, then encryption |
| `tls.handshake.type == 11` | the Certificate packet; expand it to see `CN=app.team1.test` | the server's identity (readable in TLS 1.2 only) |
| `http` (after setting the key log, see below) | `GET /api/status`, `HTTP/1.1 200 OK`, headers | the HTTP that was inside TLS |

To decrypt in Wireshark: **Wireshark → Settings (older versions: Preferences) → Protocols → TLS → (Pre)-Master-Secret log filename** = `evidence/pcap/tls-keys.log`.

**Ports to name:**
- the client uses a random **ephemeral** port (e.g. 54821) for each connection;
- DNS uses **53/UDP**;
- HTTPS uses **443/TCP**;
- nginx → backends use **3001/3002 TCP**, plain HTTP inside the LAN (see `edge-to-backend.pcap`).

**HTTP headers:** `curl -v https://app.team1.test/api/status` (`>` lines are sent, `<` lines are received), or `make scene SCENE=headers`. The headers scene also compares HTTP/1.1 with HTTP/2.

---

## The five required failure demonstrations

Do each one as **before → break → after → explain → restore**. If you ever lose track: `YOU ▸ make restore`.

### Failure 1: client uses the wrong DNS server

**Automatic:** `make scene SCENE=fail_dns_server`

**By hand, node-4 ▸**
```bash
dig +short app.team1.test                  # before: 10.0.1.12
sudo cn-resolver set 8.8.8.8               # break: use Google DNS instead of ours
dig app.team1.test | grep -E 'status|SERVER'   # NXDOMAIN, SERVER 8.8.8.8
curl -sS https://app.team1.test            # curl: (6) Could not resolve host
ping -c 2 10.0.1.12                        # but the edge is still reachable by IP
sudo cn-resolver reset                     # restore
dig +short app.team1.test                  # 10.0.1.12 again
```
**Layer:** the application layer (DNS). The network (IP) works fine, so a name problem is not a connection problem.

### Failure 2: DNS record points to the wrong IP

**Automatic:** `make scene SCENE=fail_dns_record`

**By hand:**
```bash
node-1 ▸ sudo cn-dns set 10.0.1.11         # break: app/api now point to node-1
node-4 ▸ dig +short app.team1.test         # 10.0.1.11: resolution "works"
node-4 ▸ curl -sS https://app.team1.test   # Failed to connect ... Connection refused
node-1 ▸ sudo cn-dns set 10.0.1.12         # restore
node-4 ▸ dig +short app.team1.test         # 10.0.1.12
```
**Layer:** DNS gave a wrong answer, so TCP went to a machine with nothing on port 443. DNS doesn't know or care whether the address works.

### Failure 3: one backend stopped (service continues)

**Automatic:** `make scene SCENE=fail_one_backend`

**By hand:**
```bash
node-2 ▸ cn-follow nginx                   # watch the edge
node-1 ▸ cn-probe 20 0.5                   # 20 requests, two per second
node-3 ▸ sudo systemctl stop backend-a     # while node-1 is running
           (node-1 now shows backend=B only, all 200; node-2 logs "connection refused" for 10.0.1.13:3001)
node-3 ▸ sudo systemctl start backend-a    # restore; after ~10 s nginx uses A again
```
**Layer:** the application behind the edge. nginx retried on B (`proxy_next_upstream`) and marked A as down for 10 s, so users saw no error.

### Failure 4: both backends stopped → 502

**Automatic:** `make scene SCENE=fail_both_backends`

**By hand:**
```bash
node-3 ▸ sudo systemctl stop backend-a
node-4 ▸ sudo systemctl stop backend-b
node-1 ▸ dig +short app.team1.test                        # DNS fine
node-1 ▸ curl -sv https://app.team1.test/api/status 2>&1 | grep -E 'SSL connection|verify ok|< HTTP'
                                                           # TLS fine, but HTTP/2 502
node-3 ▸ sudo systemctl start backend-a
node-4 ▸ sudo systemctl start backend-b                    # restore
```
**Layer:** DNS, TCP and TLS to the edge all work. The edge has nobody behind it, so it answers **502 Bad Gateway**.

### Failure 5: right host, wrong port

**Automatic:** `make scene SCENE=fail_wrong_port`

**By hand:**
```bash
node-2 ▸ sudo ss -lntp | grep nginx            # nginx listens on 80 and 443 only
node-1 ▸ nc -zv app.team1.test 443             # succeeded
node-1 ▸ nc -zv app.team1.test 9999            # Connection refused
node-1 ▸ curl -sS https://app.team1.test:9999  # Failed to connect ... Connection refused
node-1 ▸ ping -c 2 app.team1.test              # host is reachable
```
**Layer:** transport (TCP). The IP address picks the machine; the port picks the program. With no program on 9999, the machine answers the SYN with a reset (RST), so the connection is refused at once rather than timing out.

---

## Explanation-only topics (no demo needed)

| Topic | Where to read |
|---|---|
| HTTP/1.1 vs HTTP/2 (shown) and HTTP/3 / QUIC (explain only) | `make scene SCENE=headers`, team viva notes |
| Email protocols (SMTP, IMAP, POP3, MX records) | team viva notes |
| OSI layer mapping of the whole project | `architecture.md` → "OSI / TCP-IP mapping" |
| Cloud equivalents (Route 53, ALB, ACM, security groups, CloudFront) | `architecture.md` → "Cloud equivalents" |

---

## Rehearsal plan for the Phase 1 review

1. The day before: `make live-p1 AUTO=1`. Everything should end with **0 failed checks**.
2. Each member does their own tasks **by hand** once, using this guide:

   | Member | Tasks |
   |---|---|
   | Member 1 | A, B |
   | Member 2 | C, D |
   | Member 3 | E, F, G |
   | Member 4 | the five failures |

3. On the day: `make`, then `make live-p1`. Each member presents their scenes using the talking points shown in the bottom terminal.
4. If anything goes wrong during the review: press **q** (or Ctrl-C), run `make restore`, then `make live-p1 FROM=<scene number>`.
