# TFE Test — Random String

A minimal Terraform configuration to verify that TFE is working end-to-end.
It generates a 10-character random string using the `random` provider and
outputs the result.

## Prerequisites

- TFE is running and accessible at `https://tfe.azure.example.com`
- You have created an organisation and a workspace named `test-random-string`
- Terraform CLI `>= 1.9` installed on your Mac
- You are authenticated to TFE (`terraform login tfe.azure.example.com`)

## Setup

1. Update `main.tf` — replace `<YOUR-ORG-NAME>` with your TFE organisation name

2. Initialise:
   ```bash
   terraform init
   ```

3. Apply:
   ```bash
   terraform apply
   ```

4. Check the output:
   ```
   random_string = "aB3xK7mNpQ"
   ```

Watch the run in the TFE UI under **Workspaces → test-random-string → Runs**.
