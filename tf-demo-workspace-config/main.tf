# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Run AFTER Terraform Enterprise is deployed, the initial admin account exists,
# and the organization has been created. The API token is read from the
# TFE_TOKEN environment variable.
#------------------------------------------------------------------------------
provider "tfe" {
  hostname        = var.tfe_hostname
  ssl_skip_verify = var.tfe_ssl_skip_verify
}

locals {
  teams_enabled = var.enable_notifications && var.enable_teams_notifications
  email_enabled = var.enable_notifications && var.enable_email_notifications
  smtp_enabled  = local.email_enabled && var.configure_smtp
}

#------------------------------------------------------------------------------
# Workspace
#------------------------------------------------------------------------------
resource "tfe_workspace" "this" {
  organization        = var.tfe_organization
  name                = var.workspace_name
  description         = var.workspace_description
  auto_apply          = var.workspace_auto_apply
  terraform_version   = var.workspace_terraform_version
  assessments_enabled = var.workspace_assessments_enabled
}

#------------------------------------------------------------------------------
# Sentinel policy set
# The folder at `policy_set_source_path` (sentinel/ in this repo) is uploaded
# as-is. Its sentinel.hcl defines the policies and their enforcement levels.
# The policy set is not global; it is enabled only on the workspace above.
#------------------------------------------------------------------------------
data "tfe_slug" "policy_set" {
  count = var.enable_policy_set ? 1 : 0

  source_path = var.policy_set_source_path
}

resource "tfe_policy_set" "this" {
  count = var.enable_policy_set ? 1 : 0

  organization = var.tfe_organization
  name         = var.policy_set_name
  description  = var.policy_set_description
  kind         = "sentinel"
  global       = false
  slug         = data.tfe_slug.policy_set[0]
}

resource "tfe_workspace_policy_set" "this" {
  count = var.enable_policy_set ? 1 : 0

  policy_set_id = tfe_policy_set.this[0].id
  workspace_id  = tfe_workspace.this.id
}

#------------------------------------------------------------------------------
# SMTP settings (optional) - required for email notifications to be delivered
#------------------------------------------------------------------------------
resource "tfe_admin_smtp_settings" "this" {
  count = local.smtp_enabled ? 1 : 0

  enabled  = true
  host     = var.smtp_host
  port     = var.smtp_port
  sender   = var.smtp_sender
  auth     = var.smtp_auth
  username = var.smtp_auth == "none" ? null : var.smtp_username

  password_wo         = var.smtp_auth == "none" ? null : var.smtp_password
  password_wo_version = var.smtp_auth == "none" ? null : var.smtp_password_version
}

#------------------------------------------------------------------------------
# Microsoft Teams
#------------------------------------------------------------------------------
resource "tfe_notification_configuration" "teams" {
  count = local.teams_enabled ? 1 : 0

  name             = "teams"
  enabled          = true
  destination_type = "microsoft-teams"
  url_wo           = var.teams_webhook_url
  triggers         = var.notification_triggers
  workspace_id     = tfe_workspace.this.id
}

#------------------------------------------------------------------------------
# Email
#------------------------------------------------------------------------------
resource "tfe_notification_configuration" "email" {
  count = local.email_enabled ? 1 : 0

  name             = "email"
  enabled          = true
  destination_type = "email"
  email_addresses  = var.email_addresses
  triggers         = var.notification_triggers
  workspace_id     = tfe_workspace.this.id

  depends_on = [tfe_admin_smtp_settings.this]
}
