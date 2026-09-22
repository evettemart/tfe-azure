# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

output "url" {
  value       = module.tfe.url
  description = "URL of TFE application."
}

output "tfe_admin_console_url_pattern" {
  value       = module.tfe.tfe_admin_console_url_pattern
  description = "URL pattern to access the TFE Admin Console when it is enabled."
}

output "tfe_database_host" {
  value       = module.tfe.tfe_database_host
  description = "FQDN and port of PostgreSQL Flexible Server."
}

output "tfe_database_name" {
  value       = module.tfe.tfe_database_name
  description = "Name of PostgreSQL Flexible Server database."
}

output "tfe_object_storage_azure_account_name" {
  value       = module.tfe.tfe_object_storage_azure_account_name
  description = "Name of primary TFE Azure Storage Account."
}

output "tfe_object_storage_azure_container_name" {
  value       = module.tfe.tfe_object_storage_azure_container_name
  description = "Name of TFE Azure Storage Container."
}

output "windows_bastion_public_ip" {
  value       = module.tfe.windows_bastion_public_ip
  description = "Public IP address of the Windows bastion VM. Use this to open an RDP session from your Mac."
}

output "public_dns_zone_name_servers" {
  value       = module.tfe.public_dns_zone_name_servers
  description = "Authoritative name servers for the created public DNS zone. Delegate your domain to these."
}
