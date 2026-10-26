#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run-tf-demo-workspace-config.sh
#
# Runs the Terraform in tf-demo-workspace-config/ from your Mac against the TFE
# instance, which is not reachable directly. It opens an SSH SOCKS proxy through
# the Ubuntu bastion (the bastion can resolve and reach TFE), points Terraform
# at it, runs the command you ask for, then closes the proxy.
#
# Run from the repo root:
#   export TFE_TOKEN=<your-tfe-user-api-token>
#   bash tfe-azure/scripts/run-tf-demo-workspace-config.sh            # init + plan
#   bash tfe-azure/scripts/run-tf-demo-workspace-config.sh apply      # init + apply
#   bash tfe-azure/scripts/run-tf-demo-workspace-config.sh destroy    # init + destroy
#
# Prerequisites:
#   - terraform (>= 1.11), ssh, curl, lsof installed on your Mac
#   - the Ubuntu bastion exists and allows SSH (22) from your IP
#   - tf-demo-workspace-config/terraform.tfvars exists with a real tfe_organization
#   - TFE_TOKEN is a user API token (User Settings > Tokens), NOT the IACT token
#   - TF_VAR_ubuntu_bastion_admin_password set (as in .env) to avoid a password
#     prompt; otherwise ssh prompts for it once
#
# Optional overrides (environment variables):
#   BASTION_IP     bastion public IP     (default: terraform output ubuntu_bastion_public_ip)
#   BASTION_USER   admin username        (default: bastionadmin)
#   PROXY_PORT     local SOCKS port      (default: 1080)
#   TFE_HOSTNAME   TFE hostname          (default: tfe.azure.example.com)
# -----------------------------------------------------------------------------
set -euo pipefail

# ---- Configuration — adjust if your values differ ----
BASTION_USER="${BASTION_USER:-bastionadmin}"
PROXY_PORT="${PROXY_PORT:-1080}"
TFE_HOSTNAME="${TFE_HOSTNAME:-tfe.azure.example.com}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_MAIN_DIR="$SCRIPT_DIR/../main"
CONFIG_DIR="$SCRIPT_DIR/../tf-demo-workspace-config"
ACTION="${1:-plan}"
PROXY_STARTED=""
ASKPASS=""
CONTROL_PATH="$(mktemp -u -t tf-demo-proxy.XXXXXX)"

# ---- Colours ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[tf-demo]${NC} $*"; }
warn() { echo -e "${YELLOW}[tf-demo]${NC} $*"; }
die()  { echo -e "${RED}[tf-demo] ERROR${NC} $*" >&2; exit 1; }

cleanup() {
  if [[ -n "$PROXY_STARTED" ]]; then
    log "Closing SOCKS proxy..."
    ssh -o ControlPath="$CONTROL_PATH" -O exit "$BASTION_USER@${BASTION_IP:-}" &>/dev/null || true
  fi
  [[ -z "$ASKPASS" ]] || rm -f "$ASKPASS"
}
trap cleanup EXIT

# ---- Checks ----
case "$ACTION" in
  plan|apply|destroy) ;;
  *) die "Unknown action '$ACTION'. Use: plan (default), apply or destroy." ;;
esac

for cmd in terraform ssh curl lsof; do
  command -v "$cmd" &>/dev/null || die "'$cmd' is not installed."
done

[[ -d "$CONFIG_DIR" ]] || die "Config directory not found: $CONFIG_DIR"
[[ -f "$CONFIG_DIR/terraform.tfvars" ]] \
  || die "$CONFIG_DIR/terraform.tfvars not found. Copy terraform.tfvars.example and edit it."
if grep -q '<YOUR-ORG-NAME>' "$CONFIG_DIR/terraform.tfvars"; then
  die "Set tfe_organization in $CONFIG_DIR/terraform.tfvars (it still has <YOUR-ORG-NAME>)."
fi
: "${TFE_TOKEN:?ERROR: TFE_TOKEN is not set. Create a user API token in the TFE UI (User Settings > Tokens), then: export TFE_TOKEN=<token>}"

