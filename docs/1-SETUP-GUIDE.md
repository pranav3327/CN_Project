# 1 · Setup guide (start here)

This guide takes you from a fresh Mac to the whole project running in AWS, step by step.
You do not need to know Terraform, AWS or Linux. Every command is written out exactly.

Read the guides in this order:

1. **This file**: install the tools, start the project, open the 5 terminals.
2. [`2-PHASE1-WALKTHROUGH.md`](2-PHASE1-WALKTHROUGH.md): every Phase 1 task and failure demo, the automatic way and by hand.
3. [`3-FORM-GUIDE.md`](3-FORM-GUIDE.md): how to get every answer for the Phase 1 submission form.

---

## Part 1. What you are building (2-minute read)

The brief asks for four Macs on one Wi-Fi. We use **four Linux virtual machines in AWS** instead.
They sit in one private network, so everything behaves like a LAN.

| Machine | Plays the role of | Private IP | Its job |
|---|---|---|---|
| node-1 | Mac 1 | 10.0.1.11 | DNS server (dnsmasq): turns `app.team1.test` into an IP. Also a test client. |
| node-2 | Mac 2 | 10.0.1.12 | Edge (nginx): HTTPS, then passes each request to a backend in turn |
| node-3 | Mac 3 | 10.0.1.13 | Backend A on port 3001 (+ backup DNS and standby edge in Phase 2) |
| node-4 | Mac 4 | 10.0.1.14 | Backend B on port 3002. Also our main test client. |

A request travels like this:

```
node-4 (client)  ──DNS: "where is app.team1.test?"──▶  node-1  ──▶ "10.0.1.12"
node-4 (client)  ──HTTPS :443──▶  node-2 (nginx)  ──HTTP──▶  node-3:3001  or  node-4:3002
```

You never set any of this up by hand. The command `make` does it all:

1. **Terraform** (`infra/`) creates the private network and the four machines in AWS.
2. **cloud-init** installs the basic tools when each machine first boots.
3. **converge** (`scripts/converge.sh`) installs and configures DNS, the backends, the certificates and nginx, then tests everything.

Running `make` again is always safe. It only fixes what is different from the correct state.

---

## Part 2. One-time installation on your Mac (about 15 minutes)

Open the **Terminal** app (press Cmd+Space, type "Terminal" and press Enter).

### Step 2.1. Install Homebrew (the Mac package installer)

Check if you already have it:

```bash
brew --version
```

If you see "command not found", install it. Copy this line exactly:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

At the end it prints two or three lines under **"Next steps"**. Copy and run them; they add `brew` to your PATH. Close Terminal and open it again.

