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
  features {
  }
}

variable "tag_id" {
  type = string
}



resource "azurerm_resource_group" "rg" {
  name     = "utb_parcial"
  location = "eastus"
}

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg_parcial"
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

  security_rule {
    name                       = "allowPublicWeb"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "allowHttps"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "parcial_network" {
  name                = "parcial_network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "parcial_subnet" {
  name                 = "parcial_subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.parcial_network.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "vm_ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "vm_nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig_nic"
    subnet_id                     = azurerm_subnet.parcial_subnet.id
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
  filename          = "${path.module}/priv_key.ssh"
  file_permission   = "0600"
}

resource "azurerm_linux_virtual_machine" "parcial_vm" {
  name                  = "parcial_vm"
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
}


resource "local_file" "ansible_inventory" {
  depends_on = [azurerm_linux_virtual_machine.parcial_vm]
  content  =templatefile("inventory.tftpl", {
    ip_addrs = [azurerm_public_ip.public_ip.ip_address]
    ssh_keyfile = format("%s/%s", abspath(path.root), "priv_key.ssh")

  })
  filename = "${path.module}/inventory"
}

resource "null_resource" "run_ansible" {
  depends_on = [azurerm_linux_virtual_machine.parcial_vm]

  provisioner "local-exec" {
    
    command = "sleep 30 && ansible-playbook -i '${local_file.ansible_inventory.filename}' --private-key '${local_sensitive_file.private_key.filename}' vm.yaml -vvv"

  }

}

output "virtual_machine_ip" {
  value = azurerm_public_ip.public_ip.ip_address
}

