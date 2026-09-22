# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Networking resource group
#------------------------------------------------------------------------------
resource "azurerm_resource_group" "networking" {
  count = var.create_networking_resources ? 1 : 0

  name     = var.networking_resource_group_name
  location = var.location

  tags = merge(
    { "Name" = var.networking_resource_group_name },
    var.common_tags
  )
}

#------------------------------------------------------------------------------
# Virtual network
#------------------------------------------------------------------------------
resource "azurerm_virtual_network" "tfe" {
  count = var.create_networking_resources ? 1 : 0

  name                = var.vnet_name
  resource_group_name = azurerm_resource_group.networking[0].name
  location            = var.location
  address_space       = [var.vnet_address_space]

  tags = merge(
    { "Name" = var.vnet_name },
    var.common_tags
  )
}

#------------------------------------------------------------------------------
# Subnets
#------------------------------------------------------------------------------
resource "azurerm_subnet" "lb" {
  count = var.create_networking_resources ? 1 : 0

  name                 = "tfe-lb-subnet"
  resource_group_name  = azurerm_resource_group.networking[0].name
  virtual_network_name = azurerm_virtual_network.tfe[0].name
  address_prefixes     = [var.lb_subnet_cidr]
}

resource "azurerm_subnet" "vm" {
  count = var.create_networking_resources ? 1 : 0

  name                 = "tfe-vm-subnet"
  resource_group_name  = azurerm_resource_group.networking[0].name
  virtual_network_name = azurerm_virtual_network.tfe[0].name
  address_prefixes     = [var.vm_subnet_cidr]

  service_endpoints = ["Microsoft.KeyVault", "Microsoft.Sql", "Microsoft.Storage"]
}

resource "azurerm_subnet" "db" {
  count = var.create_networking_resources ? 1 : 0

  name                 = "tfe-db-subnet"
  resource_group_name  = azurerm_resource_group.networking[0].name
  virtual_network_name = azurerm_virtual_network.tfe[0].name
  address_prefixes     = [var.db_subnet_cidr]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "redis" {
  count = var.create_networking_resources ? 1 : 0

  name                 = "tfe-redis-subnet"
  resource_group_name  = azurerm_resource_group.networking[0].name
  virtual_network_name = azurerm_virtual_network.tfe[0].name
  address_prefixes     = [var.redis_subnet_cidr]
}

resource "azurerm_subnet" "bastion" {
  count = var.create_networking_resources && var.create_bastion_host ? 1 : 0

  # Azure requires this exact name for bastion subnets
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.networking[0].name
  virtual_network_name = azurerm_virtual_network.tfe[0].name
  address_prefixes     = [var.bastion_subnet_cidr]
}

#------------------------------------------------------------------------------
# Bastion host
#------------------------------------------------------------------------------
resource "azurerm_public_ip" "bastion" {
  count = var.create_networking_resources && var.create_bastion_host ? 1 : 0

  name                = "tfe-bastion-ip"
  resource_group_name = azurerm_resource_group.networking[0].name
  location            = var.location
  sku                 = "Standard"
  allocation_method   = "Static"
  zones               = ["1", "2", "3"]

  tags = merge(
    { "Name" = "tfe-bastion-ip" },
    var.common_tags
  )
}

resource "azurerm_bastion_host" "tfe" {
  count = var.create_networking_resources && var.create_bastion_host ? 1 : 0

  name                = "tfe-bastion"
  resource_group_name = azurerm_resource_group.networking[0].name
  location            = var.location
  sku                 = "Basic"

  ip_configuration {
    name                 = "bastion_ip_config"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = merge(
    { "Name" = "tfe-bastion" },
    var.common_tags
  )
}

#------------------------------------------------------------------------------
# Locals — expose subnet IDs for use by the TFE module when networking
# resources are created by this config rather than brought in externally
#------------------------------------------------------------------------------
locals {
  resolved_vnet_id         = var.create_networking_resources ? azurerm_virtual_network.tfe[0].id : var.vnet_id
  resolved_lb_subnet_id    = var.create_networking_resources ? azurerm_subnet.lb[0].id : var.lb_subnet_id
  resolved_vm_subnet_id    = var.create_networking_resources ? azurerm_subnet.vm[0].id : var.vm_subnet_id
  resolved_db_subnet_id    = var.create_networking_resources ? azurerm_subnet.db[0].id : var.db_subnet_id
  resolved_redis_subnet_id = var.create_networking_resources ? azurerm_subnet.redis[0].id : var.redis_subnet_id
}
