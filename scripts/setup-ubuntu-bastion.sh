#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# setup-ubuntu-bastion.sh
#
# Runs the Ubuntu bastion setup (XFCE desktop, xrdp, Google Chrome and a hosts
# entry for the TFE FQDN) on the bastion VM over SSH. Use this when the VM was
# created with `ubuntu_bastion_run_setup_script = false`.
#
# It renders templates/ubuntu_bastion_setup.sh.tpl, so the steps are identical to
# the first-boot script Terraform would otherwise run.
#
# Run from the repo root:
#   bash tfe-azure/scripts/setup-ubuntu-bastion.sh
#
# Prerequisites:
#   - terraform, az, ssh, scp installed on your Mac
#   - `az login` already done (only needed to look up the TFE VM IP)
#   - the Ubuntu bastion already created: `terraform -chdir=tfe-azure/main apply`
#   - password login: set TF_VAR_ubuntu_bastion_admin_password (as in .env) to
#     avoid typing it, otherwise ssh prompts for it once
#
# Optional overrides (environment variables):
#   BASTION_IP      bastion public IP        (default: terraform output ubuntu_bastion_public_ip)
#   BASTION_USER    admin username           (default: bastionadmin)
#   TFE_FQDN        TFE hostname             (default: tfe.azure.example.com)
#   TFE_HOSTS_IP    IP the FQDN maps to      (default: first TFE VMSS instance private IP)
#   RESOURCE_GROUP  TFE resource group       (default: tfe-rg)
#   VMSS_NAME       TFE VMSS name            (default: em-tfe-vmss)
# -----------------------------------------------------------------------------
set -euo pipefail

# ---- Configuration — adjust if your values differ ----
RESOURCE_GROUP="${RESOURCE_GROUP:-tfe-rg}"
VMSS_NAME="${VMSS_NAME:-em-tfe-vmss}"
BASTION_USER="${BASTION_USER:-bastionadmin}"
TFE_FQDN="${TFE_FQDN:-tfe.azure.example.com}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../main"
TEMPLATE="$SCRIPT_DIR/../templates/ubuntu_bastion_setup.sh.tpl"
RENDERED="$(mktemp -t ubuntu-bastion-setup.XXXXXX)"
CONTROL_PATH="$(mktemp -u -t ubuntu-bastion-ssh.XXXXXX)"
ASKPASS=""

# ---- Colours ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[setup-ubuntu-bastion]${NC} $*"; }
warn() { echo -e "${YELLOW}[setup-ubuntu-bastion]${NC} $*"; }
die()  { echo -e "${RED}[setup-ubuntu-bastion] ERROR${NC} $*" >&2; exit 1; }

cleanup() {
  ssh -o ControlPath="$CONTROL_PATH" -O exit "$BASTION_USER@${BASTION_IP:-}" &>/dev/null || true
  rm -f "$RENDERED" "$ASKPASS"
}
trap cleanup EXIT

# ---- Checks ----
for cmd in terraform az ssh scp; do
  command -v "$cmd" &>/dev/null || die "'$cmd' is not installed."
done
[[ -f "$TEMPLATE" ]] || die "Template not found: $TEMPLATE"

# ---- Resolve bastion IP ----
if [[ -z "${BASTION_IP:-}" ]]; then
  log "Looking up bastion public IP from Terraform output..."
  BASTION_IP=$(terraform -chdir="$TERRAFORM_DIR" output -raw ubuntu_bastion_public_ip 2>/dev/null) \
    || die "Could not read 'ubuntu_bastion_public_ip'. Has the bastion been created? Or set BASTION_IP."
fi
[[ -n "$BASTION_IP" && "$BASTION_IP" != "null" ]] || die "Bastion IP is empty. Set BASTION_IP."
log "Bastion: $BASTION_USER@$BASTION_IP"

# ---- Resolve the IP the TFE FQDN maps to ----
if [[ -z "${TFE_HOSTS_IP:-}" ]]; then
  log "Looking up TFE VM private IP..."
  TFE_HOSTS_IP=$(az vmss nic list \
    --resource-group "$RESOURCE_GROUP" \
    --vmss-name "$VMSS_NAME" \
    --query "[0].ipConfigurations[0].privateIPAddress" \
    --output tsv 2>/dev/null) || die "Failed to get the TFE VM IP. Is 'az login' done? Or set TFE_HOSTS_IP."
