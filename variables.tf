# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Common
#------------------------------------------------------------------------------
variable "create_resource_group" {
  type        = bool
  description = "Boolean to create a new resource group for this TFE deployment."
  default     = true
}

variable "resource_group_name" {
  type        = string
  description = "Name of resource group for this TFE deployment. Must be an existing resource group if `create_resource_group` is `false`."
}

variable "location" {
  type        = string
  description = "Azure region for this TFE deployment."

  validation {
    condition     = var.is_govcloud_region ? contains(["usgovvirginia", "usgovtexas", "usgovarizona", "usdodcentral", "usdodeast"], var.location) : contains(["eastus", "westus", "centralus", "eastus2", "westus2", "westeurope", "northeurope", "southeastasia", "eastasia", "australiaeast", "australiasoutheast", "uksouth", "ukwest", "canadacentral", "canadaeast", "southindia", "centralindia", "westindia", "japaneast", "japanwest", "koreacentral", "koreasouth", "francecentral", "southafricanorth", "uaenorth", "brazilsouth", "switzerlandnorth", "germanywestcentral", "norwayeast", "westcentralus"], var.location)
    error_message = var.is_govcloud_region ? "Value is not a valid Azure Government region." : "Value is not a valid Azure region."
  }
}

variable "friendly_name_prefix" {
  type        = string
  description = "Friendly name prefix used for uniquely naming all Azure resources for this deployment. Most commonly set to either an environment (e.g. 'sandbox', 'prod'), a team name, or a project name."

  validation {
    condition     = can(regex("^[[:alnum:]]+$", var.friendly_name_prefix)) && length(var.friendly_name_prefix) < 13
    error_message = "Value can only contain alphanumeric characters and must be less than 13 characters."
  }

  validation {
    condition     = !strcontains(lower(var.friendly_name_prefix), "tfe")
    error_message = "Value must not contain the substring 'tfe' to avoid redundancy in resource naming."
  }
}

variable "common_tags" {
  type        = map(string)
  description = "Map of common tags for taggable Azure resources."
  default     = {}
}

variable "availability_zones" {
  type        = set(string)
  description = "List of Azure availability zones to spread TFE resources across."
  default     = ["1", "2", "3"]

  validation {
    condition     = alltrue([for az in var.availability_zones : contains(["1", "2", "3"], az)])
    error_message = "Availability zone must be one of, or a combination of '1', '2', '3'."
  }
}

variable "is_secondary_region" {
  type        = bool
  description = "Boolean indicating whether this TFE deployment is for 'primary' region or 'secondary' region."
  default     = false
}

variable "is_govcloud_region" {
  type        = bool
  description = "Boolean indicating whether this TFE deployment is in an Azure Government Cloud region."
  default     = false
}

variable "tfe_primary_resource_group_name" {
  type        = string
  description = "Name of existing resource group of TFE deployment in primary region. Only set when `is_secondary_region` is `true`. "
  default     = null

  validation {
    condition     = var.is_secondary_region ? var.tfe_primary_resource_group_name != null : true
    error_message = "Value must be set when `is_secondary_region` is `true`."
  }

  validation {
    condition     = !var.is_secondary_region ? var.tfe_primary_resource_group_name == null : true
    error_message = "Value must be `null` when `is_secondary_region` is `false`."
  }
}

#------------------------------------------------------------------------------
# Bootstrap
#------------------------------------------------------------------------------
variable "bootstrap_keyvault_name" {
  type        = string
  description = "Name of the 'bootstrap' Key Vault to use for bootstrapping TFE deployment."
}

variable "bootstrap_keyvault_rg_name" {
  type        = string
  description = "Name of the Resource Group where the 'bootstrap' Key Vault resides."
}

variable "bootstrap_keyvault_create_reader_role_assignment" {
  type        = bool
  description = "Boolean to create an Azure RBAC Reader role assignment on the bootstrap Key Vault for the TFE user-assigned identity. Disable this when Key Vault access policies are sufficient and the deploying principal cannot write role assignments."
  default     = true
}

variable "use_key_vault_rbac" {
  type        = bool
  description = "Whether to use Azure RBAC instead of legacy access policies for Key Vault data-plane access."
  default     = false
}

variable "tfe_license_keyvault_secret_id" {
  type        = string
  description = "ID of Key Vault secret containing TFE license."
}

variable "tfe_tls_cert_keyvault_secret_id" {
  type        = string
  description = "ID of Key Vault secret containing TFE TLS certificate."
}

variable "tfe_tls_privkey_keyvault_secret_id" {
  type        = string
  description = "ID of Key Vault secret containing TFE TLS private key."
}

variable "tfe_tls_ca_bundle_keyvault_secret_id" {
  type        = string
  description = "ID of Key Vault secret containing TFE TLS custom CA bundle."
}

variable "tfe_encryption_password_keyvault_secret_id" {
  type        = string
  description = "ID of Key Vault secret containing TFE encryption password."
}

