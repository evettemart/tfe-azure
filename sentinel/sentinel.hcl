# Sentinel Policy Set Configuration for Terraform Enterprise (TFE)

policy "verify_authorized_providers" {
  source            = "./verify_authorized_providers.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "verify_provider_version_constraint" {
  source            = "./verify_provider_version_constraint.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "verify_module_sources" {
  source            = "./verify_module_sources.sentinel"
  enforcement_level = "hard-mandatory"
}

policy "verify_module_version_presence" {
  source            = "./verify_module_version_presence.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "verify_module_version_format" {
  source            = "./verify_module_version_format.sentinel"
  enforcement_level = "advisory"
}

policy "verify_mandatory_modules" {
  source            = "./verify_mandatory_modules.sentinel"
  enforcement_level = "advisory"
}

policy "verify_mandatory_tags" {
  source            = "./verify_mandatory_tags.sentinel"
  enforcement_level = "soft-mandatory"
}

policy "verify_terraform_outputs_presence" {
  source            = "./verify_terraform_outputs_presence.sentinel"
  enforcement_level = "advisory"
}

policy "verify_no_direct_module_covered_resources" {
  source            = "./verify_no_direct_module_covered_resources.sentinel"
  enforcement_level = "soft-mandatory"
}
