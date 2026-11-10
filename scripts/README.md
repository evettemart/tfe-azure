# Scripts

Helper scripts for deploying and testing TFE on Azure. Run them from the repo root, for example `bash tfe-azure/scripts/bootstrap.sh`. Each script has a usage header at the top.

| Script | What it does | When to run it |
|---|---|---|
| [`bootstrap.sh`](bootstrap.sh) | Creates the bootstrap Key Vault, generates a self-signed TLS certificate, a database password and an encryption password, and uploads them (and the license) as Key Vault secrets. | **Once, before `terraform apply`.** Safe to re-run. |
| [`deploy-tfe.sh`](deploy-tfe.sh) | Copies the TFE startup script to the TFE VM through the Azure Bastion tunnel and runs it. | **After `terraform apply`**, only when the VM uses a HashiCorp-built image, because its cloud-init does not run the startup script. |
| [`setup-ubuntu-bastion.sh`](setup-ubuntu-bastion.sh) | Installs the desktop, xrdp and Chrome on the Ubuntu bastion over SSH. | After `terraform apply`, only when `ubuntu_bastion_run_setup_script = false`. Safe to re-run. |
| [`run-tf-demo-workspace-config.sh`](run-tf-demo-workspace-config.sh) | Runs `tf-demo-workspace-config/` (workspace, Sentinel policy set, notifications) from your Mac through an SSH proxy on the Ubuntu bastion. Takes `plan` (default), `apply` or `destroy`. | After TFE is running and the initial admin and organisation exist. |
| [`run-test-workspace.sh`](run-test-workspace.sh) | Runs the `test-workspace/` demo on the TFE VM to prove that runs work end to end. Takes `apply` (default) or `plan`. | Optional smoke test, after TFE is running and you have an API token. |
| [`check-health-assessment-requirements.sh`](check-health-assessment-requirements.sh) | Reports which workspaces meet the requirements for health assessments. | Optional. Run it to see why a workspace is not getting health assessments. |
| [`cleanup.sh`](cleanup.sh) | Deletes the bootstrap Key Vault and its resource group, plus the Azure Bastion, networking resource group and Log Analytics workspace that `terraform destroy` can leave behind. | **Last**, after `terraform destroy`. Destructive. |

## Typical order

1. `bootstrap.sh`
2. `terraform -chdir=tfe-azure/main apply`
3. `deploy-tfe.sh` (only if needed, see above)
4. `setup-ubuntu-bastion.sh` (only if needed, see above)
5. Create the initial admin user and organisation (see the main README)
6. `run-tf-demo-workspace-config.sh apply`
7. `run-test-workspace.sh` (optional)