### Step 2.2. Install the tools

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform awscli tmux
brew install --cask wireshark
```

Check each one:

```bash
terraform version     # Terraform v1.x
aws --version         # aws-cli/2.x
tmux -V               # tmux 3.x
```

Wireshark is only needed for the packet screenshots (Task G / form Section C).

### Step 2.3. Get the project folder

You get the project in one of two ways:

- **Zip file:** unzip `cn-project.zip`, for example into your Documents folder.
- **Shared Git repository:** run `git clone <repo-url>`.

Then go into the folder:

```bash
cd ~/Documents/cn-project      # use the path where YOU put it
ls                             # you should see: Makefile  README.md  settings.env  infra  scripts ...
```

**Every `make` command must be run inside this folder.**

### Step 2.4. Check the settings

Open `settings.env` in any text editor. Normally you only check two lines:

```
TEAM=team1
DOMAIN=team1.test
```

If an earlier `make` failed with **VpcLimitExceeded**, also set `VPC_MODE=2default` (see Part 6).

Change `team1` to your team number if needed, e.g. `TEAM=team7` and `DOMAIN=team7.test`. The domain must end in `.test`.

> Everywhere in these guides you see `team1.test`, use your own domain instead.

---

## Part 3. Every lab session (about 6 minutes the first time, 1–2 minutes later)

### Step 3.1. Start the AWS Academy lab

1. Log in to AWS Academy → your course → **Modules** → **Learner Lab**.
2. Click **Start Lab** and wait until the dot next to "AWS" turns **green** (about 1–2 minutes).
3. Click **AWS Details**. Next to "AWS CLI", click **Show**.
4. Select and copy the whole block. It starts with `[default]` and has 3 lines:
   `aws_access_key_id`, `aws_secret_access_key` and `aws_session_token`.

### Step 3.2. Give the credentials to your Mac

In Terminal, inside the project folder:

```bash
make creds
```

It reads the block from your clipboard. If it asks you to paste instead, paste it, press Enter, then **Ctrl-D**. It ends by printing an ARN like `arn:aws:sts::123456789012:assumed-role/voclabs/...`. That means it worked.

> The credentials expire when the lab session ends (about every 4 hours). Next time, repeat Steps 3.1–3.2.

### Step 3.3. Build everything

```bash
make
```

What you will see:

| Stage | What it means | Time (first run) |
|---|---|---|
| `Preflight` | checks tools and credentials | seconds |
| `Terraform: private LAN + 4 machines` | creates the network and machines; prints a table of IPs at the end | 1–2 min |
| `Waiting for the machines` | first boot installs packages | 2–4 min |
| `Base`, `DNS`, `Resolvers`, `Backends`, `TLS`, `Edges` | configures each service; each line says `ok`, `changed` or `failed` | 1 min |
| `Verify` | 6 HTTPS requests from two clients, e.g. `balanced A=3 B=3` | seconds |

It ends with **`0 failed`** and **`All services up.`**, then opens the 5 terminals (Part 4).

If something fails, read the line marked `failed`, then see Part 6.

### Step 3.4. At the end of the session

```bash
make stop      # stops the 4 machines (saves AWS credit, keeps everything)
```

Next session: Steps 3.1 and 3.2, then `make`. It starts the machines again and picks up their new public IPs.

At the very end of the course:

```bash
make down      # deletes everything in AWS (asks you to type: yes)
```

---

## Part 4. The 5 terminals

```bash
make tmux      # (make already did this; use it to reopen)
```

```
┌──────────────────────────┬──────────────────────────┐
│ node-1  (DNS + client)   │ node-2  (edge)           │
├──────────────────────────┼──────────────────────────┤
│ node-3  (backend A)      │ node-4  (backend B +     │
│                          │          client)         │
├──────────────────────────┴──────────────────────────┤
│ YOU: your Mac, inside the project folder             │
└─────────────────────────────────────────────────────┘
```

- **The top four terminals are already logged in** to each machine. Click one and type, for example `cn-info`.
- **The bottom terminal is your Mac.** Run `make …` commands there.
- The prompt tells you where you are: `node-4 (backend B + client):~$` means you are on node-4.

The tool that draws these terminals is called **tmux**. Useful keys (press Ctrl-b, release, then the key):

| Keys | Does |
|---|---|
| click a pane | type in it (the mouse works) |
| `Ctrl-b` then `z` | make the current pane full screen / back |
| `Ctrl-b` then `1` | window "logs": every service log live |
| `Ctrl-b` then `2` | window "wire": live packets |
| `Ctrl-b` then `0` | back to the 5 terminals |
| `Ctrl-b` then `d` | leave tmux (everything keeps running; `make tmux` to return) |

Scroll back inside a pane: `Ctrl-b` then `[`, use the arrow keys or the mouse wheel, press `q` to exit.

**Shortcut commands on every machine** (type them in the node terminals):

| Command | What it shows |
|---|---|
| `cn-info` | this machine's IP, mask, gateway, MAC, DNS server, open ports |
| `cn-pingall` | pings the other three machines |
| `cn-probe 6` | 6 HTTPS requests and which backend answered each |
| `cn-follow` | live log of this machine's service (Ctrl-C to stop) |
| `cn-capture` (with sudo) | records one full request and explains every packet |
| `cn-diagnose` | checks DNS → IP → TCP → TLS → HTTP and says PASS/FAIL |

Each one is a short script in `node-bin/`. Open it to see exactly which Linux commands it runs.

---

## Part 5. Check that everything works (2 minutes)

Do this once after setup.

1. Bottom terminal: `make status`. Every node shows `active` for its services.
2. node-4 terminal: `dig app.team1.test`. You should see `SERVER: 10.0.1.11#53` and `app.team1.test. 30 IN A 10.0.1.12`.
3. node-4 terminal: `curl https://app.team1.test/api/status`. The JSON contains `"backend": "A"` or `"B"`. There is **no** certificate error, and we never use `-k`.
4. node-4 terminal: `cn-probe 6`. The backend alternates A, B, A, B…
5. Bottom terminal: `make scene SCENE=lb`. The demo engine types into the four terminals by itself. Press Enter at the end.

If all five work, you are ready for [`2-PHASE1-WALKTHROUGH.md`](2-PHASE1-WALKTHROUGH.md).

---

## Part 6. When something goes wrong

| What you see | What to do |
|---|---|
| `AWS credentials missing or expired` | Lab session ended. Do Steps 3.1 and 3.2 again, then `make`. |
| `node-N has no public IP (stopped?)` | The lab stopped the machines. Run `make`. |
| SSH hangs / `Operation timed out` | Your internet IP changed (other Wi-Fi). Run `make up`, which updates the firewall to your new IP. |
| A node terminal says `disconnected` | Click it and press Enter to reconnect. |
| A demo or experiment left things broken | `make restore` puts every service back. It is always safe. |
| `failed` lines during `make` | Run `make converge` once more. If it still fails, look at `.generated/converge.log`. |
| `VpcLimitExceeded: The maximum number of VPCs has been reached` | Your AWS account already has its maximum number of VPCs. In `settings.env` set `VPC_MODE=default` and run `make` again. The project then builds inside the account's default VPC and the machines get **172.31.250.11–14** instead of 10.0.1.11–14. Read every `10.0.1.x` in the guides as `172.31.250.x`. |
| Terraform errors, e.g. after the lab was **reset** | Delete `infra/terraform.tfstate*` and run `make` again. It rebuilds from scratch. |
| You are lost in tmux | `Ctrl-b` then `d`, then `make tmux`. |

---

## Part 7. Working as a team

- **Everyone can run their own complete copy.** Each student has their own AWS Academy Learner Lab, so each of you can do Parts 2–5 on your own Mac. This is the best way to practise for the viva.
- **For the review and the video, one laptop runs it**: the person whose lab is used. Others can still type in the tmux terminals on that laptop.
- **Share the code, not the secrets.** If you put the project on GitHub, keep the repo private. `.gitignore` already keeps out the generated SSH key (`.generated/`), certificates and Terraform state.
- **Never share** `~/.aws/credentials` or `.generated/cn-key.pem`.
- The design each member should be able to explain is in [`architecture.md`](architecture.md).

### What lives where

| Folder / file | What it is |
|---|---|
| `settings.env` | the only settings file (team, domain, TTL, phase) |
| `Makefile` | all commands; `make help` lists them |
| `infra/` | Terraform: network + 4 machines |
| `config/` | the real configuration files: `dnsmasq.conf`, `nginx-edge.conf`, `backend.py`, `backend.service` |
| `node-bin/` | the `cn-*` shortcut commands installed on the machines |
| `scripts/` | automation: `converge.sh` (setup), `live.sh` (demos), `form.sh` (form answers), `fault.sh` (practice faults) |
| `docs/` | these guides |
| `evidence/` | everything generated as proof (logs, captures, form answers) |