variable "tfe_image_repository_url" {
  type        = string
  description = "Repository for the TFE image. Only change this if you are hosting the TFE container image in your own custom repository."
  default     = "images.releases.hashicorp.com"
}

variable "tfe_image_name" {
  type        = string
  description = "Name of the TFE container image. Only change this if you are hosting the TFE container image in your own custom repository."
  default     = "hashicorp/terraform-enterprise"
}

variable "tfe_image_tag" {
  type        = string
  description = "Tag for the TFE container image. This represents the version of TFE to deploy."
  default     = "1.0.1"

  validation {
    condition = (
      can(regex("^v[0-9]{6}-[0-9]+$", var.tfe_image_tag)) ||
      can(regex("^v?[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.tfe_image_tag)) ||
      can(regex("^[0-9a-f]{7,}$", var.tfe_image_tag))
    )
    error_message = "tfe_image_tag must be a supported calver tag (for example v202409-3), semver tag (for example 1.2.1 or v1.2.1), or raw commit hash."
  }
}

variable "tfe_image_repository_username" {
  type        = string
  description = "Username for container registry where TFE container image is hosted. Only change this if you are hosting the TFE container image in your own custom repository."
  default     = "terraform"
}

variable "tfe_image_repository_password" {
  type        = string
  description = "Password for container registry where TFE container image is hosted. Only set this if you are hosting the TFE container image in your own custom repository."
  default     = null

  validation {
    condition     = var.tfe_image_repository_url == "images.releases.hashicorp.com" ? var.tfe_image_repository_password == null : true
    error_message = "Value must be `null` when `tfe_image_repository_url` is set to the default of `images.releases.hashicorp.com` (the TFE license is the password)."
  }
}

#------------------------------------------------------------------------------
# TFE configuration settings
#------------------------------------------------------------------------------
variable "tfe_fqdn" {
  type        = string
  description = "Fully qualified domain name of TFE instance. This name should resolve to the load balancer IP address and will be what clients use to access TFE."
}

variable "tfe_capacity_concurrency" {
  type        = number
  description = "Number of concurrent runs TFE can handle."
  default     = 10
}

variable "tfe_capacity_cpu" {
  type        = number
  description = "Number of CPU cores for TFE."
  default     = 0
}

variable "tfe_capacity_memory" {
  type        = number
  description = "Amount of memory in MB for TFE."
  default     = 2048
}

variable "tfe_license_reporting_opt_out" {
  type        = bool
  description = "Boolean to opt out of license reporting."
  default     = false
}

variable "tfe_operational_mode" {
  type        = string
  description = "[Operational mode](https://developer.hashicorp.com/terraform/enterprise/flexible-deployments/install/operation-modes) for TFE. Valid values are `active-active` or `external`."
  default     = "active-active"

  validation {
    condition     = var.tfe_operational_mode == "active-active" || var.tfe_operational_mode == "external"
    error_message = "Value must be `active-active` or `external`."
  }
}

variable "tfe_http_port" {
  type        = number
  description = "HTTP port for TFE application containers to listen on."
  default     = 8080

  validation {
    condition     = var.container_runtime == "podman" ? var.tfe_http_port != 80 : true
    error_message = "Value must not be `80` when `container_runtime` is `podman` to avoid conflicts."
  }
}

variable "tfe_https_port" {
  type        = number
  description = "HTTPS port for TFE application containers to listen on."
  default     = 8443

  validation {
    condition     = var.container_runtime == "podman" ? var.tfe_https_port != 443 : true
    error_message = "Value must not be `80` when `container_runtime` is `podman` to avoid conflicts."
  }
}

variable "tfe_admin_https_port" {
  type        = number
  description = "Port the TFE application container listens on for system (admin) API endpoint HTTPS traffic."
  default     = 9443

  validation {
    condition     = var.tfe_admin_https_port != var.tfe_https_port && var.tfe_admin_https_port != var.tfe_http_port
    error_message = "`tfe_admin_https_port` must not be the same as `tfe_https_port` or `tfe_http_port` to avoid conflicts."
  }
}

variable "tfe_run_pipeline_image" {
  type        = string
  description = "Name of the Docker image to use for the run pipeline driver."
  default     = null
}

variable "tfe_metrics_enable" {
  type        = bool
  description = "Boolean to enable metrics."
  default     = false
}

variable "tfe_metrics_http_port" {
  type        = number
  description = "HTTP port for TFE metrics endpoint."
  default     = 9090
}

variable "tfe_metrics_https_port" {
  type        = number
  description = "HTTPS port for TFE metrics endpoint."
  default     = 9091
}

variable "tfe_admin_console_disabled" {
  type        = bool
  description = "Boolean to disable the TFE Admin Console for advanced troubleshooting and diagnostics."
  default     = true
}

variable "cidr_allow_ingress_tfe_admin_console" {
  type        = list(string)
  description = "List of CIDR ranges that should be allowed to reach the admin console port. This module does not create NSG rules, so use this as the contract for your prerequisite firewall policy."
  default     = null

  validation {
    condition     = !var.tfe_admin_console_disabled ? var.cidr_allow_ingress_tfe_admin_console != null : true
    error_message = "Value must be set when `tfe_admin_console_disabled` is `false`."
  }

  validation {
    condition = var.cidr_allow_ingress_tfe_admin_console != null ? alltrue([
      for cidr in var.cidr_allow_ingress_tfe_admin_console : can(cidrhost(cidr, 0))
    ]) : true
    error_message = "All values must be valid CIDR notation."
  }
}

variable "tfe_tls_enforce" {
  type        = bool
  description = "Boolean to enforce TLS, Strict-Transport-Security headers, and secure cookies within TFE."
  default     = false
}

variable "tfe_vault_disable_mlock" {
  type        = bool
  description = "Boolean to disable mlock for internal Vault."
  default     = false
}

variable "tfe_hairpin_addressing" {
  type        = bool
  description = "Boolean to enable hairpin addressing for layer 4 load balancer with loopback prevention. Must be `true` when `lb_is_internal` is `true`."
  default     = true

  validation {
    condition     = var.lb_is_internal ? var.tfe_hairpin_addressing : true
    error_message = "Value must be `true` when `lb_type` is `nlb` and `lb_is_internal` is `true`."
  }
}

variable "tfe_run_pipeline_docker_network" {
  type        = string
  description = "Docker network where the containers that execute Terraform runs will be created. The network must already exist, it will not be created automatically. Leave as `null` to use the default network."
  default     = null
}

#------------------------------------------------------------------------------
# Networking
#------------------------------------------------------------------------------
variable "vnet_id" {
  type        = string
  description = "ID of VNet where TFE will be deployed. Only required when `create_networking_resources` is `false`."
  default     = null
}

variable "create_lb" {
  type        = bool
  description = "Boolean to create an Azure Load Balancer for TFE."
  default     = true
}

variable "lb_subnet_id" {
  type        = string
  description = "Subnet ID for Azure load balancer."
  default     = null
}

variable "lb_is_internal" {
  type        = bool
  description = "Boolean to create an internal or external Azure Load Balancer for TFE."
  default     = true
}

variable "lb_private_ip" {
  type        = string
  description = "Private IP address for internal Azure Load Balancer. Only valid when `lb_is_internal` is `true`."
  default     = null
}

variable "vm_subnet_id" {
  type        = string
  description = "Subnet ID for Virtual Machine Scaleset (VMSS). Only required when `create_networking_resources` is `false`."
  default     = null
}

variable "db_subnet_id" {
  type        = string
  description = "Subnet ID for PostgreSQL database. Only required when `create_networking_resources` is `false`."
  default     = null
}

variable "redis_subnet_id" {
  type        = string
  description = "Subnet ID for Redis cache."
  default     = null
}

variable "secondary_vm_subnet_id" {
  type        = string
  description = "VM subnet ID of existing TFE virtual machine scaleset (VMSS) in secondary region. Used to allow TFE VMs in secondary region access to TFE storage account in primary region."
  default     = null

  validation {
    condition     = var.is_secondary_region ? var.secondary_vm_subnet_id == null : true
    error_message = "Value must be `null` when `is_secondary_region` is `true`, as the TFE storage account only exists in the primary region."
  }
}

#------------------------------------------------------------------------------
# DNS
#------------------------------------------------------------------------------
variable "create_public_dns_zone" {
  type        = bool
  description = "Boolean to create a new public Azure DNS zone for TFE. When `true`, a new `azurerm_dns_zone` is created using `public_dns_zone_name` in the TFE resource group, and a DNS A record is automatically added that resolves `tfe_fqdn` to the load balancer public IP. Requires `lb_is_internal` to be `false` and `create_lb` to be `true`."
  default     = false

  validation {
    condition     = var.create_public_dns_zone ? !var.lb_is_internal : true
    error_message = "Value must be `false` when `lb_is_internal` is `true` — a public DNS zone requires a public load balancer IP."
  }

  validation {
    condition     = var.create_public_dns_zone ? var.create_lb : true
    error_message = "Value must be `false` when `create_lb` is `false` — a public DNS zone requires a load balancer to exist."
  }
}

variable "create_tfe_public_dns_record" {
  type        = bool
  description = "Boolean to create a DNS record for TFE in a public Azure DNS zone. A `public_dns_zone_name` must also be provided when `true`. Set this when using an *existing* public DNS zone; use `create_public_dns_zone` instead to have Terraform create a new zone."
  default     = false
}

variable "public_dns_zone_name" {
  type        = string
  description = "Name of the public Azure DNS zone. When `create_public_dns_zone` is `true` this zone is created; when `create_tfe_public_dns_record` is `true` this must be an existing zone. Required when either flag is `true`."
  default     = null

  validation {
    condition     = var.create_tfe_public_dns_record ? var.public_dns_zone_name != null : true
    error_message = "A value is required when `create_tfe_public_dns_record` is `true`."
  }

  validation {
    condition     = var.create_public_dns_zone ? var.public_dns_zone_name != null : true
    error_message = "A value is required when `create_public_dns_zone` is `true`."
  }
}

variable "public_dns_zone_rg_name" {
  type        = string
  description = "Name of Resource Group where `public_dns_zone_name` resides. Required when `create_tfe_public_dns_record` is `true` (existing zone lookup). When `create_public_dns_zone` is `true` the zone is created in the TFE resource group and this variable is ignored."
  default     = null

  validation {
    condition     = var.create_tfe_public_dns_record && !var.create_public_dns_zone ? var.public_dns_zone_rg_name != null : true
    error_message = "A value is required when `create_tfe_public_dns_record` is `true` and `create_public_dns_zone` is `false`."
  }
}

variable "create_tfe_private_dns_record" {
  type        = bool
  description = "Boolean to create a DNS record for TFE in a private Azure DNS zone. A `private_dns_zone_name` must also be provided when `true`."
  default     = false
}

variable "private_dns_zone_name" {
  type        = string
  description = "Name of existing private Azure DNS zone to create DNS record in. Required when `create_tfe_private_dns_record` is `true`."
  default     = null

  validation {
    condition     = var.create_tfe_private_dns_record ? var.private_dns_zone_name != null : true
    error_message = "A value is required when `create_tfe_private_dns_record` is `true`."
  }
}

variable "private_dns_zone_rg_name" {
  type        = string
  description = "Name of Resource Group where `private_dns_zone_name` resides. Required when `create_tfe_private_dns_record` is `true`."
  default     = null

  validation {
    condition     = var.private_dns_zone_name != null ? var.private_dns_zone_rg_name != null : true
    error_message = "A value is required when `private_dns_zone_name` is not `null`."
  }
}

#------------------------------------------------------------------------------
# Compute
#------------------------------------------------------------------------------
variable "vmss_instance_count" {
  type        = number
  description = "Number of VM instances to run in the Virtual Machine Scaleset (VMSS)."
  default     = 1
}

variable "vm_sku" {
  type        = string
  description = "SKU for VM size for the VMSS."
  default     = "Standard_D4s_v4"

  validation {
    condition     = can(regex("^[A-Za-z0-9_]+$", var.vm_sku))
    error_message = "Value can only contain alphanumeric characters and underscores."
  }
}

variable "vm_admin_username" {
  type        = string
  description = "Admin username for VMs in VMSS."
  default     = "tfeadmin"
}

variable "vm_ssh_public_key" {
  type        = string
  description = "SSH public key for VMs in VMSS."
  default     = null
}

variable "vm_os_image" {
  description = "The OS image to use for the VM. Options are: redhat8, redhat9, ubuntu2204, ubuntu2404."
  type        = string
  default     = "redhat9"

  validation {
    condition     = contains(["redhat8", "redhat9", "ubuntu2204", "ubuntu2404"], var.vm_os_image)
    error_message = "Value must be one of 'redhat8', 'redhat9', 'ubuntu2204', or 'ubuntu2404'."
  }
}

variable "image_factory_subscription_id" {
  type        = string
  description = "Subscription ID of the hashicorp02-image-factory-prod subscription hosting the shared image gallery."
  default     = "338f0fa5-b5ae-4847-9821-1808613db6c5"
}

variable "custom_tfe_startup_script_template" {
  type        = string
  description = "Name of custom TFE startup script template file. File must exist within a directory named `./templates` within your current working directory."
  default     = null

  validation {
    condition     = var.custom_tfe_startup_script_template != null ? fileexists("${path.cwd}/templates/${var.custom_tfe_startup_script_template}") : true
    error_message = "File not found. Ensure the file exists within a directory named `./templates` within your current working directory."
  }
}

variable "container_runtime" {
  type        = string
  description = "Value of container runtime to use for TFE deployment. For Redhat, the default is `podman`, but optionally `docker` can be used. For Ubuntu, the default is `docker`."

  validation {
    condition = (
      (contains(["redhat8", "redhat9"], var.vm_os_image) && contains(["docker", "podman"], var.container_runtime)) ||
      (contains(["ubuntu2204", "ubuntu2404"], var.vm_os_image) && var.container_runtime == "docker")
    )
    error_message = "For Redhat, the container runtime can be 'docker' or 'podman'. For Ubuntu, the container runtime must be 'docker'."
  }
}

variable "docker_version" {
  type        = string
  description = "Version of Docker to install on TFE VMSS."
  default     = "28.0.1"
}

variable "vm_disk_encryption_set_name" {
  type        = string
  description = "Name of Disk Encryption Set to use for VMSS."
  default     = null
}

variable "vm_disk_encryption_set_rg" {
  type        = string
  description = "Name of Resource Group where the Disk Encryption Set to use for VMSS exists."
  default     = null
}

variable "vm_enable_boot_diagnostics" {
  type        = bool
  description = "Boolean to enable boot diagnostics for VMSS."
  default     = false
}

variable "vm_enable_auto_instance_repair" {
  type        = bool
  description = "Boolean to enable automatic instance repair for VMSS."
  default     = true
}

#------------------------------------------------------------------------------
# PostgreSQL (database)
#------------------------------------------------------------------------------
variable "tfe_database_password_keyvault_secret_name" {
  type        = string
  description = "Name of the secret in the Key Vault that contains the TFE database password."
}

variable "postgres_version" {
  type        = number
  description = "PostgreSQL database version."
  default     = 14
}

variable "postgres_sku" {
  type        = string
  description = "PostgreSQL database SKU."
  default     = "GP_Standard_D4ds_v4"
}

variable "postgres_storage_mb" {
  type        = number
  description = "Storage capacity of PostgreSQL Flexible Server (unit is megabytes)."
  default     = 65536
}

variable "postgres_administrator_login" {
  type        = string
  description = "Username for administrator login of PostreSQL database."
  default     = "tfeadmin"
}

variable "postgres_backup_retention_days" {
  type        = number
  description = "Number of days to retain backups of PostgreSQL Flexible Server."
  default     = 35
}

variable "postgres_create_mode" {
  type        = string
  description = "Determines if the PostgreSQL Flexible Server is being created as a new server or as a replica."
  default     = "Default"

  validation {
    condition     = anytrue([var.postgres_create_mode == "Default", var.postgres_create_mode == "Replica"])
    error_message = "Value must be `Default` or `Replica`."
  }
}

variable "tfe_database_name" {
  type        = string
  description = "PostgreSQL database name for TFE."
  default     = "tfe"
}

variable "tfe_database_parameters" {
  type        = string
  description = "PostgreSQL server parameters for the connection URI. Used to configure the PostgreSQL connection."
  default     = "sslmode=require"
}

variable "create_postgres_private_endpoint" {
  type        = bool
  description = "Boolean to create a private endpoint and private DNS zone for PostgreSQL Flexible Server."
  default     = true
}

variable "postgres_enable_high_availability" {
  type        = bool
  description = "Boolean to enable `ZoneRedundant` high availability with PostgreSQL database."
  default     = false
}

variable "postgres_geo_redundant_backup_enabled" {
  type        = bool
  description = "Boolean to enable PostreSQL geo-redundant backup configuration in paired Azure region."
  default     = true
}

variable "postgres_primary_availability_zone" {
  type        = number
  description = "Number for the availability zone for the primary PostgreSQL Flexible Server instance to reside in."
  default     = 1
}

variable "postgres_secondary_availability_zone" {
  type        = number
  description = "Number for the availability zone for the standby PostgreSQL Flexible Server instance to reside in."
  default     = 2
}

variable "postgres_maintenance_window" {
  type        = map(number)
  description = "Map of maintenance window settings for PostgreSQL Flexible Server."
  default = {
    day_of_week  = 0
    start_hour   = 0
    start_minute = 0
  }
}

variable "postgres_cmk_keyvault_key_id" {
  type        = string
  description = "ID of the Key Vault key to use for customer-managed key (CMK) encryption of PostgreSQL Flexible Server database."
  default     = null
}

variable "postgres_cmk_keyvault_id" {
  type        = string
  description = "ID of the Key Vault containing the customer-managed key (CMK) for encrypting the PostgreSQL Flexible Server database."
  default     = null
}

variable "postgres_geo_backup_keyvault_key_id" {
  type        = string
  description = "ID of the Key Vault key to use for customer-managed key (CMK) encryption of PostgreSQL Flexible Server geo-redundant backups. This key must be in the same region as the geo-redundant backup."
  default     = null
}

variable "postgres_geo_backup_user_assigned_identity_id" {
  type        = string
  description = "ID of the User-Assigned Identity to use for customer-managed key (CMK) encryption of PostgreSQL Flexible Server geo-redundant backups. This identity must have 'Get', 'WrapKey', and 'UnwrapKey' permissions to the Key Vault."
  default     = null
}

variable "postgres_source_server_id" {
  type        = string
  description = "ID of the source PostgreSQL Flexible Server to replicate from. Only valid when `is_secondary_region` is `true` and `postgres_create_mode` is `Replica`."
  default     = null

  validation {
    condition     = !var.is_secondary_region ? var.postgres_source_server_id == null : true
    error_message = "Value must be `null` when `is_secondary_region` is `false`."
  }
}

#------------------------------------------------------------------------------
# Storage account (blob storage)
#------------------------------------------------------------------------------
variable "tfe_object_storage_azure_use_msi" {
  type        = bool
  description = "Boolean to use a User-Assigned Identity (MSI) for TFE blob storage account authentication rather than a storage account key."
  default     = true
}

variable "storage_account_public_network_access_enabled" {
  type        = bool
  description = "Boolean to enable public network access to Azure Blob Storage Account. Needs to be `true` for initial deployment. Optionally set to `false` after initial deployment."
  default     = true
}

variable "storage_account_ip_allow" {
  type        = list(string)
  description = "List of IP addresses allowed to access TFE Storage Account. Set this to the IP address that you are running Terraform from to deploy this module to avoid a 403 error from Azure when creating the storage container."
  default     = []
}

variable "storage_account_replication_type" {
  type        = string
  description = "Type of replication to use for TFE Storage Account."
  default     = "GRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.storage_account_replication_type)
    error_message = "Value must be one of 'LRS', 'GRS', 'RAGRS', 'ZRS', 'GZRS', or 'RAGZRS'."
  }
}

variable "create_blob_storage_private_endpoint" {
  type        = bool
  description = "Boolean to create a private endpoint and private DNS zone for TFE Storage Account."
  default     = true
}

variable "storage_account_cmk_keyvault_key_id" {
  type        = string
  description = "ID of the customer-managed key (CMK) within Key Vault for encrypting the TFE Storage Account."
  default     = null
}

variable "storage_account_cmk_keyvault_id" {
  type        = string
  description = "ID of the Key Vault containing the customer-managed key (CMK) for encrypting the TFE Storage Account."
  default     = null
}

variable "storage_account_blob_versioning_enabled" {
  type        = bool
  description = "Boolean to enable blob versioning for the TFE Storage Account."
  default     = false
}

variable "storage_account_blob_change_feed_enabled" {
  type        = bool
  description = "Boolean to enable blob change feed for the TFE Storage Account."
  default     = false
}

variable "tfe_primary_storage_account_name" {
  type        = string
  description = "Name of existing TFE storage account in primary region. Only set when `is_secondary_region` is `true`. "
  default     = null

  validation {
    condition     = var.is_secondary_region ? var.tfe_primary_storage_account_name != null : true
    error_message = "Value is required when `is_secondary_region` is `true`."
  }

  validation {
    condition     = !var.is_secondary_region ? var.tfe_primary_storage_account_name == null : true
    error_message = "Value must be `null` when `is_secondary_region` is `false`."
  }
}

variable "tfe_primary_storage_container_name" {
  type        = string
  description = "Name of existing TFE storage container (within TFE storage account) in primary region. Only set when `is_secondary_region` is `true`."
  default     = null

  validation {
    condition     = var.is_secondary_region ? var.tfe_primary_storage_container_name != null : true
    error_message = "Value is required when `is_secondary_region` is `true`."
  }

  validation {
    condition     = !var.is_secondary_region ? var.tfe_primary_storage_container_name == null : true
    error_message = "Value must be `null` when `is_secondary_region` is `false`."
  }
}

#------------------------------------------------------------------------------
# Redis cache / managed redis
#------------------------------------------------------------------------------
variable "redis_family" {
  type        = string
  description = "The SKU family/pricing group to use for the legacy Azure Cache for Redis path. Valid values are C (for Basic/Standard SKU family) and P (for Premium)."
  default     = "P"

  validation {
    condition     = contains(["C", "P"], var.redis_family)
    error_message = "Supported values are `C` or `P`."
  }
}

variable "redis_capacity" {
  type        = number
  description = "The size of the legacy Azure Cache for Redis deployment. Valid values for a SKU family of C (Basic/Standard) are 0, 1, 2, 3, 4, 5, 6, and for P (Premium) family are 1, 2, 3, 4."
  default     = 1

  validation {
    condition     = contains([0, 1, 2, 3, 4, 5, 6], var.redis_capacity)
    error_message = "Valid values for a SKU family of C (Basic/Standard) are 0, 1, 2, 3, 4, 5, 6, and for P (Premium) family are 1, 2, 3, 4."
  }
}

variable "redis_sku_name" {
  type        = string
  description = "Which SKU of Redis to use for the legacy Azure Cache for Redis path. Options are 'Basic', 'Standard', or 'Premium'."
  default     = "Premium"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.redis_sku_name)
    error_message = "Supported values are `Basic`, `Standard`, or `Premium`."
  }
}

