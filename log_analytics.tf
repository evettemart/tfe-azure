# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Log Analytics resource group + workspace
#------------------------------------------------------------------------------
resource "azurerm_resource_group" "log_analytics" {
  count = var.create_log_analytics_workspace ? 1 : 0

  name     = var.log_analytics_workspace_rg_name
  location = var.location

  tags = merge(
    { "Name" = var.log_analytics_workspace_rg_name },
    var.common_tags
  )
}

resource "azurerm_log_analytics_workspace" "tfe" {
  count = var.create_log_analytics_workspace ? 1 : 0

  name                = var.log_analytics_workspace_name
  resource_group_name = azurerm_resource_group.log_analytics[0].name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = merge(
    { "Name" = var.log_analytics_workspace_name },
    var.common_tags
  )
}
