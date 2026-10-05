# ─────────────────────────────────────────────────────────────────────
#  CN Project – Private Network Service Platform on AWS (Academy)
#
#    make            build everything (Terraform + services) and open the 5 terminals
#    make live       run the full live demonstration in those terminals
#    make help       all commands
# ─────────────────────────────────────────────────────────────────────
SHELL := /bin/bash
SC := ./scripts

# Optional:  AUTO=1 (no pauses)  FROM=5 (start at scene 5)  ONLY=ext_b  PACE=0.5
#            FAULT=edge-wrong-cert   YES=1 (skip confirmation for make down)
export AUTO FROM ONLY PACE YES

.DEFAULT_GOAL := all

##@ Start here
all: up tmux ## Build/repair everything, then open the 5-terminal dashboard
up: ## Terraform (LAN + 4 machines) → wait for boot → configure all services (idempotent)
	@$(SC)/infra.sh up
tmux: ## Open the dashboard: 4 server terminals + your terminal (+ logs, wire windows)
	@$(SC)/tmux.sh
creds: ## Paste AWS Academy credentials (AWS Details → AWS CLI) into ~/.aws/credentials
	@$(SC)/infra.sh creds

##@ Live demonstration (typed into the 4 server terminals)
live: ## Full final demo, brief Section 8 order (13 scenes)
	@$(SC)/live.sh run final
live-p1: ## Phase 1 review: Tasks A–G + all 5 required failure demos (13 scenes)
	@$(SC)/live.sh run p1
live-p2: ## Phase 2 review: Extensions A–F (6 scenes)
	@$(SC)/live.sh run p2
scene: ## One scene:  make scene SCENE=lb   (see: make scenes)
	@[ -n "$(SCENE)" ] || { echo "usage: make scene SCENE=<name>   (make scenes lists them)"; exit 1; }
	@$(SC)/live.sh run $(SCENE)
scenes: ## List every scene name
	@echo "Phase 1: topology lan dns https headers lb cache capture fail_dns_server fail_dns_record fail_one_backend fail_both_backends fail_wrong_port"
	@echo "Phase 2: ext_a ext_b ext_c ext_d ext_e ext_f     Final extra: viva"

##@ Submission form
form: ## Run every Phase 1 form command (A1–D3) on the real machines → evidence/form/FORM.md
	@$(SC)/form.sh

##@ Troubleshooting practice (Extension F)
fault: ## Inject a hidden random fault (or FAULT=name); diagnose with cn-diagnose
	@$(SC)/fault.sh inject $(FAULT)
fault-list: ## Show the available practice faults
	@$(SC)/fault.sh list
fault-reveal: ## Reveal the injected fault
	@$(SC)/fault.sh reveal
restore: ## Put everything back to the known-good state (undoes any demo or fault)
	@$(SC)/converge.sh restore

##@ Everyday
converge: ## Re-apply the service configuration only (no Terraform)
	@$(SC)/converge.sh all
status: ## Machines, IPs and service states
	@$(SC)/infra.sh status
ssh: ## SSH into one machine:  make ssh N=2
	@ssh -F .generated/ssh_config node-$(N)
report: ## Build evidence/REPORT.md from all checks and evidence files
	@$(SC)/report.sh
stop: ## Stop the 4 instances (keeps everything, saves credits)
	@$(SC)/infra.sh stop
start: ## Start them again (then: make converge)
	@$(SC)/infra.sh start
down: ## Destroy everything in AWS (asks for confirmation)
	@tmux kill-session -t cn 2>/dev/null || true
	@$(SC)/infra.sh down
tmux-kill: ## Close the dashboard
	@tmux kill-session -t cn 2>/dev/null || true

help:
	@awk 'BEGIN{FS=":.*## "} /^##@/{printf "\n\033[1m%s\033[0m\n", substr($$0,5); next} \
	  /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo

.PHONY: form all up tmux creds live live-p1 live-p2 scene scenes fault fault-list fault-reveal restore \
        converge status ssh report stop start down tmux-kill help