variable "redis_version" {
  type        = number
  description = "Legacy Azure Cache for Redis version. Only the major version is needed."
  default     = 6
}

variable "redis_managed_sku_name" {
  type        = string
  description = "Managed Redis SKU to use when `tfe_image_tag` is semver `>= 1.0.1` and the module switches to Azure Managed Redis."
  default     = "Balanced_B3"
}

variable "redis_managed_high_availability_enabled" {
  type        = bool
  description = "Boolean to enable high availability for Azure Managed Redis instances when `tfe_image_tag` is semver `>= 1.0.1`."
  default     = true
}

variable "tfe_redis_use_auth" {
  type        = bool
  description = "Boolean to enable authentication to the Redis cache."
  default     = true
}

variable "tfe_redis_use_tls" {
  type        = bool
  description = "Boolean to enable TLS for the Redis cache."
  default     = true
}

variable "redis_non_ssl_port_enabled" {
  type        = bool
  description = "Boolean to enable non-SSL port 6379 for the legacy Azure Cache for Redis path."
  default     = false
}

variable "redis_min_tls_version" {
  type        = string
  description = "Minimum TLS version to use with the legacy Azure Cache for Redis path."
  default     = "1.2"
}

variable "create_redis_private_endpoint" {
  type        = bool
  description = "Boolean to create a private DNS zone and private endpoint for the Redis service used by TFE."
  default     = true
}

