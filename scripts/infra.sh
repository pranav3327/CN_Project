#!/usr/bin/env bash
# Infrastructure lifecycle: credentials, Terraform, waiting for the machines.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

TFDIR="$ROOT/infra"
TF="$(command -v terraform || command -v tofu || true)"

export TF_IN_AUTOMATION=1
export TF_VAR_region="$REGION"
export TF_VAR_team="$TEAM"
export TF_VAR_instance_type="$INSTANCE_TYPE"
export TF_VAR_key_name="${KEY_NAME:-}"
export TF_VAR_key_path="${KEY_PATH:-}"
export TF_VAR_vpc_mode="${VPC_MODE:-new}"

tf() { (cd "$TFDIR" && "$TF" "$@"); }

# ---- checks -------------------------------------------------------------------
cmd_preflight() {
  section "Preflight"
  [ -n "$TF" ] || die "terraform not found – macOS: brew tap hashicorp/tap && brew install hashicorp/tap/terraform"
  report ok laptop "$(basename "$TF") $("$TF" version | head -1 | awk '{print $2}')"
  command -v aws  >/dev/null || die "aws CLI not found – macOS: brew install awscli"
  command -v ssh  >/dev/null || die "ssh not found"
  command -v perl >/dev/null || die "perl not found"
  command -v tmux >/dev/null || report skip laptop "tmux not installed (needed for make tmux / make live: brew install tmux)"
  case "$DOMAIN" in *.test) ;; *) die "settings.env: DOMAIN must end in .test (got $DOMAIN)" ;; esac
  local who
  if ! who="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)"; then
    die "AWS credentials missing or expired (AWS Academy sessions last ~4h) – run: make creds"
  fi
  report ok aws "$who"
  if [ -n "${KEY_NAME:-}" ]; then
    [ -f "$(eval echo "${KEY_PATH:-}")" ] || die "settings.env: KEY_PATH '$KEY_PATH' not found for KEY_NAME=$KEY_NAME"
  fi
}

# ---- AWS Academy credentials ----------------------------------------------------
cmd_creds() {
  local text="" clip=""
  if command -v pbpaste >/dev/null; then clip="$(pbpaste 2>/dev/null || true)"
  elif command -v wl-paste >/dev/null; then clip="$(wl-paste 2>/dev/null || true)"
  elif command -v xclip >/dev/null; then clip="$(xclip -o -selection clipboard 2>/dev/null || true)"
  fi
  if printf '%s' "$clip" | grep -q aws_session_token; then
    echo "Found AWS credentials in the clipboard – using them."
    text="$clip"
  else
    echo "AWS Academy → Learner Lab → 'AWS Details' → AWS CLI: Show."
    echo "Paste the whole [default] block here, then press Ctrl-D:"
    text="$(cat)"
  fi
  printf '%s' "$text" | grep -q aws_access_key_id || die "that does not look like an AWS credentials block"
  mkdir -p ~/.aws
  [ -f ~/.aws/credentials ] && cp ~/.aws/credentials ~/.aws/credentials.bak
  printf '%s\n' "$text" > ~/.aws/credentials
  chmod 600 ~/.aws/credentials
  if ! grep -q '^region' ~/.aws/config 2>/dev/null; then
    printf '[default]\nregion = %s\n' "$REGION" >> ~/.aws/config
  fi
  aws sts get-caller-identity --query Arn --output text && echo "credentials OK (old file saved as ~/.aws/credentials.bak)"
}

# ---- terraform ------------------------------------------------------------------
tf_init() {
  if [ ! -d "$TFDIR/.terraform" ] || [ "$TFDIR/versions.tf" -nt "$TFDIR/.terraform" ]; then
    tf init -input=false -upgrade >/dev/null && touch "$TFDIR/.terraform"
  fi
}

