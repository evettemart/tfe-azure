# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# TFE Dashboards
#
# Dashboard and Workbook resources:
#
#   1. azurerm_portal_dashboard  — loaded from dashboards/TFE.json
#      An Azure Portal shared dashboard pinned to the portal home page.
#      Controlled by `create_dashboard = true`.
#
#   2. azurerm_application_insights_workbook — inline KQL
#      An Azure Monitor Workbook with interactive charts and tables for
#      run outcomes, error rates, and HTTP traffic.
#      Controlled by `create_workbook = true`.
#
# Both query the Log Analytics custom log table `tfe_fluent_bit_CL` which
# Fluent Bit populates from TFE container logs (Log_Type = tfe_fluent_bit).
#
# Requires:
#   - tfe_log_forwarding_enabled  = true
#   - log_fwd_destination_type    = "log_analytics"
#------------------------------------------------------------------------------
locals {
  dashboard_name = "${var.friendly_name_prefix}-tfe-dashboard"
  workbook_name  = "${var.friendly_name_prefix}-tfe-workbook"

  # Full ARM resource ID of the Log Analytics workspace used as the KQL source.
  log_analytics_resource_id = (
    (var.create_dashboard || var.create_workbook) && var.tfe_log_forwarding_enabled && contains(["log_analytics", "both"], var.log_fwd_destination_type) ?
    (var.create_log_analytics_workspace ?
      azurerm_log_analytics_workspace.tfe[0].id :
    data.azurerm_log_analytics_workspace.logging[0].id)
    : null
  )
}

#------------------------------------------------------------------------------
# 1. Azure Portal Dashboard (from dashboards/TFE.json)
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

