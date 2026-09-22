#!/usr/bin/env bash
# bootstrap.sh — Idempotent bootstrap for TFE prerequisites.
# Safe to re-run: skips already-existing resources, always regenerates certs
# and updates Key Vault secrets.
#
# Run this BEFORE `terraform apply`.
# Usage: ./scripts/bootstrap.sh

set -euo pipefail

#------------------------------------------------------------------------------
# Config — update these to match your deployment
#------------------------------------------------------------------------------
KEYVAULT_NAME="my-bootstrap-kv"
BOOTSTRAP_RG="bootstrap-keyvault-rg"
LOCATION="centralus"
FQDN="tfe.azure.example.com"

#------------------------------------------------------------------------------
# Derived
#------------------------------------------------------------------------------
MY_USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"
LICENSE_FILE="${SCRIPT_DIR}/../terraform.hclic"

echo "==> Starting TFE bootstrap..."
echo "    Key Vault : $KEYVAULT_NAME"
echo "    RG        : $BOOTSTRAP_RG"
echo "    Location  : $LOCATION"
echo "    FQDN      : $FQDN"
echo ""

#------------------------------------------------------------------------------
# 1. Bootstrap resource group (idempotent — az group create is a no-op if exists)
#------------------------------------------------------------------------------
echo "==> [1/7] Ensuring bootstrap resource group exists..."
az group create \
  --name "$BOOTSTRAP_RG" \
  --location "$LOCATION" \
  --output none
echo "    Done."

#------------------------------------------------------------------------------
# 2. Key Vault (idempotent — skip if already exists)
#------------------------------------------------------------------------------
echo "==> [2/7] Ensuring Key Vault '$KEYVAULT_NAME' exists..."
if az keyvault show --name "$KEYVAULT_NAME" --resource-group "$BOOTSTRAP_RG" &>/dev/null; then
  echo "    Key Vault already exists, skipping creation."
else
  az keyvault create \
    --name "$KEYVAULT_NAME" \
    --resource-group "$BOOTSTRAP_RG" \
    --location "$LOCATION" \
    --enable-rbac-authorization true \
    --sku standard \
    --output none
  echo "    Key Vault created."
fi

#------------------------------------------------------------------------------
# 3. Role assignment (idempotent — skip if already assigned)
#    Wait only happens when a NEW assignment is created.
#------------------------------------------------------------------------------
echo "==> [3/7] Ensuring Key Vault Administrator role assignment..."
KEYVAULT_ID=$(az keyvault show \
  --name "$KEYVAULT_NAME" \
  --resource-group "$BOOTSTRAP_RG" \
  --query id -o tsv)

EXISTING_ASSIGNMENT=$(az role assignment list \
  --role "Key Vault Administrator" \
  --assignee "$MY_USER_OBJECT_ID" \
  --scope "$KEYVAULT_ID" \
  --query "[0].id" -o tsv 2>/dev/null || true)

if [[ -n "$EXISTING_ASSIGNMENT" ]]; then
  echo "    Role assignment already exists, skipping."
else
  az role assignment create \
    --role "Key Vault Administrator" \
    --assignee-object-id "$MY_USER_OBJECT_ID" \
    --assignee-principal-type User \
    --scope "$KEYVAULT_ID" \
    --output none
  echo "    Role assigned. Waiting 60s for RBAC propagation..."
  sleep 60
  echo "    Done."
fi

#------------------------------------------------------------------------------
# 4. Clean up and regenerate TLS certificates
#------------------------------------------------------------------------------
echo "==> [4/7] Regenerating TLS certificates for '$FQDN'..."

# Remove any existing cert files so we start clean
rm -f \
  "${CERTS_DIR}/privkey.pem" \
  "${CERTS_DIR}/cert.pem" \
  "${CERTS_DIR}/ca_bundle.pem" \
  "${CERTS_DIR}/cert_nowrap.b64" \
  "${CERTS_DIR}/privkey_nowrap.b64" \
  "${CERTS_DIR}/ca_bundle_nowrap.b64"

mkdir -p "$CERTS_DIR"

openssl genrsa -out "${CERTS_DIR}/privkey.pem" 4096 2>/dev/null

openssl req -new -x509 \
  -key "${CERTS_DIR}/privkey.pem" \
  -out "${CERTS_DIR}/cert.pem" \
  -days 365 \
  -subj "/CN=${FQDN}" \
  -addext "subjectAltName=DNS:${FQDN}" 2>/dev/null

cp "${CERTS_DIR}/cert.pem" "${CERTS_DIR}/ca_bundle.pem"

# Base64 encode (no line wrapping)
base64 < "${CERTS_DIR}/cert.pem"      | tr -d '\n' > "${CERTS_DIR}/cert_nowrap.b64"
base64 < "${CERTS_DIR}/privkey.pem"   | tr -d '\n' > "${CERTS_DIR}/privkey_nowrap.b64"
base64 < "${CERTS_DIR}/ca_bundle.pem" | tr -d '\n' > "${CERTS_DIR}/ca_bundle_nowrap.b64"

echo "    Certificates written to $CERTS_DIR"

#------------------------------------------------------------------------------
# 5. Upload TLS secrets to Key Vault (always overwrite with latest certs)
#------------------------------------------------------------------------------
echo "==> [5/7] Uploading TLS secrets to Key Vault..."

az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "tfe-tls-cert" \
  --file "${CERTS_DIR}/cert_nowrap.b64" \
  --output none

az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "tfe-tls-privkey" \
  --file "${CERTS_DIR}/privkey_nowrap.b64" \
  --output none

