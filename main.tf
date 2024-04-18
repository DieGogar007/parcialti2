terraform {
    required_providers {
    azurerm = {  
        source = "hashicorp/azurerm"
        version = "~>3.0"
    }
    tls = {
        source = "hashicorp/tls"
        version = "~>4.0"
    }
    }
}

provider "azurerm" {
  skip_provider_registration = "true"
  features {}
  
  tenant_id       = "165d65fd-4352-4815-8f48-0c3f70e9a0e0"
  subscription_id = "15c3f2c9-88a8-4301-a0f7-3b5622ab0317"
  client_secret	  = "Pe68Q~r2iJ7kXvEJX6.2l1o4MK5bLsF8w2GRIbNt"
  client_id		  = "a9fa2a4c-a3b7-4709-bde2-379d12b843c9"
}


resource "azurerm_resource_group" "rg" {
  name     = "parcial_laescuadra"
  location = "northeurope"
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg_parcialutb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allowSSH"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  dynamic "security_rule"{
    for_each = split("," , azurerm_app_service.linux.outbound_ip_addresses)
    content {
      name = "access"
      priority = 1100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      destination_port_range     = "3306"
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
  }

  security_rule{
    name                       = "app-web"
    priority                   =  4000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "azurerm_virtual_network" "parcial_laescuadra" {
  name                = "parcial-laescuadra"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "vm-laescuadra" {
  name                 = "vm-laescuadra"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.parcial_laescuadra.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "app-laescuadra" {
  name = "web-laescuadra"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.parcial_laescuadra.name
  address_prefixes = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "public_ip_vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "vm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig_nic"
    subnet_id                     = azurerm_subnet.vm-laescuadra.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_nic_assoc" {
  network_interface_id      = azurerm_network_interface.vm_nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_sensitive_file" "private_key" {
  content = tls_private_key.ssh_key.private_key_openssh
  filename          = "priv_key.ssh"
  file_permission   = "0600"
}



resource "azurerm_linux_virtual_machine" "laescuadra_vm" {
  name                  = "utb_vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  network_interface_ids = [azurerm_network_interface.vm_nic.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  computer_name                   = "utbvm"
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh_key.public_key_openssh
  }

  provisioner "local-exec" {
  command = <<EOT
    echo "IP Address: ${azurerm_public_ip.public_ip.ip_address}"
    while ! ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa -l azureuser ${azurerm_public_ip.public_ip.ip_address} exit; do
      sleep 5
    done
  EOT
}

  provisioner "local-exec" {
    command = "ansible-playbook -i '${azurerm_public_ip.public_ip.ip_address},' vm.yml -e 'ssh_user=azureuser' -e 'sh_private_key=~/.ssh/id_rsa'"
  }
}

output "virtual_machine_ip" {
  value = azurerm_public_ip.public_ip.ip_address
}