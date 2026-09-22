#!/usr/bin/env bash
# cleanup.sh — Delete all manually created Azure prerequisites for the TFE deployment.
# Resources created via Terraform (tfe-rg) should be destroyed with `terraform destroy` first.
# Run this script AFTER `terraform destroy` has completed.

set -euo pipefail

#------------------------------------------------------------------------------
# Config — update these if your values differ
#------------------------------------------------------------------------------
KEYVAULT_NAME="my-bootstrap-kv"
BOOTSTRAP_RG="bootstrap-keyvault-rg"
NETWORKING_RG="tfe-networking-rg"
LOG_ANALYTICS_RG="tfe-log-analytics-rg"
LOG_ANALYTICS_WORKSPACE="tfeloganalyticsworkspacename"
VNET="tfe-vnet"
BASTION_NAME="tfe-bastion"
BASTION_IP="tfe-bastion-ip"

echo "==> Starting TFE prerequisite cleanup..."
echo ""

#------------------------------------------------------------------------------
# 1. Bastion host (delete first — depends on subnet and public IP)
#------------------------------------------------------------------------------
echo "==> [1/6] Deleting bastion host (if exists)..."
if az network bastion show --name "$BASTION_NAME" --resource-group "$NETWORKING_RG" &>/dev/null; then
  echo "    Waiting for bastion to be fully deleted (this can take a few minutes)..."
  az network bastion delete \
    --name "$BASTION_NAME" \
    --resource-group "$NETWORKING_RG"
  echo "    Bastion deleted."
else
  echo "    Bastion not found, skipping."
fi

echo ""

#------------------------------------------------------------------------------
# 2. Bastion public IP
#------------------------------------------------------------------------------
echo "==> [2/6] Deleting bastion public IP (if exists)..."
if az network public-ip show --name "$BASTION_IP" --resource-group "$NETWORKING_RG" &>/dev/null; then
  az network public-ip delete \
    --name "$BASTION_IP" \
    --resource-group "$NETWORKING_RG"
  echo "    Bastion public IP deleted."
else
  echo "    Bastion public IP not found, skipping."
fi

echo ""

#------------------------------------------------------------------------------
# 3. Networking resource group (VNet + all subnets)
#------------------------------------------------------------------------------
echo "==> [3/6] Deleting networking resource group '$NETWORKING_RG' (VNet, subnets)..."
if az group show --name "$NETWORKING_RG" &>/dev/null; then
  az group delete \
    --name "$NETWORKING_RG" \
    --yes \
    --no-wait
  echo "    '$NETWORKING_RG' deletion triggered (runs async)."
else
  echo "    '$NETWORKING_RG' not found, skipping."
fi

echo ""

#------------------------------------------------------------------------------
# 4. Bootstrap Key Vault (purge to fully remove soft-deleted vault)
#------------------------------------------------------------------------------
echo "==> [4/6] Deleting bootstrap Key Vault '$KEYVAULT_NAME'..."
if az keyvault show --name "$KEYVAULT_NAME" --resource-group "$BOOTSTRAP_RG" &>/dev/null; then
  az keyvault delete \
    --name "$KEYVAULT_NAME" \
    --resource-group "$BOOTSTRAP_RG"
  echo "    Key Vault deleted. Purging to remove soft-delete retention..."
  az keyvault purge \
    --name "$KEYVAULT_NAME" \
    --no-wait
  echo "    Purge triggered."
else
  echo "    Key Vault '$KEYVAULT_NAME' not found, skipping."
fi

echo ""

#------------------------------------------------------------------------------
# 5. Bootstrap resource group
#------------------------------------------------------------------------------
echo "==> [5/6] Deleting bootstrap resource group '$BOOTSTRAP_RG'..."
if az group show --name "$BOOTSTRAP_RG" &>/dev/null; then
  az group delete \
    --name "$BOOTSTRAP_RG" \
    --yes \
    --no-wait
  echo "    '$BOOTSTRAP_RG' deletion triggered (runs async)."
else
  echo "    '$BOOTSTRAP_RG' not found, skipping."
fi

echo ""

#------------------------------------------------------------------------------
# 6. Log Analytics workspace + resource group
#------------------------------------------------------------------------------
echo "==> [6/6] Deleting Log Analytics workspace '$LOG_ANALYTICS_WORKSPACE'..."
if az monitor log-analytics workspace show \
     --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
     --resource-group "$LOG_ANALYTICS_RG" &>/dev/null; then
  az monitor log-analytics workspace delete \
    --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
    --resource-group "$LOG_ANALYTICS_RG" \
    --force \
    --yes
  echo "    Log Analytics workspace deleted."
else
  echo "    Log Analytics workspace not found, skipping."
fi

if az group show --name "$LOG_ANALYTICS_RG" &>/dev/null; then
  az group delete \
    --name "$LOG_ANALYTICS_RG" \
    --yes \
    --no-wait
  echo "    '$LOG_ANALYTICS_RG' deletion triggered (runs async)."
else
  echo "    '$LOG_ANALYTICS_RG' not found, skipping."
fi

echo ""
echo "==> Cleanup complete."
echo "    Note: async deletions may still be running. Check the Azure portal to confirm."
