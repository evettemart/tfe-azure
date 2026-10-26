# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Ubuntu bastion host (optional)
# An Ubuntu VM with an XFCE desktop, xrdp and Google Chrome, so the TFE UI can
# be opened in a graphical browser. Accessible over RDP (3389) and SSH (22)
# from the CIDR(s) listed in `ubuntu_bastion_allowed_cidrs`.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Shared image lookup
#------------------------------------------------------------------------------
data "azurerm_shared_image" "ubuntu_bastion" {
  count = var.create_ubuntu_bastion ? 1 : 0

  provider            = azurerm.image_factory
  name                = var.ubuntu_bastion_image_name
  gallery_name        = "hcbaseGallery"
  resource_group_name = "hc-base-rg-gallery"
}

#------------------------------------------------------------------------------
# Public IP
#------------------------------------------------------------------------------
resource "azurerm_public_ip" "ubuntu_bastion" {
  count = var.create_ubuntu_bastion ? 1 : 0

  name                = "${var.friendly_name_prefix}-ubuntu-bastion-ip"
  resource_group_name = local.resource_group_name
  location            = var.location
  sku                 = "Standard"
  allocation_method   = "Static"

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-ubuntu-bastion-ip" },
    var.common_tags
  )
}

#------------------------------------------------------------------------------
# NSG — allow RDP (xrdp) and SSH inbound from the specified CIDRs only
#------------------------------------------------------------------------------
resource "azurerm_network_security_group" "ubuntu_bastion" {
  count = var.create_ubuntu_bastion ? 1 : 0

  name                = "${var.friendly_name_prefix}-ubuntu-bastion-nsg"
  resource_group_name = local.resource_group_name
  location            = var.location

  security_rule {
    name                       = "allow-rdp-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefixes    = var.ubuntu_bastion_allowed_cidrs
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-ssh-inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.ubuntu_bastion_allowed_cidrs
    destination_address_prefix = "*"
  }

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-ubuntu-bastion-nsg" },
    var.common_tags
  )
}

#------------------------------------------------------------------------------
# NIC
#------------------------------------------------------------------------------
resource "azurerm_network_interface" "ubuntu_bastion" {
  count = var.create_ubuntu_bastion ? 1 : 0

  name                = "${var.friendly_name_prefix}-ubuntu-bastion-nic"
  resource_group_name = local.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "bastion-ipconfig"
    subnet_id                     = local.resolved_vm_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ubuntu_bastion[0].id
  }

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-ubuntu-bastion-nic" },
    var.common_tags
  )
}

resource "azurerm_network_interface_security_group_association" "ubuntu_bastion" {
  count = var.create_ubuntu_bastion ? 1 : 0

  network_interface_id      = azurerm_network_interface.ubuntu_bastion[0].id
  network_security_group_id = azurerm_network_security_group.ubuntu_bastion[0].id
}

#------------------------------------------------------------------------------
# Ubuntu VM
#------------------------------------------------------------------------------
locals {
  # IP the bastion maps `tfe_fqdn` to. Defaults to the load balancer IP; override
  # with `ubuntu_bastion_tfe_hosts_ip` (for example a TFE instance private IP)
  # when the load balancer path is not reachable.
  ubuntu_bastion_tfe_hosts_ip = var.create_ubuntu_bastion ? (
    var.ubuntu_bastion_tfe_hosts_ip != null ? var.ubuntu_bastion_tfe_hosts_ip : (
      !var.lb_is_internal ? azurerm_public_ip.tfe_lb[0].ip_address : var.lb_private_ip
    )
  ) : ""
}

resource "azurerm_linux_virtual_machine" "ubuntu_bastion" {
  count = var.create_ubuntu_bastion ? 1 : 0

  name                = "${var.friendly_name_prefix}-ubuntu-bastion"
  resource_group_name = local.resource_group_name
  location            = var.location
  size                = var.ubuntu_bastion_vm_size
  admin_username      = var.ubuntu_bastion_admin_username
  admin_password      = var.ubuntu_bastion_admin_password

  # xrdp logs in with the Linux user password, so password auth must be on.
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.ubuntu_bastion[0].id]

  source_image_id = data.azurerm_shared_image.ubuntu_bastion[0].id

  dynamic "admin_ssh_key" {
    for_each = var.ubuntu_bastion_ssh_public_key != null ? [1] : []
    content {
      username   = var.ubuntu_bastion_admin_username
      public_key = var.ubuntu_bastion_ssh_public_key
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  # Managed boot diagnostics (no storage account): gives a serial log and
  # screenshot in the portal if the VM fails to boot.
  boot_diagnostics {}

  # Runs the setup script on first boot (cloud-init) unless
  # `ubuntu_bastion_run_setup_script` is false. Progress and errors are logged
  # to /var/log/ubuntu-bastion-setup.log on the VM.
  custom_data = var.ubuntu_bastion_run_setup_script ? base64encode(templatefile("${path.module}/templates/ubuntu_bastion_setup.sh.tpl", {
    tfe_fqdn       = var.tfe_fqdn
    tfe_hosts_ip   = local.ubuntu_bastion_tfe_hosts_ip
    admin_username = var.ubuntu_bastion_admin_username
  })) : null

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-ubuntu-bastion" },
    var.common_tags
  )
}
