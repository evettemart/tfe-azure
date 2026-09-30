# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Event Hub resource group (optional), namespace, event hub, and auth rule
#------------------------------------------------------------------------------
resource "azurerm_resource_group" "event_hub" {
  count = var.create_event_hub && var.event_hub_rg_name != null ? 1 : 0

  name     = var.event_hub_rg_name
  location = var.location

  tags = merge(
    { "Name" = var.event_hub_rg_name },
    var.common_tags
  )
}

resource "azurerm_eventhub_namespace" "tfe" {
  count = var.create_event_hub ? 1 : 0

  name                = var.event_hub_namespace_name != null ? var.event_hub_namespace_name : "${var.friendly_name_prefix}-tfe-eventhub-ns"
  resource_group_name = var.event_hub_rg_name != null ? azurerm_resource_group.event_hub[0].name : local.resource_group_name
  location            = var.location
  sku                 = var.event_hub_sku
  capacity            = var.event_hub_capacity

  tags = merge(
    { "Name" = var.event_hub_namespace_name != null ? var.event_hub_namespace_name : "${var.friendly_name_prefix}-tfe-eventhub-ns" },
    var.common_tags
  )
}

resource "azurerm_eventhub" "tfe" {
  count = var.create_event_hub ? 1 : 0

  name              = var.event_hub_name != null ? var.event_hub_name : "tfe-logs"
  namespace_id      = azurerm_eventhub_namespace.tfe[0].id
  partition_count   = var.event_hub_partition_count
  message_retention = var.event_hub_message_retention
}

resource "azurerm_eventhub_authorization_rule" "fluent_bit" {
  count = var.create_event_hub ? 1 : 0

  name                = "tfe-fluent-bit-send"
  namespace_name      = azurerm_eventhub_namespace.tfe[0].name
  eventhub_name       = azurerm_eventhub.tfe[0].name
  resource_group_name = azurerm_eventhub_namespace.tfe[0].resource_group_name

  listen = false
  send   = true
  manage = false
}