# ---- Resolve bastion IP ----
if [[ -z "${BASTION_IP:-}" ]]; then
  log "Looking up bastion public IP from Terraform output..."
  BASTION_IP=$(terraform -chdir="$TERRAFORM_MAIN_DIR" output -raw ubuntu_bastion_public_ip 2>/dev/null) \
    || die "Could not read 'ubuntu_bastion_public_ip'. Has the bastion been created? Or set BASTION_IP."
fi
[[ -n "$BASTION_IP" && "$BASTION_IP" != "null" ]] || die "Bastion IP is empty. Set BASTION_IP."
log "Bastion: $BASTION_USER@$BASTION_IP"

# ---- Open the SOCKS proxy ----
if lsof -nP -iTCP:"$PROXY_PORT" -sTCP:LISTEN &>/dev/null; then
  warn "Port $PROXY_PORT is already in use by:"
  lsof -nP -iTCP:"$PROXY_PORT" -sTCP:LISTEN
  die "Free port $PROXY_PORT (for example: pkill -f 'ssh -f -N -D $PROXY_PORT') or set PROXY_PORT=<other port>."
fi

SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=15
          -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes
          -o ControlMaster=yes -o ControlPath="$CONTROL_PATH")

if [[ -n "${TF_VAR_ubuntu_bastion_admin_password:-}" ]]; then
  ASKPASS="$(mktemp -t tf-demo-askpass.XXXXXX)"
  printf '#!/bin/sh\nprintf "%%s\\n" "$TF_VAR_ubuntu_bastion_admin_password"\n' > "$ASKPASS"
  chmod 700 "$ASKPASS"
  export SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-:0}"
  SSH_OPTS+=(-o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1)
  log "Using password from TF_VAR_ubuntu_bastion_admin_password."
else
  warn "TF_VAR_ubuntu_bastion_admin_password is not set — ssh will prompt for the password."
fi

log "Opening SOCKS proxy on 127.0.0.1:$PROXY_PORT via the bastion..."
ssh -f -N -D "$PROXY_PORT" "${SSH_OPTS[@]}" "$BASTION_USER@$BASTION_IP" \
  || die "Could not open the SSH proxy. Check the IP, that the NSG allows your IP on port 22, and the password."
PROXY_STARTED=1

# ---- Verify TFE is reachable through the proxy ----
log "Checking TFE through the proxy..."
HEALTH=$(curl -sk --max-time 20 --socks5-hostname "127.0.0.1:$PROXY_PORT" \
  "https://$TFE_HOSTNAME/_health_check" || true)
[[ "$HEALTH" == "OK" ]] \
  || die "TFE did not answer 'OK' on /_health_check through the bastion (got: '${HEALTH:-nothing}'). Check that the bastion has the hosts entry for $TFE_HOSTNAME (scripts/setup-ubuntu-bastion.sh)."
log "TFE is reachable."

# ---- Run Terraform ----
# Terraform (Go) honours HTTPS_PROXY but ignores ALL_PROXY. socks5h makes the
# bastion resolve the TFE hostname, so no /etc/hosts change is needed on this Mac.
export HTTPS_PROXY="socks5h://127.0.0.1:$PROXY_PORT"
export NO_PROXY="localhost,127.0.0.1"
export TFE_TOKEN

cd "$CONFIG_DIR"

# `init` downloads the tfe provider from the internet. Do that without the
# proxy, which only needs to carry traffic to TFE.
log "terraform init (direct, no proxy)..."
HTTPS_PROXY="" terraform init -input=false

case "$ACTION" in
  plan)
    log "terraform plan..."
    terraform plan -input=false
    log "Plan only. To create the resources: bash tfe-azure/scripts/run-tf-demo-workspace-config.sh apply"
    ;;
  apply)
    log "terraform apply..."
    terraform apply
    ;;
  destroy)
    log "terraform destroy..."
    terraform destroy
    ;;
esac

log "Done."