#------------------------------------------------------------------------------
# Log forwarding
#------------------------------------------------------------------------------
variable "tfe_log_forwarding_enabled" {
  type        = bool
  description = "Boolean to enable TFE log forwarding feature."
  default     = false
}

variable "log_fwd_destination_type" {
  type        = string
  description = "Type of log forwarding destination. Valid values are 'log_analytics', 'event_hub', 'both' (log_analytics + event_hub), or 'custom'."
  default     = "log_analytics"

  validation {
    condition     = contains(["log_analytics", "event_hub", "both", "custom"], var.log_fwd_destination_type)
    error_message = "Supported values are `log_analytics`, `event_hub`, `both`, or `custom`."
  }
}

variable "log_analytics_workspace_name" {
  type        = string
  description = "Name of existing Azure Log Analytics Workspace for log forwarding destination. Required when `log_fwd_destination_type` is `log_analytics` or `both` (unless `create_log_analytics_workspace = true`)."
  default     = null

  validation {
    condition     = var.tfe_log_forwarding_enabled && contains(["log_analytics", "both"], var.log_fwd_destination_type) && !var.create_log_analytics_workspace ? var.log_analytics_workspace_name != null : true
    error_message = "Value is required when `tfe_log_forwarding_enabled` is `true`, `log_fwd_destination_type` is `log_analytics` or `both`, and `create_log_analytics_workspace` is `false`."

  }
}

