# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Event Hub -> Log Analytics ingestion (optional)
#
# A Data Collection Rule (DCR) reads the TFE log events that Fluent Bit sends to
# the Event Hub and writes them to a custom Log Analytics table. The table name
# and the `component_s` / `log_s` columns match what dashboards/TFE.json queries.
#
# Controlled by `create_event_hub_log_analytics_ingestion = true`. Use it with
# `log_fwd_destination_type = "event_hub"` so Fluent Bit only sends to the hub.
#
# If the workspace already has a `tfe_fluent_bit_CL` table (created earlier by
# the Fluent Bit `azure` output), import it before applying:
#   terraform import 'module.tfe.azurerm_log_analytics_workspace_table_custom_log.tfe[0]' \
#     <workspace resource ID>/tables/tfe_fluent_bit_CL
# The columns below match that table, so the import shows no changes and the
# existing data is kept.
#------------------------------------------------------------------------------
locals {
  event_hub_ingestion_table_name = "tfe_fluent_bit_CL"
  event_hub_ingestion_stream     = "Custom-TfeEventHubLogs"
}

resource "azurerm_eventhub_consumer_group" "log_analytics" {
  count = var.create_event_hub_log_analytics_ingestion ? 1 : 0

  name                = "tfe-log-analytics"
  namespace_name      = azurerm_eventhub_namespace.tfe[0].name
  eventhub_name       = azurerm_eventhub.tfe[0].name
  resource_group_name = azurerm_eventhub_namespace.tfe[0].resource_group_name
}

resource "azurerm_user_assigned_identity" "event_hub_ingestion" {
  count = var.create_event_hub_log_analytics_ingestion ? 1 : 0

  name                = "${var.friendly_name_prefix}-tfe-eventhub-dcr-id"
  resource_group_name = azurerm_resource_group.log_analytics[0].name
  location            = var.location

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-tfe-eventhub-dcr-id" },
    var.common_tags
  )
}

resource "azurerm_role_assignment" "event_hub_ingestion" {
  count = var.create_event_hub_log_analytics_ingestion ? 1 : 0

  scope                = azurerm_eventhub.tfe[0].id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_user_assigned_identity.event_hub_ingestion[0].principal_id
}

resource "azurerm_log_analytics_workspace_table_custom_log" "tfe" {
  count = var.create_event_hub_log_analytics_ingestion ? 1 : 0

  name         = local.event_hub_ingestion_table_name
  display_name = local.event_hub_ingestion_table_name
  workspace_id = azurerm_log_analytics_workspace.tfe[0].id

  # Same columns, in the same order, as the classic table that the Fluent Bit
  # `azure` output created. Azure cannot rename columns, so these must match.
  # TimeGenerated is a standard column and is not declared here.
  column {
    name         = "_timestamp_d"
    type         = "real"
    display_name = "_timestamp_d"
  }

  column {
    name         = "log_s"
    type         = "string"
    display_name = "log_s"
  }

  column {
    name         = "component_s"
    type         = "string"
    display_name = "component_s"
  }
}

resource "azurerm_monitor_data_collection_rule" "event_hub" {
  count = var.create_event_hub_log_analytics_ingestion ? 1 : 0

  name                = "${var.friendly_name_prefix}-tfe-eventhub-dcr"
  resource_group_name = azurerm_resource_group.log_analytics[0].name
  location            = var.location

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.event_hub_ingestion[0].id]
  }

  # Event Hub input streams have a fixed shape: TimeGenerated, RawData, Properties.
  stream_declaration {
    stream_name = local.event_hub_ingestion_stream

    column {
      name = "TimeGenerated"
      type = "datetime"
    }
    column {
      name = "RawData"
      type = "string"
    }
    column {
      name = "Properties"
      type = "dynamic"
    }
  }

  data_sources {
    data_import {
      event_hub_data_source {
        name           = "tfe-event-hub"
        stream         = local.event_hub_ingestion_stream
        consumer_group = azurerm_eventhub_consumer_group.log_analytics[0].name
      }
    }
  }

  destinations {
    log_analytics {
      name                  = "tfe-log-analytics"
      workspace_resource_id = azurerm_log_analytics_workspace.tfe[0].id
    }
  }

  data_flow {
    streams       = [local.event_hub_ingestion_stream]
    destinations  = ["tfe-log-analytics"]
    output_stream = "Custom-${local.event_hub_ingestion_table_name}"
    transform_kql = <<-KQL
      source
      | extend Record = parse_json(RawData)
      | project TimeGenerated,
                component_s = tostring(Record.component),
                log_s = tostring(Record.log)
    KQL
  }

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-tfe-eventhub-dcr" },
    var.common_tags
  )

  depends_on = [
    azurerm_role_assignment.event_hub_ingestion,
    azurerm_log_analytics_workspace_table_custom_log.tfe,
  ]
}
