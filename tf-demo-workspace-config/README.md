# TFE demo workspace config

Terraform that creates the demo workspace in Terraform Enterprise (TFE) and, optionally, configures run notifications on it for **Microsoft Teams** and **email**. It is separate from the main TFE deployment and is applied **after** TFE is running.

It creates the workspace that [`test-workspace/`](../test-workspace/main.tf) points at. The default `workspace_name` is `tf-demo-workspace`, which matches the `cloud` block in that file.

Notifications are off by default. The workspace is created either way.

## What it creates

| Resource | When |
|---|---|
| `tfe_workspace` | Always. |
| `tfe_notification_configuration` (Teams) | `enable_notifications` and `enable_teams_notifications` are both true. |
| `tfe_notification_configuration` (email) | `enable_notifications` and `enable_email_notifications` are both true. |
| `tfe_admin_smtp_settings` | Email is enabled and `configure_smtp` is true. |

## Flags

| Variable | Default | Purpose |
|---|---|---|
| `enable_notifications` | `false` | Master flag for notifications. When `false`, no notification or SMTP resources are created, whatever the other flags say. |
| `enable_teams_notifications` | `false` | Create a Microsoft Teams notification on the workspace. |
| `enable_email_notifications` | `false` | Create an email notification on the workspace. |
| `configure_smtp` | `false` | Also manage TFE's SMTP settings. Only used when email is enabled. |

`notification_triggers` applies to both destinations. The default is `["run:needs_attention", "run:errored"]`.

## Workspace settings

| Variable | Default | Purpose |
|---|---|---|
| `workspace_name` | `tf-demo-workspace` | Name of the workspace. |
| `workspace_description` | `Demo workspace used to verify the TFE deployment.` | Description. |
| `workspace_auto_apply` | `false` | Apply automatically after a successful plan. |
| `workspace_terraform_version` | `null` | Terraform version or constraint. When `null`, the provider default (latest available) is used. |
| `workspace_assessments_enabled` | `true` | Turn on health assessments (drift detection and continuous validation). Set `false` to turn them off. |

## Email needs SMTP

TFE cannot deliver email until SMTP is configured. You have two choices:

1. **An admin has already configured SMTP in TFE.** Leave `configure_smtp = false`.
2. **Let Terraform manage it.** Set `configure_smtp = true` and provide `smtp_host`, `smtp_sender`, and for `plain` or `login` auth also `smtp_username` and `smtp_password`. This uses `tfe_admin_smtp_settings` and needs a **site admin** token.

> Terraform manages one SMTP settings object for the whole TFE instance. If another admin changes SMTP in the UI, the next apply will overwrite it.

## Secrets

`teams_webhook_url` and `smtp_password` are **ephemeral, write-only** values. Terraform does not store them in state or plan files. Supply them as environment variables:

```bash
export TF_VAR_teams_webhook_url="https://..."
export TF_VAR_smtp_password="..."
```

Because write-only values are not stored, Terraform cannot compare them directly. For the SMTP password, increment `smtp_password_version` to apply a new value. For the Teams URL, the `tfe` provider tracks changes automatically (its `url_wo_version` is auto-managed), so no manual step is needed.

## Usage

Requires Terraform 1.11 or later, because of the write-only arguments.

The organization must already exist. Create it in the TFE UI first, as described in the main README.

```bash
cd tfe-azure/tf-demo-workspace-config
cp terraform.tfvars.example terraform.tfvars   # then edit

export TFE_TOKEN="<token>"                     # site admin token if configure_smtp = true
export TF_VAR_teams_webhook_url="https://..."  # if Teams is enabled

terraform init
terraform plan
terraform apply
```

If TFE uses a private or self-signed certificate that your machine does not trust, set `tfe_ssl_skip_verify = true`.

Teams webhooks are created in Teams as a **Workflow** that posts to a channel. TFE sends it a notification payload.

## Relationship to `run-test-workspace.sh`

[`scripts/run-test-workspace.sh`](../scripts/run-test-workspace.sh) runs `terraform init` against the `cloud` block in `test-workspace/main.tf`, which creates the workspace automatically if it does not exist.

If you create the workspace here first, that script uses it instead. Creating it in this folder is the way to get a workspace that already has notifications configured.

## Tests

The tests use a mocked provider, so no TFE instance is needed:

```bash
terraform test
```

> `terraform test` also loads `terraform.tfvars` from this folder, and the tests assume the defaults (everything off). If your `terraform.tfvars` enables notifications, some tests fail for that reason. Move it aside while testing: `mv terraform.tfvars /tmp/ && terraform test; mv /tmp/terraform.tfvars .`

They check that the workspace is always created, that the master flag creates no notification resources when off, that each destination is created only when enabled, that SMTP is only managed when email is on, and that the input validation rules reject bad values.

## Not covered

- **Project-level or team-level notifications.** Only workspace notifications are configured. The provider also has `tfe_project_notification_configuration` and `tfe_team_notification_configuration`.
- **Other workspace settings.** VCS connection, variables, execution mode and agent pools are not managed here.
- **Organization creation.** The organization must already exist.