variable "log_analytics_workspace_rg_name" {
  type        = string
  description = "Name of Resource Group where Log Analytics Workspace exists."
  default     = null

  validation {
    condition     = contains(["log_analytics", "both"], var.log_fwd_destination_type) && var.log_analytics_workspace_name != null ? var.log_analytics_workspace_rg_name != null : true
    error_message = "Value is required when `log_fwd_destination_type` is `log_analytics` or `both` and `log_analytics_workspace_name` is not `null`."
  }
}

variable "create_event_hub" {
  type        = bool
  description = "Boolean to automatically create an Azure Event Hubs namespace and Event Hub topic for log forwarding."
  default     = false
}

variable "event_hub_rg_name" {
  type        = string
  description = "Resource Group name for the Event Hub resources. Defaults to the TFE resource group if not specified."
  default     = null
}

variable "event_hub_sku" {
  type        = string
  description = "Defines which tier to use for Event Hub Namespace. Valid options are Basic, Standard, and Premium."
  default     = "Standard"
}

variable "event_hub_capacity" {
  type        = number
  description = "Specifies the Capacity / Throughput Units for a Standard SKU namespace."
  default     = 1
}

variable "event_hub_partition_count" {
  type        = number
  description = "Specifies the current number of shards on the Event Hub. Must be between 1 and 32."
  default     = 2
}

