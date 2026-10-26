# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

# Offline tests: the tfe provider is mocked, so no TFE instance is needed.
# Run from the tf-demo-workspace-config/ directory with: terraform test

mock_provider "tfe" {}

variables {
  tfe_hostname     = "tfe.example.com"
  tfe_organization = "org"
}

run "workspace_is_created_with_everything_off" {
  command = plan

  assert {
    condition     = tfe_workspace.this.name == "tf-demo-workspace" && tfe_workspace.this.organization == "org"
    error_message = "The workspace must be created with the default name in the given organization."
  }

  assert {
    condition     = length(tfe_notification_configuration.teams) == 0 && length(tfe_notification_configuration.email) == 0 && length(tfe_admin_smtp_settings.this) == 0
    error_message = "No notification or SMTP resources should exist by default."
  }
}

run "health_assessments_enabled_by_default" {
  command = plan

  assert {
    condition     = tfe_workspace.this.assessments_enabled == true
    error_message = "Health assessments must be enabled on the workspace by default."
  }
}

run "health_assessments_can_be_disabled" {
  command = plan

  variables {
    workspace_assessments_enabled = false
  }

  assert {
    condition     = tfe_workspace.this.assessments_enabled == false
    error_message = "workspace_assessments_enabled = false must disable health assessments."
  }
}

run "workspace_name_is_configurable" {
  command = plan

  variables {
    workspace_name = "my-demo"
  }

  assert {
    condition     = tfe_workspace.this.name == "my-demo"
    error_message = "workspace_name must set the workspace name."
  }
}

run "flag_off_creates_no_notifications_even_if_destinations_requested" {
  command = plan

  variables {
    enable_notifications       = false
    enable_teams_notifications = true
    teams_webhook_url          = "https://example.com/hook"
    enable_email_notifications = true
    email_addresses            = ["a@example.com"]
    configure_smtp             = true
    smtp_host                  = "smtp.example.com"
    smtp_sender                = "noreply@example.com"
  }

  assert {
    condition     = length(tfe_notification_configuration.teams) == 0 && length(tfe_notification_configuration.email) == 0 && length(tfe_admin_smtp_settings.this) == 0
    error_message = "No notification or SMTP resources should be created when enable_notifications is false."
  }

  assert {
    condition     = tfe_workspace.this.name == "tf-demo-workspace"
    error_message = "The workspace must still be created when notifications are off."
  }
}

run "teams_only" {
  command = plan

  variables {
    enable_notifications       = true
    enable_teams_notifications = true
    teams_webhook_url          = "https://example.com/hook"
  }

  assert {
    condition     = length(tfe_notification_configuration.teams) == 1 && length(tfe_notification_configuration.email) == 0 && length(tfe_admin_smtp_settings.this) == 0
    error_message = "Expected one Teams configuration and no email or SMTP resources."
  }

  assert {
    condition     = tfe_notification_configuration.teams[0].destination_type == "microsoft-teams"
    error_message = "Teams configuration must use the microsoft-teams destination type."
  }
}

run "email_only_without_managing_smtp" {
  command = plan

  variables {
    enable_notifications       = true
    enable_email_notifications = true
    email_addresses            = ["a@example.com", "b@example.com"]
  }

  assert {
    condition     = length(tfe_notification_configuration.email) == 1 && length(tfe_notification_configuration.teams) == 0 && length(tfe_admin_smtp_settings.this) == 0
    error_message = "Expected one email configuration, no Teams, and no SMTP management."
  }

  assert {
    condition     = tfe_notification_configuration.email[0].destination_type == "email"
    error_message = "Email configuration must use the email destination type."
  }
}

run "teams_and_email_with_smtp" {
  command = plan

  variables {
    enable_notifications       = true
    enable_teams_notifications = true
    teams_webhook_url          = "https://example.com/hook"
    enable_email_notifications = true
    email_addresses            = ["a@example.com"]
    configure_smtp             = true
    smtp_host                  = "smtp.example.com"
    smtp_sender                = "noreply@example.com"
    smtp_auth                  = "login"
    smtp_username              = "user"
    smtp_password              = "pw"
  }

  assert {
    condition     = length(tfe_notification_configuration.teams) == 1 && length(tfe_notification_configuration.email) == 1 && length(tfe_admin_smtp_settings.this) == 1
    error_message = "Expected Teams, email and one SMTP settings resource."
  }
}

run "smtp_not_managed_when_email_disabled" {
  command = plan

  variables {
    enable_notifications = true
    configure_smtp       = true
    smtp_host            = "smtp.example.com"
    smtp_sender          = "noreply@example.com"
  }

  assert {
    condition     = length(tfe_admin_smtp_settings.this) == 0
    error_message = "SMTP must not be managed unless email notifications are enabled."
  }
}

run "teams_enabled_without_url_is_rejected" {
  command = plan

  variables {
    enable_notifications       = true
    enable_teams_notifications = true
  }

  expect_failures = [var.teams_webhook_url]
}

run "email_enabled_without_addresses_is_rejected" {
  command = plan

  variables {
    enable_notifications       = true
    enable_email_notifications = true
  }

  expect_failures = [var.email_addresses]
}

run "smtp_login_without_password_is_rejected" {
  command = plan

  variables {
    enable_notifications       = true
    enable_email_notifications = true
    email_addresses            = ["a@example.com"]
    configure_smtp             = true
    smtp_host                  = "smtp.example.com"
    smtp_sender                = "noreply@example.com"
    smtp_auth                  = "login"
    smtp_username              = "user"
  }

  expect_failures = [var.smtp_password]
}