cmd_apply() {   # create / update / start the machines (idempotent)
  cmd_preflight
  section "Terraform: private LAN + 4 machines (state=${1:-running})"
  tf_init
  mkdir -p "$GEN"
  local tflog="$GEN/terraform-apply.log"
  if tf apply -input=false -auto-approve -no-color -compact-warnings -var "instance_state=${1:-running}" 2>&1 \
      | tee "$tflog" | grep --line-buffered -E '^(Apply complete|Plan:|No changes|Error)|: (Creating|Destroying|Creation complete|Modifications complete)'; then :; fi
  if ! grep -q '^Apply complete' "$tflog"; then
    sed -n '/^Error:/,$p' "$tflog" | head -20
    if grep -q VpcLimitExceeded "$tflog"; then
      echo
      echo "${B}This AWS account already has the maximum number of VPCs in $REGION:${RST}"
      aws ec2 describe-vpcs --region "$REGION" \
        --query 'Vpcs[].[VpcId,CidrBlock,IsDefault,Tags[?Key==`Name`]|[0].Value]' --output table 2>/dev/null || true
      echo "Fix (pick one):"
      echo "  1) Recommended: in settings.env set  VPC_MODE=default  and run make again."
      echo "     The project then uses a new subnet 172.31.250.0/24 inside the default VPC (IPs .11-.14 as usual)."
      echo "  2) Delete unused NON-default VPCs (AWS console → VPC → Your VPCs → Actions → Delete VPC), then make."
    fi
    die "terraform apply failed – full log: $tflog"
  fi
  load_cluster
  tf output -json nodes | perl -MJSON::PP -e '
    my $n = decode_json(join "", <STDIN>);
    printf "  %-7s private %-11s public %-15s %s\n", $_, $n->{$_}{private_ip}, $n->{$_}{public_ip} || "-", $n->{$_}{state}
      for sort keys %$n;'
}

cmd_wait() {   # until SSH works and cloud-init has finished on every machine
  need_cluster
  section "Waiting for the machines (SSH + first-boot setup)"
  local n
  for n in $NODES; do
    (
      local i=0 st=""
      while [ $i -lt 60 ]; do
        if st="$(on_q "$n" 'cloud-init status --wait >/dev/null 2>&1; cloud-init status | awk "{print \$2}"')"; then
          [ -n "$st" ] && break
        fi
        i=$((i + 1)); sleep 5
      done
      case "$st" in
        done)     report ok "$n" "ready" ;;
        degraded) report ok "$n" "ready (cloud-init reported warnings)" ;;
        *)        report failed "$n" "not ready after 5 min (cloud-init: ${st:-no ssh})" ;;
      esac
    ) &
  done
  wait
}

cmd_up() {   # the whole thing, idempotent
  cmd_apply running
  cmd_wait
  "$ROOT/scripts/converge.sh" all
}

cmd_stop()  { cmd_apply stopped; }
cmd_start() { cmd_apply running; cmd_wait; }

cmd_down() {
  if [ "${YES:-}" != 1 ]; then
    printf 'Destroy ALL project resources in AWS (VPC, 4 instances, key)? type yes: '
    local a; read -r a; [ "$a" = yes ] || { echo "cancelled"; exit 0; }
  fi
  cmd_preflight
  tf_init
  tf destroy -input=false -auto-approve -compact-warnings | tail -3
  rm -rf "$GEN"
  echo "all AWS resources removed"
}

cmd_output() { tf output; }

cmd_status() {
  need_cluster
  printf '%-7s %-11s %-15s %-9s %-9s %-9s %s\n' machine private public dnsmasq nginx backend resolver
  local n
  for n in $NODES; do
    printf '%-7s %-11s %-15s ' "$n" "$(ip_of "$n")" "$(eval echo "\${NODE${n#node-}_PUB}")"
    on_q "$n" 'b=-; [ -f /etc/cn/cn.env ] && . /etc/cn/cn.env && [ -n "$BACKEND_UNIT" ] && b=$(systemctl is-active $BACKEND_UNIT)
      printf "%-9s %-9s %-9s %s\n" "$(systemctl is-active dnsmasq 2>/dev/null || true)" "$(systemctl is-active nginx 2>/dev/null || true)" "$b" "$(resolvectl dns 2>/dev/null | head -1 | cut -d: -f2)"' \
      || echo "unreachable"
  done
  [ -f "$GEN/last-fault" ] && echo "practice fault active (make fault-reveal / make restore)"
  return 0
}

dispatch "$@"