variable "event_hub_message_retention" {
  type        = number
  description = "Specifies the number of days to retain the events for this Event Hub. Must be between 1 and 7 days."
  default     = 1
}

variable "event_hub_namespace_name" {
  type        = string
  description = "Name of the Azure Event Hubs namespace for log forwarding. Required when `create_event_hub` is `false` and `log_fwd_destination_type` is `event_hub` or `both`."
  default     = null

  validation {
    condition     = var.tfe_log_forwarding_enabled && contains(["event_hub", "both"], var.log_fwd_destination_type) && !var.create_event_hub ? var.event_hub_namespace_name != null : true
    error_message = "Value is required when `tfe_log_forwarding_enabled` is `true`, `log_fwd_destination_type` is `event_hub` or `both`, and `create_event_hub` is `false`."
  }
}

variable "event_hub_name" {
  type        = string
  description = "Name of the Azure Event Hub instance (topic) for log forwarding. Required when `create_event_hub` is `false` and `log_fwd_destination_type` is `event_hub` or `both`."
  default     = null

  validation {
    condition     = var.tfe_log_forwarding_enabled && contains(["event_hub", "both"], var.log_fwd_destination_type) && !var.create_event_hub ? var.event_hub_name != null : true
    error_message = "Value is required when `tfe_log_forwarding_enabled` is `true`, `log_fwd_destination_type` is `event_hub` or `both`, and `create_event_hub` is `false`."
  }
}

