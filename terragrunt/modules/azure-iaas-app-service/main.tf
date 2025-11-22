terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# -----------------------------
# Réseau : VNet + Subnet + NSG
# -----------------------------
resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-${var.environment}-vnet"
  address_space       = var.vnet_address_space
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_subnet" "app" {
  name                 = "${var.project_name}-${var.environment}-app-subnet"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_address_prefixes
}

# Database Subnet
resource "azurerm_subnet" "db" {
  name                 = "${var.project_name}-${var.environment}-db-subnet"
  resource_group_name  = data.azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_security_group" "app" {
  name                = "${var.project_name}-${var.environment}-nsg"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSH"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# Database NSG - Only allow MySQL from app subnet
resource "azurerm_network_security_group" "db" {
  name                = "${var.project_name}-${var.environment}-db-nsg"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowMySQLFromApp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowSSHFromApp"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}


# ------------------------------------------------------------------
# Option SANS LB : une IP Publique par VM (si LB désactivé)
# ------------------------------------------------------------------
resource "azurerm_public_ip" "vm" {
  count               = var.enable_load_balancer ? 0 : var.vm_count
  name                = "${var.project_name}-${var.environment}-pip-${count.index}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# ------------------------------------------------------------------
# Option AVEC LB : toutes les ressources du LB en count conditionnel
# ------------------------------------------------------------------

# IP publique du LB
resource "azurerm_public_ip" "lb" {
  count               = var.enable_load_balancer ? 1 : 0
  name                = "${var.project_name}-${var.environment}-lb-pip"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Load Balancer
resource "azurerm_lb" "main" {
  count               = var.enable_load_balancer ? 1 : 0
  name                = "${var.project_name}-${var.environment}-lb"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb[0].id
  }

  tags = var.tags
}

# Backend pool
resource "azurerm_lb_backend_address_pool" "main" {
  count           = var.enable_load_balancer ? 1 : 0
  loadbalancer_id = azurerm_lb.main[0].id
  name            = "BackEndAddressPool"
}

# Health probe
resource "azurerm_lb_probe" "http" {
  count           = var.enable_load_balancer ? 1 : 0
  loadbalancer_id = azurerm_lb.main[0].id
  name            = "http-probe"
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

# Règle LB HTTP
resource "azurerm_lb_rule" "http" {
  count                          = var.enable_load_balancer ? 1 : 0
  loadbalancer_id                = azurerm_lb.main[0].id
  name                           = "HTTPRule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main[0].id]
  probe_id                       = azurerm_lb_probe.http[0].id
}

# -------------------------------------------------
# NICs : attachent une PIP si pas de LB, sinon rien
# -------------------------------------------------
resource "azurerm_network_interface" "vm" {
  count               = var.vm_count
  name                = "${var.project_name}-${var.environment}-nic-${count.index}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.enable_load_balancer ? null : azurerm_public_ip.vm[count.index].id
  }

  tags = var.tags
}

# Association NIC ↔ backend pool du LB (si LB activé)
resource "azurerm_network_interface_backend_address_pool_association" "vm" {
  count                   = var.enable_load_balancer ? var.vm_count : 0
  network_interface_id    = azurerm_network_interface.vm[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main[0].id
}

# -----------------------------
# App VMs (Traefik + Application)
# -----------------------------
resource "azurerm_linux_virtual_machine" "vm" {
  count               = var.vm_count
  name                = "${var.project_name}-${var.environment}-vm-${count.index}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  size                = "Standard_B1ls"
  # size                = var.vm_size
  admin_username = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.vm[count.index].id,
  ]

  # Use custom image if provided, otherwise use marketplace image
  source_image_id = var.custom_image_id != "" ? var.custom_image_id : null

  dynamic "source_image_reference" {
    for_each = var.custom_image_id == "" ? [1] : []
    content {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-server-jammy"
      sku       = "22_04-lts-gen2"
      version   = "latest"
    }
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-app.yaml", {
    acr_login_server   = var.acr_login_server
    acr_admin_username = var.acr_admin_username
    acr_admin_password = var.acr_admin_password
    docker_image       = var.docker_image
    docker_image_tag   = var.docker_image_tag
    db_name            = var.db_name
    db_username        = var.db_admin_username
    db_password        = var.db_admin_password
    db_root_password   = var.db_root_password
    app_key            = var.app_key
    app_settings       = jsonencode(var.app_settings)
  }))

  tags = var.tags
}

# Autoriser la VM à pull depuis l’ACR
resource "azurerm_role_assignment" "vm_to_acr" {
  count                = var.vm_count
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_virtual_machine.vm[count.index].identity[0].principal_id
}

# -----------------------------
# IaaS: MySQL runs in Docker Compose on VM
# No Azure managed MySQL needed
# Ansible handles rolling updates via Traefik
# -----------------------------

# -----------------------------
# Database VMs (MariaDB)
# -----------------------------

# NIC for DB VMs (no public IP)
resource "azurerm_network_interface" "db" {
  count               = var.db_vm_count
  name                = "${var.project_name}-${var.environment}-db-nic-${count.index}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.db.id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost("10.0.2.0/24", 4 + count.index)
  }

  tags = var.tags
}

resource "azurerm_linux_virtual_machine" "db" {
  count               = var.db_vm_count
  name                = "${var.project_name}-${var.environment}-db-vm-${count.index}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  size                = var.db_vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.db[count.index].id,
  ]

  source_image_id = var.custom_image_id != "" ? var.custom_image_id : null

  dynamic "source_image_reference" {
    for_each = var.custom_image_id == "" ? [1] : []
    content {
      publisher = "Canonical"
      offer     = "0001-com-ubuntu-server-jammy"
      sku       = "22_04-lts-gen2"
      version   = "latest"
    }
  }

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/cloud-init-db.yaml", {
    db_name          = var.db_name
    db_username      = var.db_admin_username
    db_password      = var.db_admin_password
    db_root_password = var.db_root_password
  }))

  tags = var.tags
}