fi
[[ -n "$TFE_HOSTS_IP" ]] || die "TFE VM IP is empty. Set TFE_HOSTS_IP."
log "Hosts entry: $TFE_HOSTS_IP $TFE_FQDN"

# ---- Render the template ----
sed \
  -e "s|\${tfe_fqdn}|$TFE_FQDN|g" \
  -e "s|\${tfe_hosts_ip}|$TFE_HOSTS_IP|g" \
  -e "s|\${admin_username}|$BASTION_USER|g" \
  "$TEMPLATE" > "$RENDERED"
if grep -q '\${[a-z_]*}' "$RENDERED"; then
  die "Unrendered template placeholders remain in $RENDERED."
fi

# ---- SSH options (one connection, reused, so the password is asked once) ----
SSH_OPTS=(-o StrictHostKeyChecking=no -o ConnectTimeout=15
          -o ControlMaster=auto -o ControlPersist=10m -o ControlPath="$CONTROL_PATH")

if [[ -n "${TF_VAR_ubuntu_bastion_admin_password:-}" ]]; then
  ASKPASS="$(mktemp -t ubuntu-bastion-askpass.XXXXXX)"
  printf '#!/bin/sh\nprintf "%%s\\n" "$TF_VAR_ubuntu_bastion_admin_password"\n' > "$ASKPASS"
  chmod 700 "$ASKPASS"
  export SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-:0}"
  SSH_OPTS+=(-o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1)
  log "Using password from TF_VAR_ubuntu_bastion_admin_password."
else
  warn "TF_VAR_ubuntu_bastion_admin_password is not set — ssh will prompt for the password."
fi

# ---- Connect and check outbound internet ----
log "Connecting..."
ssh "${SSH_OPTS[@]}" "$BASTION_USER@$BASTION_IP" "hostname" \
  || die "SSH login failed. Check the IP, the NSG allows your IP on port 22, and the password."

log "Checking outbound internet from the bastion..."
ssh "${SSH_OPTS[@]}" "$BASTION_USER@$BASTION_IP" \
  "curl -sI --max-time 15 https://dl.google.com | head -1" | grep -q "HTTP" \
  || die "The bastion has no outbound internet (https://dl.google.com unreachable). apt and Chrome downloads would fail. This needs a network fix, not a script fix."

# ---- Copy and run ----
log "Copying setup script..."
scp "${SSH_OPTS[@]}" "$RENDERED" "$BASTION_USER@$BASTION_IP:/tmp/ubuntu-bastion-setup.sh" \
  || die "Failed to copy the script."

log "Running setup (about 5-10 minutes). Log: /var/log/ubuntu-bastion-setup.log on the VM."
echo ""
# sudo on the bastion needs the user's password. With the password in the
# environment it is piped to `sudo -S` over stdin (never on a command line);
# otherwise a tty is allocated so sudo can prompt.
if [[ -n "${TF_VAR_ubuntu_bastion_admin_password:-}" ]]; then
  printf '%s\n' "$TF_VAR_ubuntu_bastion_admin_password" \
    | ssh "${SSH_OPTS[@]}" "$BASTION_USER@$BASTION_IP" \
        "sudo -S -p '' bash /tmp/ubuntu-bastion-setup.sh" \
    || die "Setup failed. Check /var/log/ubuntu-bastion-setup.log on the VM. The script is safe to re-run: bash tfe-azure/scripts/setup-ubuntu-bastion.sh"
else
  ssh -t "${SSH_OPTS[@]}" "$BASTION_USER@$BASTION_IP" \
    "sudo bash /tmp/ubuntu-bastion-setup.sh" \
    || die "Setup failed. Check /var/log/ubuntu-bastion-setup.log on the VM. The script is safe to re-run: bash tfe-azure/scripts/setup-ubuntu-bastion.sh"
fi

echo ""
log "Checking xrdp..."
ssh "${SSH_OPTS[@]}" "$BASTION_USER@$BASTION_IP" "systemctl is-active xrdp" \
  | grep -qx "active" || die "xrdp is not active. Check /var/log/ubuntu-bastion-setup.log on the VM."

log "Done. Connect with Microsoft Remote Desktop to $BASTION_IP as $BASTION_USER,"
log "then open Chrome at https://$TFE_FQDN"