variable "event_hub_connection_string" {
  type        = string
  description = "Primary connection string for the Event Hub authorization rule. Required when `create_event_hub` is `false` and `log_fwd_destination_type` is `event_hub` or `both`."
  sensitive   = true
  default     = null

  validation {
    condition     = var.tfe_log_forwarding_enabled && contains(["event_hub", "both"], var.log_fwd_destination_type) && !var.create_event_hub ? var.event_hub_connection_string != null : true
    error_message = "Value is required when `tfe_log_forwarding_enabled` is `true`, `log_fwd_destination_type` is `event_hub` or `both`, and `create_event_hub` is `false`."
  }
}

variable "custom_fluent_bit_config" {
  type        = string
  description = "Custom Fluent Bit configuration for log forwarding. Only valid if `log_fwd_destination_type` is `custom`."
  default     = null
}

#------------------------------------------------------------------------------
# Networking
#------------------------------------------------------------------------------
variable "create_networking_resources" {
  type        = bool
  description = "Boolean to create the networking resource group, VNet, and subnets. Set to false if these already exist."
  default     = false
}

variable "networking_resource_group_name" {
  type        = string
  description = "Name of the networking resource group. Used when `create_networking_resources` is `true`."
  default     = "tfe-networking-rg"
}

variable "vnet_name" {
  type        = string
  description = "Name of the Virtual Network to create. Used when `create_networking_resources` is `true`."
  default     = "tfe-vnet"
}

