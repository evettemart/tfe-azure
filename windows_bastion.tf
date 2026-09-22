# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Windows bastion host (optional)
# A Windows Server 2025 VM with a browser pre-configured to reach TFE.
# Accessible over RDP from the CIDR(s) listed in `windows_bastion_allowed_cidrs`.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Shared image lookup
#------------------------------------------------------------------------------
data "azurerm_shared_image" "windows_bastion" {
  count = var.create_windows_bastion ? 1 : 0

  provider            = azurerm.image_factory
  name                = "hc-base-windows-server-2025-x64"
  gallery_name        = "hcbaseGallery"
  resource_group_name = "hc-base-rg-gallery"
}

#------------------------------------------------------------------------------
# Public IP
#------------------------------------------------------------------------------
resource "azurerm_public_ip" "windows_bastion" {
  count = var.create_windows_bastion ? 1 : 0

  name                = "${var.friendly_name_prefix}-win-bastion-ip"
  resource_group_name = local.resource_group_name
  location            = var.location
  sku                 = "Standard"
  allocation_method   = "Static"

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-win-bastion-ip" },
    var.common_tags
  )
}

#------------------------------------------------------------------------------
# NSG — allow RDP inbound from the specified CIDRs only
#------------------------------------------------------------------------------
resource "azurerm_network_security_group" "windows_bastion" {
  count = var.create_windows_bastion ? 1 : 0

  name                = "${var.friendly_name_prefix}-win-bastion-nsg"
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
    source_address_prefixes    = var.windows_bastion_allowed_cidrs
    destination_address_prefix = "*"
  }

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-win-bastion-nsg" },
    var.common_tags
  )
}

#------------------------------------------------------------------------------
# NIC
#------------------------------------------------------------------------------
resource "azurerm_network_interface" "windows_bastion" {
  count = var.create_windows_bastion ? 1 : 0

  name                = "${var.friendly_name_prefix}-win-bastion-nic"
  resource_group_name = local.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "bastion-ipconfig"
    subnet_id                     = local.resolved_vm_subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.windows_bastion[0].id
  }

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-win-bastion-nic" },
    var.common_tags
  )
}

resource "azurerm_network_interface_security_group_association" "windows_bastion" {
  count = var.create_windows_bastion ? 1 : 0

  network_interface_id      = azurerm_network_interface.windows_bastion[0].id
  network_security_group_id = azurerm_network_security_group.windows_bastion[0].id
}

#------------------------------------------------------------------------------
# Windows VM
#------------------------------------------------------------------------------
locals {
  windows_bastion_lb_ip = var.create_windows_bastion ? (
    !var.lb_is_internal ? azurerm_public_ip.tfe_lb[0].ip_address : var.lb_private_ip
  ) : ""
}

resource "azurerm_windows_virtual_machine" "windows_bastion" {
  count = var.create_windows_bastion ? 1 : 0

  name                = "${var.friendly_name_prefix}-win-bastion"
  resource_group_name = local.resource_group_name
  location            = var.location
  size                = var.windows_bastion_vm_size
  admin_username      = var.windows_bastion_admin_username
  admin_password      = var.windows_bastion_admin_password

  network_interface_ids = [azurerm_network_interface.windows_bastion[0].id]

  source_image_id = data.azurerm_shared_image.windows_bastion[0].id

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  tags = merge(
    { "Name" = "${var.friendly_name_prefix}-win-bastion" },
    var.common_tags
  )
}

#------------------------------------------------------------------------------
# Custom Script Extension — executes PowerShell on first boot.
# Writes the script to a temp file then executes it to avoid command-line
# length limits and encoding issues with -EncodedCommand.
#------------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "windows_bastion_setup" {
  count = var.create_windows_bastion ? 1 : 0

  name                       = "windows-bastion-setup"
  virtual_machine_id         = azurerm_windows_virtual_machine.windows_bastion[0].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -Command \"$h='C:\\Windows\\System32\\drivers\\etc\\hosts'; $e='${local.windows_bastion_lb_ip} ${var.tfe_fqdn}'; if(!(Select-String -Path $h -Pattern $e -Quiet)){Add-Content -Path $h -Value \\\"`n$e\\\"}; $i=\\\"$env:TEMP\\ChromeSetup.exe\\\"; Invoke-WebRequest -Uri 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' -OutFile $i; Start-Process -FilePath $i -Args '/silent /install' -Wait; Remove-Item $i -Force\""
  })

  tags = var.common_tags
}
