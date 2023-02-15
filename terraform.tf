# Configure the Azure provider
terraform {

  required_version = ">=0.12"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0" 
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "test_cloudazure" {
  name     = "Arquitectura_nube"
  location = "eastus"
}

# Red Virtual
resource "azurerm_virtual_network" "red_cloudazure" {
  name                = "red_virtual_Tony"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.test_cloudazure.location
  resource_group_name = azurerm_resource_group.test_cloudazure.name
}


# SubNet Virtual Machine
resource "azurerm_subnet" "test_cloudazure" {
  name                 = "Subred_privada"
  resource_group_name  = azurerm_resource_group.test_cloudazure.name
  virtual_network_name = azurerm_virtual_network.red_cloudazure.name
  address_prefixes     = ["10.0.2.0/24"]
}
#==========================================================================#
# SubNet Base de datos
resource "azurerm_subnet" "subnet_bdd" {

  address_prefixes     = ["10.0.1.0/24"]
  name                 = "subnet_database"
  resource_group_name  = azurerm_resource_group.test_cloudazure.name
  virtual_network_name = azurerm_virtual_network.red_cloudazure.name
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "fs"

    service_delegation {
      name    = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# Zona DNS bdd
resource "azurerm_private_dns_zone" "dns_zone" {

  name                = "bdd.tony.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.test_cloudazure.name
}

# Gestionar zonas DNS privadas
resource "azurerm_private_dns_zone_virtual_network_link" "link_dns_zone" {

  name                  = "mysqlVnetZoneTony.com"
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone.name
  resource_group_name   = azurerm_resource_group.test_cloudazure.name
  virtual_network_id    = azurerm_virtual_network.red_cloudazure.id
}

#Gestiona el Servidor Flexible MySQL
resource "azurerm_mysql_flexible_server" "server_mysql" {

  location                     = azurerm_resource_group.test_cloudazure.location
  name                         = "mysqltony"
  resource_group_name          = azurerm_resource_group.test_cloudazure.name
  administrator_login          = "tony"
  administrator_password       = "Tony1234."
  backup_retention_days        = 7
  delegated_subnet_id          = azurerm_subnet.subet_bdd.id
  geo_redundant_backup_enabled = false
  private_dns_zone_id          = azurerm_private_dns_zone.dns_zone.id
  sku_name                     = "GP_Standard_D2ds_v4"
  version                      = "8.0.21"
  zone                         = "1"

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }
  maintenance_window {
    day_of_week  = 0
    start_hour   = 8
    start_minute = 0
  }
  storage {
    iops    = 360
    size_gb = 20
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.link_dns_zone]
}

# Gestiona la base de datos del Servidor Flexible MySQL
resource "azurerm_mysql_flexible_database" "bdd_wordpress" {
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
  name                = "bdd_wordpress"
  resource_group_name = azurerm_resource_group.test_cloudazure.name
  server_name         = azurerm_mysql_flexible_server.server_mysql.name
}

#==========================================================================#

# IP Publica
resource "azurerm_public_ip" "test_cloudazure" {
  count               = 2
  name                = "ip_publica${count.index}"
  location            = azurerm_resource_group.test_cloudazure.location
  resource_group_name = azurerm_resource_group.test_cloudazure.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "machinerb${count.index}"
}


# Interfaz de Red
resource "azurerm_network_interface" "test_cloudazure" {
  count               = 2
  name                = "red${count.index}"
  location            = azurerm_resource_group.test_cloudazure.location
  resource_group_name = azurerm_resource_group.test_cloudazure.name

  ip_configuration {
    name                          = "configuracion_ip"
    subnet_id                     = azurerm_subnet.test_cloudazure.id
    private_ip_address_allocation = "static"
    private_ip_address            = cidrhost("10.0.2.0/24", 4 + count.index)
    public_ip_address_id          = azurerm_public_ip.test_cloudazure[count.index].id
  }

}

# Crear y administrar discos de datos
resource "azurerm_managed_disk" "test_cloudazure" {
  count                = 2
  name                 = "datadisk${count.index}"
  location             = azurerm_resource_group.test_cloudazure.location
  resource_group_name  = azurerm_resource_group.test_cloudazure.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "32"
}

# Agrupación de máquinas virtuales
resource "azurerm_availability_set" "avset" {
  name                         = "grupo_VM"
  location                     = azurerm_resource_group.test_cloudazure.location
  resource_group_name          = azurerm_resource_group.test_cloudazure.name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true
}


# Variable para el directorio de clave privada
variable "private_key_path" {
  type    = string
  default = "C:\\Clave\\keys\\private"
}

# Definir y configurar una máquina virtual 
resource "azurerm_virtual_machine" "test_cloudazure" {
  count                 = 2
  name                  = "Servicio${count.index}"
  location              = azurerm_resource_group.test_cloudazure.location
  availability_set_id   = azurerm_availability_set.avset.id
  resource_group_name   = azurerm_resource_group.test_cloudazure.name
  network_interface_ids = [element(azurerm_network_interface.test_cloudazure.*.id, count.index)]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  # delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  # delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "myosdisk${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  # Optional data disks
  storage_data_disk {
    name              = "datadisk_new_${count.index}"
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    lun               = 0
    disk_size_gb      = "10"
  }

  storage_data_disk {
    name            = element(azurerm_managed_disk.test_cloudazure.*.name, count.index)
    managed_disk_id = element(azurerm_managed_disk.test_cloudazure.*.id, count.index)
    create_option   = "Attach"
    lun             = 1
    disk_size_gb    = element(azurerm_managed_disk.test_cloudazure.*.disk_size_gb, count.index)
  }

  os_profile {
    computer_name  = "Tony"
    admin_username = "tony"
    admin_password = "Tony1234."
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  # Conexion Clave Privada
  connection {
    type        = "ssh"
    user        = "tony"
    password    = "Tony1234."
    private_key = file(var.private_key_path)
    host        = azurerm_network_interface.test_cloudazure.id
  }

  tags = {
    environment = "staging"
  }
}


#crear grupo de seguridad y reglas de firewall

resource "azurerm_network_security_group" "reglas" {
  name                = "reglas_ssh"
  location            = azurerm_resource_group.test_cloudazure.location
  resource_group_name = azurerm_resource_group.test_cloudazure.name

  security_rule {
    name                       = "permisos"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "servicio"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "bdd_rules"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

#asociacion de grupo de seguridad con las maquinas virtuales existentes
resource "azurerm_network_interface_security_group_association" "association" {

  count = length(azurerm_network_interface.test_cloudazure)

  network_interface_id      = azurerm_network_interface.test_cloudazure[count.index].id
  network_security_group_id = azurerm_network_security_group.reglas.id
}


#Sistema de monitoreo
#Logs por medio de consultas
resource "azurerm_log_analytics_workspace" "logs_cloudazure" {

  count = length(azurerm_network_interface.test_cloudazure)

  name                = "mointoreo${count.index}"
  location            = azurerm_resource_group.test_cloudazure.location
  resource_group_name = azurerm_resource_group.test_cloudazure.name

  sku = "PerGB2018"
}

resource "azurerm_storage_account" "test_cloudazure" {

  count = length(azurerm_network_interface.test_cloudazure)

  name                     = "account${count.index}"
  resource_group_name     = azurerm_resource_group.test_cloudazure.name
  location                 = azurerm_resource_group.test_cloudazure.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}


#monitor alert 
