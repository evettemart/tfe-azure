#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# deploy-tfe.sh
#
# This script is only required when using hashicorp images as the startup script is marked
# complete and there the custom data script doesnt get copied over
# Extracts the TFE startup script from Terraform state, copies it to the TFE
# VM via the Azure Bastion tunnel, and executes it.
#
# Run from the repo root:
#   bash tfe-azure/scripts/deploy-tfe.sh
#
# Prerequisites:
#   - terraform, az, jq, ssh, scp installed on your Mac
#   - `az login` already done
#   - `terraform -chdir=tfe-azure/main apply` already completed
#   - SSH private key available — set via: export SSH_KEY=~/.ssh/<private-key>
# -----------------------------------------------------------------------------
set -euo pipefail

# ---- Configuration — adjust if your values differ ----
RESOURCE_GROUP="tfe-rg"
NETWORKING_RG="tfe-networking-rg"
BASTION_NAME="tfe-bastion"
VMSS_NAME="em-tfe-vmss"
VM_ADMIN="tfeadmin"
SSH_KEY="${SSH_KEY:?ERROR: SSH_KEY environment variable is not set. Export it before running: export SSH_KEY=~/.ssh/<private-key>}"
TUNNEL_PORT="${TUNNEL_PORT:-2222}"
TERRAFORM_DIR="$(cd "$(dirname "$0")/../main" && pwd)"
SCRIPT_TMP="/tmp/tfe-init.sh"

# ---- Colours ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[deploy-tfe]${NC} $*"; }
warn() { echo -e "${YELLOW}[deploy-tfe]${NC} $*"; }
die()  { echo -e "${RED}[deploy-tfe] ERROR${NC} $*" >&2; exit 1; }

# ---- Checks ----
for cmd in terraform az jq ssh scp; do
  command -v "$cmd" &>/dev/null || die "'$cmd' is not installed."
done

[[ -f "$SSH_KEY" ]] || die "SSH key not found at $SSH_KEY. Set SSH_KEY env var to override."

# ---- Get VM private IP ----
log "Looking up TFE VM private IP..."
VM_IP=$(az vmss nic list \
  --resource-group "$RESOURCE_GROUP" \
  --vmss-name "$VMSS_NAME" \
  --query "[0].ipConfigurations[0].privateIPAddress" \
  --output tsv 2>/dev/null) || die "Failed to get VM IP. Is the VMSS running?"

[[ -n "$VM_IP" ]] || die "No VM IP found. Is the VMSS running?"
log "VM IP: $VM_IP"

# ---- Extract startup script from Terraform state ----
log "Extracting startup script from Terraform state..."
cd "$TERRAFORM_DIR"

terraform show -json | \
  jq -r '.values.root_module.child_modules[].resources[]
    | select(.type == "azurerm_linux_virtual_machine_scale_set")
    | .values.custom_data' | \
  base64 -d > "$SCRIPT_TMP" || die "Failed to extract script from Terraform state. Has 'terraform apply' been run?"

# Verify it looks like a bash script
head -1 "$SCRIPT_TMP" | grep -q "bash\|cloud-boothook" || \
  die "Extracted script doesn't look right. Check Terraform state."

log "Script extracted to $SCRIPT_TMP ($(wc -l < "$SCRIPT_TMP") lines)"

# ---- Open Bastion tunnel ----
log "Opening Bastion tunnel on port $TUNNEL_PORT..."
az network bastion tunnel \
  --name "$BASTION_NAME" \
  --resource-group "$NETWORKING_RG" \
  --target-ip-address "$VM_IP" \
  --resource-port 22 \
  --port "$TUNNEL_PORT" &
TUNNEL_PID=$!

# Ensure tunnel is killed on exit
trap 'log "Closing tunnel..."; kill $TUNNEL_PID 2>/dev/null || true' EXIT

log "Waiting for tunnel to be ready..."
sleep 8

# Verify tunnel is up
ssh -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    -o BatchMode=yes \
    -p "$TUNNEL_PORT" \
    -i "$SSH_KEY" \
    "$VM_ADMIN@127.0.0.1" \
    "echo tunnel-ok" &>/dev/null || die "Tunnel not reachable. Check bastion SKU (needs Standard + ip_connect_enabled)."

log "Tunnel is ready."

# ---- Copy script to VM ----
log "Copying startup script to VM..."
scp -o StrictHostKeyChecking=no \
    -P "$TUNNEL_PORT" \
    -i "$SSH_KEY" \
    "$SCRIPT_TMP" \
    "$VM_ADMIN@127.0.0.1:/tmp/tfe-init.sh" || die "Failed to copy script to VM."

# ---- Run script on VM ----
log "Running startup script on VM (this takes 10-15 minutes)..."
log "Streaming logs — look for '[INFO] TFE custom_data script finished successfully!'"
echo ""

ssh -o StrictHostKeyChecking=no \
    -p "$TUNNEL_PORT" \
    -i "$SSH_KEY" \
    "$VM_ADMIN@127.0.0.1" \
    "sudo find /etc/apt/sources.list.d/ -name '*artifactory*' -delete 2>/dev/null || true && \
     sudo bash /tmp/tfe-init.sh 2>&1 | sudo tee /var/log/tfe-cloud-init.log"

echo ""
log "Script completed. TFE should now be starting up."
log "Check health: ssh -p $TUNNEL_PORT -i $SSH_KEY $VM_ADMIN@127.0.0.1 'curl -ksfS https://localhost/_health_check'"