variable "vnet_address_space" {
  type        = string
  description = "Address space for the Virtual Network. Used when `create_networking_resources` is `true`."
  default     = "10.0.0.0/16"
}

variable "lb_subnet_cidr" {
  type        = string
  description = "CIDR for the load balancer subnet. Used when `create_networking_resources` is `true`."
  default     = "10.0.1.0/24"
}

variable "vm_subnet_cidr" {
  type        = string
  description = "CIDR for the VM subnet. Used when `create_networking_resources` is `true`."
  default     = "10.0.2.0/24"
}

variable "db_subnet_cidr" {
  type        = string
  description = "CIDR for the database subnet. Used when `create_networking_resources` is `true`."
  default     = "10.0.3.0/24"
}

variable "redis_subnet_cidr" {
  type        = string
  description = "CIDR for the Redis subnet. Used when `create_networking_resources` is `true`."
  default     = "10.0.4.0/24"
}

variable "create_bastion_host" {
  type        = bool
  description = "Boolean to create an Azure Bastion host for VM access. Only valid when `create_networking_resources` is `true`."
  default     = true
}

variable "bastion_subnet_cidr" {
  type        = string
  description = "CIDR for the AzureBastionSubnet. Must be at least /26. Used when `create_bastion_host` is `true`."
  default     = "10.0.5.0/26"
}

#------------------------------------------------------------------------------
# Log Analytics
#------------------------------------------------------------------------------
variable "create_log_analytics_workspace" {
  type        = bool
  description = "Boolean to create the Log Analytics resource group and workspace."
  default     = false
}


#------------------------------------------------------------------------------
# Dashboard
#------------------------------------------------------------------------------
variable "create_dashboard" {
  type        = bool
  description = "Boolean to create an Azure Portal shared dashboard showing TFE workspace run summaries. Requires `tfe_log_forwarding_enabled = true` and `log_fwd_destination_type = \"log_analytics\"`."
  default     = false
}

variable "create_workbook" {
  type        = bool
  description = "Boolean to create an Azure Monitor Workbook with interactive KQL charts showing TFE workspace run summaries. Requires `tfe_log_forwarding_enabled = true` and `log_fwd_destination_type = \"log_analytics\"`."
  default     = false
}

#------------------------------------------------------------------------------
# Windows bastion host
#------------------------------------------------------------------------------
variable "create_windows_bastion" {
  type        = bool
  description = "Boolean to create a Windows Server 2025 bastion VM with a public IP and Google Chrome pre-installed. Useful for accessing the TFE UI from a browser when the load balancer has no public DNS or when running in a restricted network."
  default     = false
}

variable "windows_bastion_vm_size" {
  type        = string
  description = "Azure VM size (SKU) for the Windows bastion host."
  default     = "Standard_D2s_v3"
}

variable "windows_bastion_admin_username" {
  type        = string
  description = "Local administrator username for the Windows bastion VM."
  default     = "bastionadmin"
}

variable "windows_bastion_admin_password" {
  type        = string
  description = "Local administrator password for the Windows bastion VM. Must meet Azure complexity requirements (12+ chars, upper, lower, digit, special). Recommended: supply via the TF_VAR_windows_bastion_admin_password environment variable rather than in tfvars."
  sensitive   = true
  default     = null
  nullable    = true
}

variable "windows_bastion_allowed_cidrs" {
  type        = list(string)
  description = "List of CIDR ranges allowed to connect to the Windows bastion host over RDP (port 3389). Set this to your Mac's public IP, e.g. [\"1.2.3.4/32\"]."
  default     = []

  validation {
    condition     = var.create_windows_bastion ? length(var.windows_bastion_allowed_cidrs) > 0 : true
    error_message = "At least one CIDR must be provided in `windows_bastion_allowed_cidrs` when `create_windows_bastion` is `true`."
  }

  validation {
    condition = alltrue([
      for cidr in var.windows_bastion_allowed_cidrs : can(cidrhost(cidr, 0))
    ])
    error_message = "All values must be valid CIDR notation."
  }
}