#------------------------------------------------------------------------------
# 2. Azure Monitor Workbook (interactive KQL charts)
#------------------------------------------------------------------------------
resource "azurerm_application_insights_workbook" "tfe" {
  count = var.create_workbook ? 1 : 0

  name                = uuidv5("url", "https://tfe.workbook/${var.friendly_name_prefix}")
  resource_group_name = local.resource_group_name
  location            = var.location
  display_name        = "${var.friendly_name_prefix} TFE — Operational Dashboard"

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = [
      {
        type    = 1
        name    = "header"
        content = { json = "## TFE Operational Dashboard\nAll data is sourced from `tfe_fluent_bit_CL` in Log Analytics. Use the **Time Range** picker to adjust the window." }
      },
      # Shared parameters: time range + pre-bound Log Analytics workspace
      {
        type = 9
        name = "params"
        content = {
          version = "KqlParameterItem/1.0"
          parameters = [
            {
              id      = "a1b2c3d4-0000-0000-0000-000000000001"
              version = "KqlParameterItem/1.0"
              name    = "TimeRange"
              type    = 4
              typeSettings = {
                selectableValues = [
                  { durationMs = 3600000 },
                  { durationMs = 14400000 },
                  { durationMs = 43200000 },
                  { durationMs = 86400000 },
                  { durationMs = 604800000 },
                  { durationMs = 2592000000 }
                ]
                allowCustom = true
              }
              value = { durationMs = 86400000 }
              label = "Time Range"
            },
          ]
        }
      },
      # ---- Runs ----
      { type = 1, name = "runsHeader", content = { json = "### Runs" } },
      {
        type = 3, name = "workspaceTable"
        content = {
          version                  = "KqlItem/1.0", title = "Workspace Run Summary"
          timeContextFromParameter = "TimeRange", queryType = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = [local.log_analytics_resource_id]
          query                    = "tfe_fluent_bit_CL\n| where TimeGenerated {TimeRange}\n| where RawData has \"run\"\n| extend parsed = parse_json(RawData)\n| extend workspace = tostring(parsed.workspace_name)\n| extend msg = tostring(parsed[\"@message\"])\n| where isnotempty(workspace)\n| summarize SuccessfulPlans = countif(msg has \"planned\"), SuccessfulApplies = countif(msg has \"applied\"), Errors = countif(msg has \"errored\"), TotalRuns = count() by workspace\n| order by TotalRuns desc"
          size                     = 0
          gridSettings = {
            formatters = [
              { columnMatch = "workspace", formatter = 0, formatOptions = {} },
              { columnMatch = "TotalRuns", formatter = 8, formatOptions = { min = 0, palette = "blue" } },
              { columnMatch = "SuccessfulPlans", formatter = 8, formatOptions = { min = 0, palette = "blue" } },
              { columnMatch = "SuccessfulApplies", formatter = 8, formatOptions = { min = 0, palette = "green" } },
              { columnMatch = "Errors", formatter = 8, formatOptions = { min = 0, palette = "red" } }
            ]
            labelSettings = [
              { columnId = "workspace", label = "Workspace" },
              { columnId = "TotalRuns", label = "Total Runs" },
              { columnId = "SuccessfulPlans", label = "Successful Plans" },
              { columnId = "SuccessfulApplies", label = "Successful Applies" },
              { columnId = "Errors", label = "Errors" }
            ]
          }
        }
      },
      {
        type = 3, name = "runStatusChart"
        content = {
          version                  = "KqlItem/1.0", title = "Run Outcomes Over Time"
          timeContextFromParameter = "TimeRange", queryType = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = [local.log_analytics_resource_id]
          query                    = "tfe_fluent_bit_CL\n| where TimeGenerated {TimeRange}\n| where RawData has \"run\"\n| extend parsed = parse_json(RawData)\n| extend msg = tostring(parsed[\"@message\"])\n| extend outcome = case(msg has \"applied\", \"Applied\", msg has \"planned\", \"Planned\", msg has \"errored\", \"Errored\", msg has \"canceled\", \"Canceled\", msg has \"discarded\", \"Discarded\", \"Other\")\n| where outcome != \"Other\"\n| summarize Count = count() by bin(TimeGenerated, 1h), outcome\n| order by TimeGenerated asc"
          size                     = 0, visualization = "barchart"
          chartSettings = {
            chartType = 2
            seriesLabelSettings = [
              { seriesName = "Applied", color = "green" },
              { seriesName = "Planned", color = "blue" },
              { seriesName = "Errored", color = "red" },
              { seriesName = "Canceled", color = "orange" },
              { seriesName = "Discarded", color = "gray" }
            ]
          }
        }
      },
      # ---- Errors & Warnings ----
      { type = 1, name = "errorsHeader", content = { json = "### Errors & Warnings" } },
      {
        type = 3, name = "errorRateChart"
        content = {
          version                  = "KqlItem/1.0", title = "Error & Warning Rate Over Time"
          timeContextFromParameter = "TimeRange", queryType = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = [local.log_analytics_resource_id]
          query                    = "tfe_fluent_bit_CL\n| where TimeGenerated {TimeRange}\n| extend parsed = parse_json(RawData)\n| extend log_level = tostring(parsed[\"@level\"])\n| where log_level in (\"error\", \"warn\")\n| summarize Count = count() by bin(TimeGenerated, 15m), log_level\n| order by TimeGenerated asc"
          size                     = 0, visualization = "linechart"
          chartSettings = {
            chartType = 2
            seriesLabelSettings = [
              { seriesName = "error", color = "red" },
              { seriesName = "warn", color = "yellow" }
            ]
          }
        }
      },
      {
        type = 3, name = "topErrorsTable"
        content = {
          version                  = "KqlItem/1.0", title = "Top Error Messages"
          timeContextFromParameter = "TimeRange", queryType = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = [local.log_analytics_resource_id]
          query                    = "tfe_fluent_bit_CL\n| where TimeGenerated {TimeRange}\n| extend parsed = parse_json(RawData)\n| extend log_level = tostring(parsed[\"@level\"])\n| extend message = tostring(parsed[\"@message\"])\n| where log_level == \"error\" and isnotempty(message)\n| summarize Count = count(), LastSeen = max(TimeGenerated) by message\n| order by Count desc\n| take 20"
          size                     = 0
          gridSettings = {
            formatters = [
              { columnMatch = "Count", formatter = 8, formatOptions = { min = 0, palette = "red" } },
              { columnMatch = "LastSeen", formatter = 0, formatOptions = {} },
              { columnMatch = "message", formatter = 0, formatOptions = {} }
            ]
            labelSettings = [
              { columnId = "message", label = "Error Message" },
              { columnId = "Count", label = "Count" },
              { columnId = "LastSeen", label = "Last Seen" }
            ]
          }
        }
      },
      # ---- HTTP Traffic ----
      { type = 1, name = "httpHeader", content = { json = "### HTTP Traffic" } },
      {
        type = 3, name = "httpStatusChart"
        content = {
          version                  = "KqlItem/1.0", title = "HTTP Responses by Status Class Over Time"
          timeContextFromParameter = "TimeRange", queryType = 0
          resourceType             = "microsoft.operationalinsights/workspaces"
          crossComponentResources  = [local.log_analytics_resource_id]
          query                    = "tfe_fluent_bit_CL\n| where TimeGenerated {TimeRange}\n| extend parsed = parse_json(RawData)\n| extend status_code = toint(parsed.status)\n| where isnotnull(status_code)\n| extend status_class = case(status_code < 300, \"2xx Success\", status_code < 400, \"3xx Redirect\", status_code < 500, \"4xx Client Error\", \"5xx Server Error\")\n| summarize Count = count() by bin(TimeGenerated, 15m), status_class\n| order by TimeGenerated asc"
          size                     = 0, visualization = "linechart"
          chartSettings = {
            chartType = 2
            seriesLabelSettings = [
              { seriesName = "2xx Success", color = "green" },
              { seriesName = "3xx Redirect", color = "blue" },
              { seriesName = "4xx Client Error", color = "orange" },
              { seriesName = "5xx Server Error", color = "red" }
            ]
          }
        }
      }
    ]
    styleSettings = {}
    "$schema"     = "https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json"
  })

  tags = merge(
    { "Name" = local.workbook_name },
    var.common_tags
  )
}
