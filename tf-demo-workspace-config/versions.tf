# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

terraform {
  # 1.11+ is required for write-only arguments (url_wo, password_wo).
  required_version = ">= 1.11"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = ">= 0.82, < 1.0"
    }
  }
}
