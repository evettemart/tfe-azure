#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# run-test-workspace.sh
#
# Copies the test-workspace Terraform config to the TFE VM via the Azure
# Bastion tunnel and runs terraform init + apply on the VM.
#
# Run from the repo root:
#   export SSH_KEY=~/.ssh/<private-key>
#   export TFE_ORG=<your-org-name>
#   export TFE_TOKEN=<your-tfe-user-api-token>
#   bash tfe-azure/scripts/run-test-workspace.sh
#
# How to get a TFE_TOKEN:
#   1. Log in to https://tfe.azure.example.com in a browser
#   2. Go to User Settings → Tokens → Create an API token
#   3. export TFE_TOKEN=<the token value>
#
# Prerequisites:
#   - az, ssh, scp installed on your Mac
#   - az login already done
#   - TFE is running (deploy-tfe.sh has been run successfully)
#   - SSH_KEY env var set to your private key path
#   - TFE_ORG env var set to your TFE organisation name
#   - TFE_TOKEN env var set to a TFE user API token
# -----------------------------------------------------------------------------
set -euo pipefail

# ---- Configuration ----
RESOURCE_GROUP="tfe-rg"
NETWORKING_RG="tfe-networking-rg"
BASTION_NAME="tfe-bastion"
VMSS_NAME="em-tfe-vmss"
VM_ADMIN="tfeadmin"
TFE_HOSTNAME="tfe.azure.example.com"
TUNNEL_PORT="${TUNNEL_PORT:-2222}"
WORKSPACE_NAME="test-random-string"
LOCAL_WORKSPACE_DIR="$(cd "$(dirname "$0")/../test-workspace" && pwd)"

SSH_KEY="${SSH_KEY:?ERROR: SSH_KEY is not set. Run: export SSH_KEY=~/.ssh/<private-key>}"
TFE_ORG="${TFE_ORG:?ERROR: TFE_ORG is not set. Run: export TFE_ORG=<your-org-name>}"
TFE_TOKEN="${TFE_TOKEN:?ERROR: TFE_TOKEN is not set. Get one from https://tfe.azure.example.com → User Settings → Tokens, then: export TFE_TOKEN=<token>}"

# ---- Colours ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[run-test]${NC} $*"; }
warn() { echo -e "${YELLOW}[run-test]${NC} $*"; }
die()  { echo -e "${RED}[run-test] ERROR${NC} $*" >&2; exit 1; }

# ---- Checks ----
for cmd in az ssh scp; do
  command -v "$cmd" &>/dev/null || die "'$cmd' is not installed."
done

[[ -f "$SSH_KEY" ]] || die "SSH key not found at $SSH_KEY"
[[ -d "$LOCAL_WORKSPACE_DIR" ]] || die "test-workspace directory not found at $LOCAL_WORKSPACE_DIR"

# ---- Get VM private IP ----
log "Looking up TFE VM private IP..."
VM_IP=$(az vmss nic list \
  --resource-group "$RESOURCE_GROUP" \
  --vmss-name "$VMSS_NAME" \
  --query "[0].ipConfigurations[0].privateIPAddress" \
  --output tsv 2>/dev/null) || die "Failed to get VM IP. Is the VMSS running?"

[[ -n "$VM_IP" ]] || die "No VM IP found. Is the VMSS running?"
log "VM IP: $VM_IP"

# ---- Open Bastion tunnel ----
log "Opening Bastion tunnel on port $TUNNEL_PORT..."
az network bastion tunnel \
  --name "$BASTION_NAME" \
  --resource-group "$NETWORKING_RG" \
  --target-ip-address "$VM_IP" \
  --resource-port 22 \
  --port "$TUNNEL_PORT" &
TUNNEL_PID=$!

trap 'log "Closing tunnel..."; kill $TUNNEL_PID 2>/dev/null || true' EXIT

log "Waiting for tunnel to be ready..."
sleep 8

ssh -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 \
    -o BatchMode=yes \
    -p "$TUNNEL_PORT" \
    -i "$SSH_KEY" \
    "$VM_ADMIN@127.0.0.1" \
    "echo tunnel-ok" &>/dev/null || die "Tunnel not reachable."

log "Tunnel is ready."

# ---- Install / pin Terraform on VM ----
# TFE 1.0.1 is incompatible with Terraform CLI >= 1.10 (policy evaluation API
# change). Pin to 1.9.8 which is the latest 1.9.x release and works correctly.
TF_REQUIRED_VERSION="1.9.8"
log "Checking Terraform version on VM (need $TF_REQUIRED_VERSION)..."
TF_CURRENT=$(ssh -o StrictHostKeyChecking=no \
  -p "$TUNNEL_PORT" -i "$SSH_KEY" "$VM_ADMIN@127.0.0.1" \
  "terraform version 2>/dev/null | head -1 | grep -oP '[\d]+\.[\d]+\.[\d]+' || echo 'none'")

