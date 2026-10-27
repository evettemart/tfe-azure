# Changelog

Changes made in this repository, newest first. The entries from `v1.0.0` down are the upstream HashiCorp module history, kept for reference.

## Unreleased

### Breaking
* Removed the Azure Monitor workbook. The `create_workbook` variable and the `workbook_url` output no longer exist. The next `terraform apply` destroys the existing workbook; the Portal dashboard (`create_dashboard`) is unchanged.

### Added
* New outputs: `resource_group_name`, `vmss_name`, `load_balancer_ip`, `vnet_id`, `networking_resource_group_name` and `azure_bastion_name`.
* `event_hub_ingestion.tf` and the `create_event_hub_log_analytics_ingestion` variable. A Data Collection Rule reads the Event Hub and writes `component_s` and `log_s` to the `tfe_fluent_bit_CL` table, so `dashboards/TFE.json` keeps working. Use it with `create_event_hub = true` and `create_log_analytics_workspace = true`. The ingestion identity gets the Azure Event Hubs Data Receiver role on the hub. **Known issue:** Azure rejects the Data Collection Rule on a `PerGB2018` workspace (`Event Hub data imports are only available with 'LACluster' and 'CapacityReservation' SKUs`), so leave it off unless the workspace is changed. See "Event Hub to Log Analytics" in the README.
* `scripts/README.md`, which lists each script, when to run it and the usual order.
* `docs/images/tfe-azure-deployment.svg`, a diagram of what this repo deploys.

### Changed
* Rewrote the main `README.md`: a short overview and deploy sequence, then the existing reference sections. The terraform-docs block is regenerated.
* `sentinel/README.md`: split deployment into "Manual Deployment into TFE" and "Automated Deployment to TFE", which points at `tf-demo-workspace-config`.
* `main/terraform.tfvars.example` and `.env.local.example` now list the networking, Log Analytics, image factory, Ubuntu bastion, Azure login and TFE token settings.

## Earlier changes in this repository

### Sentinel policy set automation (#11)
* `tf-demo-workspace-config` uploads `sentinel/` as a policy set and enables it on the demo workspace, with `enable_policy_set` and related variables.
* `sentinel/.sentinel/` (created by `sentinel test`) is git-ignored.

### Demo workspace and Ubuntu bastion (#10)
* Added an optional Ubuntu bastion (`ubuntu_bastion.tf`) with an XFCE desktop, xrdp and Chrome, and the `ubuntu_bastion_*` variables. `scripts/setup-ubuntu-bastion.sh` runs the setup over SSH when `ubuntu_bastion_run_setup_script = false`.
* Added `tf-demo-workspace-config/`, which uses the `tfe` provider to create a workspace with health assessments and optional Teams and email notifications. `scripts/run-tf-demo-workspace-config.sh` runs it from a Mac through an SSH SOCKS proxy on the Ubuntu bastion.
* `scripts/run-test-workspace.sh` gained a `plan` option.
* Removed the Windows bastion (`windows_bastion.tf`) and the placeholder `tests/` READMEs.

### Fixes (Sentinel tests, tunnel)
* Added unit tests for the Sentinel policies under `sentinel/test/`.
* Fixed the Azure Bastion tunnel handling in `scripts/deploy-tfe.sh`.

### Event Hub log forwarding (#7)
* Added optional Event Hub log forwarding (`event_hub.tf`, a Fluent Bit Event Hub template and the `event_hub_*` variables and outputs).

### Sentinel policies (#6)
* Added the Sentinel policy set in `sentinel/`: authorized providers, provider and module version rules, module sources, mandatory modules, mandatory tags, outputs presence, and no direct module-covered resources.

### Health assessment check (#5)
* Added `scripts/check-health-assessment-requirements.sh`, which reports which workspaces meet the requirements for health assessments.

### Portal dashboard (#4)
* Added the Azure Portal dashboard (`dashboard.tf`, `dashboards/TFE.json`) and the `create_dashboard` variable. It reads the Fluent Bit logs in Log Analytics.

### Windows bastion and deploy script (#2, #3)
* Added a Windows bastion and `scripts/deploy-tfe.sh`, which copies the startup script to the TFE VM through the Azure Bastion tunnel. (The Windows bastion was later replaced by the Ubuntu bastion.)

### Networking, bootstrap and cleanup (#1)
* Optional creation of the VNet, subnets and Azure Bastion (`networking.tf`) and a Log Analytics workspace (`log_analytics.tf`).
* Added `scripts/bootstrap.sh` (Key Vault, certificates and secrets) and `scripts/cleanup.sh`.
* Switched the VM scale set to images from the shared image gallery.

### Initial upload
* Imported the upstream `terraform-azurerm-terraform-enterprise-hvd` module.

---

## Upstream history (v1.0.0 and earlier)

### v1.0.0

#### What's Changed
* add template sync workflow by @jeffmccollum in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/9
* Add Terraform Validate workflow by @jeffmccollum in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/10
* chore: Pass value of `var.is_govcloud_region` via main.tf and update variables.tf for govcloud by @jkellner-hashi in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/11
* fix: Update Azure endpoint for govcloud region in compute.tf by @jkellner-hashi in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/12
* upstream merge template repository by @github-actions[bot] in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/13
* bump docker default version by @abuxton in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/14
* Abc template user data by @abuxton in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/15
* upstream merge template repository by @github-actions[bot] in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/16
* upstream merge template repository by @github-actions[bot] in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/17
* Chore/abc-add-workflow-permissions by @abuxton in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/18
* [IND-4227] [COMPLIANCE] Update Copyright Headers (Batch 1 of 1) by @oss-core-libraries-dashboard[bot] in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/19
* feat: add readiness-aware admin console support by @abuxton in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/22
* chore/manual template sync by @abuxton in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/25

#### New Contributors
* @github-actions[bot] made their first contribution in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/13
* @abuxton made their first contribution in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/14
* @oss-core-libraries-dashboard[bot] made their first contribution in https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/pull/19

**Full Changelog**: https://github.com/hashicorp/terraform-azurerm-terraform-enterprise-hvd/compare/0.2.0...1.0.0