az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "tfe-tls-ca-bundle" \
  --file "${CERTS_DIR}/ca_bundle_nowrap.b64" \
  --output none

echo "    Done."

#------------------------------------------------------------------------------
# 6. Database password (only generate if secret does not already exist)
#------------------------------------------------------------------------------
echo "==> [6/7] Ensuring database password secret exists..."

if az keyvault secret show \
     --vault-name "$KEYVAULT_NAME" \
     --name "tfe-database-password" &>/dev/null; then
  echo "    Secret 'tfe-database-password' already exists, skipping."
else
  # No $ character — PostgreSQL does not allow it in passwords
  DB_PASSWORD=$(openssl rand -base64 24 | tr -d '/+=$')
  az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "tfe-database-password" \
    --value "$DB_PASSWORD" \
    --output none
  echo "    Database password stored in Key Vault."
fi

#------------------------------------------------------------------------------
# 7. TFE license (read from terraform.hclic) + encryption password (auto-generated)
#------------------------------------------------------------------------------
echo "==> [7/7] Storing TFE license and encryption password..."

# --- License ---
if [[ ! -f "$LICENSE_FILE" ]]; then
  echo "    ERROR: License file not found at $LICENSE_FILE"
  echo "    Place your terraform.hclic file in the root of the tfe-azure directory and re-run."
  exit 1
fi

TFE_LICENSE=$(tr -d '[:space:]' < "$LICENSE_FILE")

az keyvault secret set \
  --vault-name "$KEYVAULT_NAME" \
  --name "tfe-license" \
  --value "$TFE_LICENSE" \
  --output none
echo "    TFE license stored from terraform.hclic."

# --- Encryption password (only generate if not already set) ---
if az keyvault secret show \
     --vault-name "$KEYVAULT_NAME" \
     --name "tfe-encryption-password" &>/dev/null; then
  echo "    Secret 'tfe-encryption-password' already exists, skipping."
else
  ENCRYPTION_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=$')
  az keyvault secret set \
    --vault-name "$KEYVAULT_NAME" \
    --name "tfe-encryption-password" \
    --value "$ENCRYPTION_PASSWORD" \
    --output none
  echo "    Encryption password generated and stored."
fi

#------------------------------------------------------------------------------
# Output — all terraform.tfvars values
#------------------------------------------------------------------------------
KV_BASE="https://${KEYVAULT_NAME}.vault.azure.net/secrets"

VNET_ID=$(az network vnet show \
  --name "tfe-vnet" \
  --resource-group "tfe-networking-rg" \
  --query id -o tsv 2>/dev/null || echo "<vnet not found — set create_networking_resources = true>")
LB_SUBNET_ID=$(az network vnet subnet show \
  --name "tfe-lb-subnet" --resource-group "tfe-networking-rg" --vnet-name "tfe-vnet" \
  --query id -o tsv 2>/dev/null || echo "<not found>")
VM_SUBNET_ID=$(az network vnet subnet show \
  --name "tfe-vm-subnet" --resource-group "tfe-networking-rg" --vnet-name "tfe-vnet" \
  --query id -o tsv 2>/dev/null || echo "<not found>")
DB_SUBNET_ID=$(az network vnet subnet show \
  --name "tfe-db-subnet" --resource-group "tfe-networking-rg" --vnet-name "tfe-vnet" \
  --query id -o tsv 2>/dev/null || echo "<not found>")
REDIS_SUBNET_ID=$(az network vnet subnet show \
  --name "tfe-redis-subnet" --resource-group "tfe-networking-rg" --vnet-name "tfe-vnet" \
  --query id -o tsv 2>/dev/null || echo "<not found>")

MY_IP=$(curl -s https://ifconfig.me)

echo ""
echo "============================================================"
echo "  Copy the following into your main/terraform.tfvars"
echo "============================================================"
echo ""
echo "# --- Bootstrap --- #"
echo "bootstrap_keyvault_name                    = \"${KEYVAULT_NAME}\""
echo "bootstrap_keyvault_rg_name                 = \"${BOOTSTRAP_RG}\""
echo "use_key_vault_rbac                         = true"
echo "tfe_license_keyvault_secret_id             = \"${KV_BASE}/tfe-license\""
echo "tfe_tls_cert_keyvault_secret_id            = \"${KV_BASE}/tfe-tls-cert\""
echo "tfe_tls_privkey_keyvault_secret_id         = \"${KV_BASE}/tfe-tls-privkey\""
echo "tfe_tls_ca_bundle_keyvault_secret_id       = \"${KV_BASE}/tfe-tls-ca-bundle\""
echo "tfe_encryption_password_keyvault_secret_id = \"${KV_BASE}/tfe-encryption-password\""
echo "tfe_database_password_keyvault_secret_name = \"tfe-database-password\""
echo ""
echo "# --- Common --- #"
echo "location = \"${LOCATION}\""
echo ""
echo "# --- TFE config settings --- #"
echo "tfe_fqdn = \"${FQDN}\""
echo ""
echo "# --- Networking (only needed if create_networking_resources = false) --- #"
echo "vnet_id         = \"${VNET_ID}\""
echo "lb_subnet_id    = \"${LB_SUBNET_ID}\""
echo "vm_subnet_id    = \"${VM_SUBNET_ID}\""
echo "db_subnet_id    = \"${DB_SUBNET_ID}\""
echo "redis_subnet_id = \"${REDIS_SUBNET_ID}\""
echo ""
echo "# --- Object storage --- #"
echo "storage_account_ip_allow = [\"${MY_IP}\"]"
echo ""
echo "============================================================"
echo ""
echo "==> Bootstrap complete."