if [[ "$TF_CURRENT" == "$TF_REQUIRED_VERSION" ]]; then
  log "Terraform $TF_REQUIRED_VERSION already installed — skipping."
else
  log "Installing Terraform $TF_REQUIRED_VERSION (current: $TF_CURRENT)..."
  ssh -o StrictHostKeyChecking=no \
      -p "$TUNNEL_PORT" -i "$SSH_KEY" "$VM_ADMIN@127.0.0.1" \
      "curl -fsSL https://releases.hashicorp.com/terraform/${TF_REQUIRED_VERSION}/terraform_${TF_REQUIRED_VERSION}_linux_amd64.zip -o /tmp/terraform.zip && \
       sudo unzip -o /tmp/terraform.zip -d /usr/local/bin/ && \
       sudo chmod +x /usr/local/bin/terraform && \
       rm /tmp/terraform.zip && \
       terraform version"
  log "Terraform $TF_REQUIRED_VERSION installed."
fi

# ---- Ensure TFE hostname resolves on the VM ----
log "Ensuring $TFE_HOSTNAME resolves on VM..."
ssh -o StrictHostKeyChecking=no \
    -p "$TUNNEL_PORT" -i "$SSH_KEY" "$VM_ADMIN@127.0.0.1" \
    "grep -q '$TFE_HOSTNAME' /etc/hosts || echo '127.0.0.1 $TFE_HOSTNAME' | sudo tee -a /etc/hosts"

# ---- Trust TFE CA bundle on the VM ----
# The TFE CA bundle is written to /etc/tfe/tls/bundle.pem by the startup script.
# Install it into the OS trust store so that `terraform login` and curl trust TFE's cert.
log "Trusting TFE CA bundle on VM..."
ssh -o StrictHostKeyChecking=no \
    -p "$TUNNEL_PORT" -i "$SSH_KEY" "$VM_ADMIN@127.0.0.1" \
    'if [[ -f /etc/tfe/tls/bundle.pem ]]; then
       sudo cp /etc/tfe/tls/bundle.pem /usr/local/share/ca-certificates/tfe-ca.crt
       sudo update-ca-certificates
       echo "CA bundle installed."
     else
       echo "WARNING: /etc/tfe/tls/bundle.pem not found — skipping CA trust install."
     fi'

# ---- Copy test workspace to VM ----
log "Copying test-workspace to VM..."
ssh -o StrictHostKeyChecking=no \
    -p "$TUNNEL_PORT" -i "$SSH_KEY" "$VM_ADMIN@127.0.0.1" \
    "rm -rf /home/$VM_ADMIN/test-workspace && mkdir -p /home/$VM_ADMIN/test-workspace"

scp -o StrictHostKeyChecking=no \
    -P "$TUNNEL_PORT" -i "$SSH_KEY" \
    -r "$LOCAL_WORKSPACE_DIR/." \
    "$VM_ADMIN@127.0.0.1:/home/$VM_ADMIN/test-workspace/"

# ---- Update org name in main.tf ----
log "Setting TFE organisation to '$TFE_ORG'..."
ssh -o StrictHostKeyChecking=no \
    -p "$TUNNEL_PORT" -i "$SSH_KEY" "$VM_ADMIN@127.0.0.1" \
    "sed -i 's/<YOUR-ORG-NAME>/$TFE_ORG/' /home/$VM_ADMIN/test-workspace/main.tf"

# ---- Write Terraform credentials file on VM ----
# Write the JSON directly via printf on the Mac side — no shell variable
# expansion on the VM needed, so there are no quoting issues.
log "Writing Terraform credentials file on VM..."
printf '{"credentials":{"%s":{"token":"%s"}}}\n' "$TFE_HOSTNAME" "$TFE_TOKEN" \
  | ssh -o StrictHostKeyChecking=no \
        -p "$TUNNEL_PORT" -i "$SSH_KEY" "$VM_ADMIN@127.0.0.1" \
        "mkdir -p ~/.terraform.d && cat > ~/.terraform.d/credentials.tfrc.json" \
  || die "Failed to write credentials file on VM."
log "Credentials file written."

# ---- Run terraform init and apply ----
log "Running terraform init..."
ssh -o StrictHostKeyChecking=no \
    -p "$TUNNEL_PORT" -i "$SSH_KEY" "$VM_ADMIN@127.0.0.1" \
    "cd /home/$VM_ADMIN/test-workspace && terraform init"

log "Running terraform apply..."
ssh -o StrictHostKeyChecking=no \
    -p "$TUNNEL_PORT" -i "$SSH_KEY" "$VM_ADMIN@127.0.0.1" \
    "cd /home/$VM_ADMIN/test-workspace && terraform apply -auto-approve"

log "Done. Check the TFE UI at https://$TFE_HOSTNAME for the run results."
log "Workspace: $WORKSPACE_NAME | Org: $TFE_ORG"
