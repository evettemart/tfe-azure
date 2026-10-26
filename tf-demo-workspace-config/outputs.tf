# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

output "workspace_id" {
  value       = tfe_workspace.this.id
  description = "ID of the created workspace."
}

output "workspace_url" {
  value       = tfe_workspace.this.html_url
  description = "URL of the created workspace in the TFE UI."
}

output "teams_notification_enabled" {
  value       = length(tfe_notification_configuration.teams) > 0
  description = "Whether a Microsoft Teams notification is configured on the workspace."
}

output "email_notification_enabled" {
  value       = length(tfe_notification_configuration.email) > 0
  description = "Whether an email notification is configured on the workspace."
}

output "smtp_managed" {
  value       = local.smtp_enabled
  description = "Whether this configuration manages TFE's SMTP settings."
}
