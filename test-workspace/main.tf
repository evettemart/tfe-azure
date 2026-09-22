terraform {
  cloud {
    hostname     = "tfe.azure.example.com"
    organization = "<YOUR-ORG-NAME>"

    workspaces {
      name = "test-random-string"
    }
  }

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  required_version = "~> 1.9"
}

resource "random_string" "test" {
  length  = 10
  special = false
  upper   = true
  lower   = true
  numeric = true
}

output "random_string" {
  value       = random_string.test.result
  description = "The generated 10-character random string."
}
