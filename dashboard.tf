# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# TFE Dashboard
#
#   azurerm_portal_dashboard — loaded from dashboards/TFE.json
#   An Azure Portal shared dashboard pinned to the portal home page.
#   Controlled by `create_dashboard = true`.
#
# It queries the Log Analytics custom log table `tfe_fluent_bit_CL` which
# Fluent Bit populates from TFE container logs (Log_Type = tfe_fluent_bit).
#
# Requires:
#   - tfe_log_forwarding_enabled  = true
#   - log_fwd_destination_type    = "log_analytics"
#------------------------------------------------------------------------------
locals {
  dashboard_name = "${var.friendly_name_prefix}-tfe-dashboard"

  # Full ARM resource ID of the Log Analytics workspace used as the KQL source.
  log_analytics_resource_id = (
    var.create_dashboard && var.tfe_log_forwarding_enabled && contains(["log_analytics", "both"], var.log_fwd_destination_type) ?
    (var.create_log_analytics_workspace ?
      azurerm_log_analytics_workspace.tfe[0].id :
    data.azurerm_log_analytics_workspace.logging[0].id)
    : null
  )
}

#------------------------------------------------------------------------------
# Azure Portal Dashboard (from dashboards/TFE.json)
#------------------------------------------------------------------------------
resource "azurerm_portal_dashboard" "tfe" {
  count = var.create_dashboard ? 1 : 0

  name                = local.dashboard_name
  resource_group_name = local.resource_group_name
  location            = var.location
  dashboard_properties = templatefile("${path.module}/dashboards/TFE.json", {
    log_analytics_resource_id    = local.log_analytics_resource_id
    log_analytics_workspace_name = var.log_analytics_workspace_name
    dashboard_name               = local.dashboard_name
    location                     = var.location
  })

  tags = merge(
    { "hidden-title" = local.dashboard_name },
    var.common_tags
  )
}
