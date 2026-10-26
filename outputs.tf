# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Windows bastion
#------------------------------------------------------------------------------
output "windows_bastion_public_ip" {
  value       = var.create_windows_bastion ? azurerm_public_ip.windows_bastion[0].ip_address : null
  description = "Public IP address of the Windows bastion VM. Use this to open an RDP session from your Mac."
}

#------------------------------------------------------------------------------
# DNS
#------------------------------------------------------------------------------
output "public_dns_zone_name_servers" {
  value       = var.create_public_dns_zone ? azurerm_dns_zone.tfe[0].name_servers : null
  description = "List of authoritative name servers for the created public DNS zone. Delegate your domain to these name servers. Only populated when `create_public_dns_zone` is `true`."
}

#------------------------------------------------------------------------------
# TFE
#------------------------------------------------------------------------------
output "url" {
  value       = "https://${var.tfe_fqdn}"
  description = "URL of TFE application based on `tfe_fqdn` input."
}

#------------------------------------------------------------------------------
# Dashboard
#------------------------------------------------------------------------------
output "dashboard_url" {
  value       = var.create_dashboard ? "https://portal.azure.com/#@/dashboard/arm${azurerm_portal_dashboard.tfe[0].id}" : null
  description = "Azure Portal URL to open the TFE Portal Dashboard. Only populated when `create_dashboard` is `true`."
}

output "workbook_url" {
  value       = var.create_workbook ? "https://portal.azure.com/#resource${azurerm_application_insights_workbook.tfe[0].id}" : null
  description = "Azure Portal URL to open the TFE Monitor Workbook. Only populated when `create_workbook` is `true`."
}

#------------------------------------------------------------------------------
# Event Hub
#------------------------------------------------------------------------------
output "event_hub_namespace_id" {
  value       = var.create_event_hub ? azurerm_eventhub_namespace.tfe[0].id : null
  description = "The ID of the Azure Event Hubs namespace created for TFE log forwarding."
}

output "event_hub_id" {
  value       = var.create_event_hub ? azurerm_eventhub.tfe[0].id : null
  description = "The ID of the Azure Event Hub topic created for TFE log forwarding."
}

output "tfe_admin_console_url_pattern" {
  value       = !var.tfe_admin_console_disabled ? "https://${var.tfe_fqdn}:${var.tfe_admin_https_port}" : null
  description = "URL pattern to access the TFE Admin Console when it is enabled."
}

#------------------------------------------------------------------------------
# Database
#------------------------------------------------------------------------------
output "tfe_database_host" {
  value       = "${azurerm_postgresql_flexible_server.tfe.fqdn}:5432"
  description = "FQDN and port of PostgreSQL Flexible Server."
}

output "tfe_database_name" {
  value       = azurerm_postgresql_flexible_server_database.tfe.name
  description = "Name of PostgreSQL Flexible Server database."
}

#------------------------------------------------------------------------------
# Object storage
#------------------------------------------------------------------------------
output "tfe_object_storage_azure_account_name" {
  value       = try(azurerm_storage_account.tfe[0].name, null)
  description = "Name of primary TFE Azure Storage Account."
}

output "tfe_object_storage_azure_container_name" {
  value       = try(azurerm_storage_container.tfe[0].name, null)
  description = "Name of TFE Azure Storage Container."
}
