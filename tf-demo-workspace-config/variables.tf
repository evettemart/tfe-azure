# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# TFE connection
# The API token is read from the TFE_TOKEN environment variable. It must be a
# site admin token when `configure_smtp` is true.
#------------------------------------------------------------------------------
variable "tfe_hostname" {
  type        = string
  description = "Hostname of the Terraform Enterprise instance, e.g. tfe.azure.example.com."
}

variable "tfe_organization" {
  type        = string
  description = "Name of an existing TFE organization. The workspace is created in it."
}

variable "tfe_ssl_skip_verify" {
  type        = bool
  description = "Skip TLS certificate verification when calling the TFE API. Only set to true when TFE uses a private or self-signed certificate that this machine does not trust."
  default     = false
}

#------------------------------------------------------------------------------
# Workspace (always created)
#------------------------------------------------------------------------------
variable "workspace_name" {
  type        = string
  description = "Name of the workspace to create. The default matches the `cloud` block in test-workspace/main.tf."
  default     = "tf-demo-workspace"
}

variable "workspace_description" {
  type        = string
  description = "Description of the workspace."
  default     = "Demo workspace used to verify the TFE deployment."
}

variable "workspace_auto_apply" {
  type        = bool
  description = "Whether runs in the workspace apply automatically after a successful plan."
  default     = false
}

variable "workspace_terraform_version" {
  type        = string
  description = "Terraform version (or version constraint) for the workspace. When null, the provider default (latest available) is used."
  default     = null
}

variable "workspace_assessments_enabled" {
  type        = bool
  description = "Whether to regularly run health assessments (drift detection and continuous validation) on the workspace. Defaults to true. Needs TFE health assessments to be allowed for the organization, and the workspace needs a successful apply and an agent or remote execution mode that supports them."
  default     = true
}

#------------------------------------------------------------------------------
# Notifications master flag
#------------------------------------------------------------------------------
variable "enable_notifications" {
  type        = bool
  description = "Master flag for notifications. When false, no notification or SMTP resources are created, regardless of the destination settings below. The workspace is created either way."
  default     = false
}

variable "notification_triggers" {
  type        = list(string)
  description = "Events that generate a notification. Applied to both Teams and email destinations."
  default     = ["run:needs_attention", "run:errored"]

  validation {
    condition = alltrue([
      for t in var.notification_triggers : contains([
        "run:created", "run:planning", "run:needs_attention", "run:pending_apply_approval",
        "run:cost_estimated", "run:policy_override_required", "run:policies_checked",
        "run:applying", "run:completed", "run:errored", "run:run_errored", "run:run_canceled",
        "run:policy_soft_failed", "assessment:check_failure", "assessment:drifted",
        "assessment:failed", "workspace:auto_destroy_reminder", "workspace:auto_destroy_run_results",
      ], t)
    ])
    error_message = "One or more values in `notification_triggers` are not valid TFE notification triggers."
  }
}

#------------------------------------------------------------------------------
# Microsoft Teams
#------------------------------------------------------------------------------
variable "enable_teams_notifications" {
  type        = bool
  description = "Send notifications to a Microsoft Teams channel. Requires `enable_notifications` to be true and `teams_webhook_url` to be set."
  default     = false
}

variable "teams_webhook_url" {
  type        = string
  description = "Incoming webhook (workflow) URL for the Microsoft Teams channel. Required when `enable_teams_notifications` is true. Supply it via TF_VAR_teams_webhook_url rather than in a tfvars file. It is write-only and is never stored in Terraform state."
  default     = null
  ephemeral   = true

  validation {
    condition     = var.enable_teams_notifications && var.enable_notifications ? (var.teams_webhook_url != null && can(regex("^https://", var.teams_webhook_url))) : true
    error_message = "`teams_webhook_url` must be an https:// URL when `enable_teams_notifications` is true."
  }
}

#------------------------------------------------------------------------------
# Email
#------------------------------------------------------------------------------
variable "enable_email_notifications" {
  type        = bool
  description = "Send notification emails. Requires `enable_notifications` to be true, at least one address in `email_addresses`, and SMTP configured in TFE (see `configure_smtp`)."
  default     = false
}

variable "email_addresses" {
  type        = list(string)
  description = "Email addresses that receive notifications. Required when `enable_email_notifications` is true."
  default     = []

  validation {
    condition     = var.enable_email_notifications && var.enable_notifications ? length(var.email_addresses) > 0 : true
    error_message = "At least one address must be provided in `email_addresses` when `enable_email_notifications` is true."
  }

  validation {
    condition     = alltrue([for e in var.email_addresses : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every value in `email_addresses` must look like an email address."
  }
}

#------------------------------------------------------------------------------
# SMTP (TFE does not send email until this is configured)
#------------------------------------------------------------------------------
variable "configure_smtp" {
  type        = bool
  description = "Manage TFE's SMTP settings from this configuration. Leave false if SMTP is already configured in TFE. Only used when `enable_email_notifications` is true."
  default     = false
}

variable "smtp_host" {
  type        = string
  description = "Hostname of the SMTP server. Required when `configure_smtp` is true."
  default     = null
}

variable "smtp_port" {
  type        = number
  description = "Port of the SMTP server."
  default     = 587
}

variable "smtp_sender" {
  type        = string
  description = "From address used on outgoing notification emails. Required when `configure_smtp` is true."
  default     = null
}

variable "smtp_auth" {
  type        = string
  description = "SMTP authentication type: none, plain or login."
  default     = "none"

  validation {
    condition     = contains(["none", "plain", "login"], var.smtp_auth)
    error_message = "`smtp_auth` must be one of: none, plain, login."
  }
}

variable "smtp_username" {
  type        = string
  description = "SMTP username. Required when `smtp_auth` is plain or login."
  default     = null
}

variable "smtp_password_version" {
  type        = number
  description = "Increment this number to make Terraform send a changed `smtp_password` to TFE. Write-only values are not stored, so Terraform cannot detect a changed password on its own."
  default     = 1
}

variable "smtp_password" {
  type        = string
  description = "SMTP password. Required when `smtp_auth` is plain or login. Supply it via TF_VAR_smtp_password. It is write-only and is never stored in Terraform state; increment `smtp_password_version` to apply a new value."
  default     = null
  ephemeral   = true

  validation {
    condition = !(var.enable_notifications && var.enable_email_notifications && var.configure_smtp) ? true : (
      var.smtp_host != null && var.smtp_sender != null &&
      (var.smtp_auth == "none" || (var.smtp_username != null && var.smtp_password != null))
    )
    error_message = "When `configure_smtp` is true, `smtp_host` and `smtp_sender` are required, and `smtp_username` and `smtp_password` are required unless `smtp_auth` is \"none\"."
  }
}
