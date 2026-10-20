# Sentinel Policy Set for Terraform Enterprise (TFE)

This folder contains the complete Sentinel policy suite mapped directly to the organizational governance and compliance controls.

## Policy Mapping & Enforcement Table

| # | Policy Name | File | Description | Action on Failure | Notes / Approved Patterns |
|---|-------------|------|-------------|-------------------|---------------------------|
| 1 | **Authorized Providers** | [`verify_authorized_providers.sentinel`](verify_authorized_providers.sentinel) | Validates that only explicitly approved providers are declared in `required_providers`. | **Soft Mandatory** | `hashicorp/aws`, `hashicorp/azurerm`, `hashicorp/google`, `hashicorp/random`, `hashicorp/tls`, `azure/azapi` |
| 2 | **Provider Version Constraint** | [`verify_provider_version_constraint.sentinel`](verify_provider_version_constraint.sentinel) | Validates that provider declarations include a pessimistic version constraint. | **Soft Mandatory** | `version = "~> <major>.<minor>.0"` |
| 3 | **Module Sources** | [`verify_module_sources.sentinel`](verify_module_sources.sentinel) | Validates that all remote modules are sourced from approved enterprise registries. | **Hard Mandatory** | `tfe.windtre.it`, `tfe.azu.windtre.it` |
| 4 | **Module Version Presence** | [`verify_module_version_presence.sentinel`](verify_module_version_presence.sentinel) | Ensures every remote module declaration explicitly defines a `version` attribute. | **Soft Mandatory** | Version attribute must not be empty. |
| 5 | **Module Version Format** | [`verify_module_version_format.sentinel`](verify_module_version_format.sentinel) | Validates that module version constraints use major-version boundary expressions. | **Advisory** | `version = "~> <major>"` or `version = "~> <major>.0"` |
| 6 | **Mandatory Modules Presence** | [`verify_mandatory_modules.sentinel`](verify_mandatory_modules.sentinel) | Enforces the presence of standard project setting modules for each project/CSP. | **Advisory** | `[approved-host]/[registry]/std_project_setting/(aws\|google\|azurerm)` |
| 7 | **Mandatory Tags** | [`verify_mandatory_tags.sentinel`](verify_mandatory_tags.sentinel) | Validates that resource types across CSPs include mandatory organization tags. | **Soft Mandatory** | `Environment`, `Owner`, `Project` (configurable per policy set) |
| 8 | **Terraform Outputs Presence** | [`verify_terraform_outputs_presence.sentinel`](verify_terraform_outputs_presence.sentinel) | Ensures that Terraform configurations define at least one output. | **Advisory** | `length(tfconfig.outputs) > 0` |
| 9 | **No Direct Module-Covered Resources** | [`verify_no_direct_module_covered_resources.sentinel`](verify_no_direct_module_covered_resources.sentinel) | Prevents direct creation of resource types where a standard module is mandatory. | **Soft Mandatory** | Enforces usage of standard modules instead of direct resource blocks in root configuration. |

## Deployment into TFE

You can link this folder directly as a **Policy Set** in your Terraform Enterprise Organization:
1. In TFE, navigate to **Settings** &rarr; **Policy Sets** &rarr; **Create new policy set**.
2. Connect your VCS repository and point the path to `/sentinel` (or `tfe-azure/sentinel`).
3. Set scope to **All workspaces** or selected workspaces.
