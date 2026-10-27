# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

output "url" {
  value       = module.tfe.url
  description = "URL of TFE application."
}

output "resource_group_name" {
  value       = module.tfe.resource_group_name
  description = "Name of the resource group containing the TFE resources."
}

output "vmss_name" {
  value       = module.tfe.vmss_name
  description = "Name of the TFE Virtual Machine Scale Set. Used by the scripts to find the TFE VM."
}

output "load_balancer_ip" {
  value       = module.tfe.load_balancer_ip
  description = "IP address of the TFE load balancer: the public IP when external, or the private IP when internal."
}

output "vnet_id" {
  value       = module.tfe.vnet_id
  description = "ID of the Virtual Network that TFE is deployed in."
}

output "networking_resource_group_name" {
  value       = module.tfe.networking_resource_group_name
  description = "Name of the networking resource group. Only populated when `create_networking_resources` is `true`."
}

output "azure_bastion_name" {
  value       = module.tfe.azure_bastion_name
  description = "Name of the Azure Bastion host used to SSH to the TFE VM."
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

output "ubuntu_bastion_public_ip" {
  value       = module.tfe.ubuntu_bastion_public_ip
  description = "Public IP address of the Ubuntu bastion VM. Use this to open an RDP (xrdp) or SSH session from your Mac."
}

output "public_dns_zone_name_servers" {
  value       = module.tfe.public_dns_zone_name_servers
  description = "Authoritative name servers for the created public DNS zone. Delegate your domain to these."
}

output "dashboard_url" {
  value       = module.tfe.dashboard_url
  description = "Azure Portal URL to open the TFE Portal Dashboard. Only populated when `create_dashboard` is `true`."
}

output "event_hub_namespace_id" {
  value       = module.tfe.event_hub_namespace_id
  description = "The ID of the Azure Event Hubs namespace created for TFE log forwarding."
}

output "event_hub_id" {
  value       = module.tfe.event_hub_id
  description = "The ID of the Azure Event Hub topic created for TFE log forwarding."
}
