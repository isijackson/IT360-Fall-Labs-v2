terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

variable "location" {
  type    = string
  default = "eastus"
}
variable "name" {
  type    = string
  default = "it360-web"
}
variable "ssh_public_key" { type = string }
variable "ssh_source_cidr" {
  type    = string
  default = "0.0.0.0/0" # narrow this to <your public ip>/32 outside a sandbox
}
variable "resource_group" {
  type    = string
  default = "" # set to the pre-created group on the Vocareum sandbox
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  count    = var.resource_group == "" ? 1 : 0
  name     = "${var.name}-rg"
  location = var.location
}

locals {
  rg = var.resource_group != "" ? var.resource_group : azurerm_resource_group.rg[0].name
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.name}-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = var.location
  resource_group_name = local.rg
}

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = local.rg
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_public_ip" "pip" {
  name                = "${var.name}-pip"
  location            = var.location
  resource_group_name = local.rg
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.name}-nsg"
  location            = var.location
  resource_group_name = local.rg
  security_rule {
    name                       = "ssh"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.ssh_source_cidr == "0.0.0.0/0" ? "*" : var.ssh_source_cidr
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "http"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nic" {
  name                = "${var.name}-nic"
  location            = var.location
  resource_group_name = local.rg
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_linux_virtual_machine" "web" {
  name                  = var.name
  location              = var.location
  resource_group_name   = local.rg
  size                  = "Standard_D2s_v4" # the size that had capacity in the Vocareum sandbox (Week 1 Lab 2)
  admin_username        = "ubuntu"
  network_interface_ids = [azurerm_network_interface.nic.id]
  admin_ssh_key {
    username   = "ubuntu"
    public_key = var.ssh_public_key
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  custom_data = base64encode(<<-EOT
    #!/bin/bash
    apt-get update && apt-get install -y nginx
    echo "<h1>served from Azure by $(hostname)</h1>" > /var/www/html/index.html
  EOT
  )
}

output "public_ip" { value = azurerm_public_ip.pip.ip_address }
