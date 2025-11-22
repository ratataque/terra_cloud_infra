# ======================================================
# Informations générales
# ======================================================

output "resource_group_name" {
  description = "The name of the resource group"
  value       = data.azurerm_resource_group.main.name
}

output "vnet_name" {
  description = "The name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "subnet_id" {
  description = "The ID of the application subnet"
  value       = azurerm_subnet.app.id
}

# ======================================================
# Load Balancer (optionnel)
# ======================================================

output "load_balancer_public_ip" {
  description = "The public IP address of the Load Balancer (null if LB disabled)"
  value       = (
    var.enable_load_balancer && length(azurerm_public_ip.lb) > 0
    ? azurerm_public_ip.lb[0].ip_address
    : null
  )
}

output "load_balancer_url" {
  description = "The URL to access the application via Load Balancer (null if LB disabled)"
  value       = (
    var.enable_load_balancer && length(azurerm_public_ip.lb) > 0
    ? "http://${azurerm_public_ip.lb[0].ip_address}"
    : null
  )
}

# ======================================================
# Virtual Machines
# ======================================================

output "vm_names" {
  description = "The names of the virtual machines"
  value       = azurerm_linux_virtual_machine.vm[*].name
}

output "vm_private_ips" {
  description = "The private IP addresses of the virtual machines"
  value       = azurerm_network_interface.vm[*].private_ip_address
}

output "vm_public_ips" {
  description = "The public IPs of the VMs when Load Balancer is disabled"
  value       = (
    var.enable_load_balancer
    ? []
    : [for ip in azurerm_public_ip.vm : ip.ip_address]
  )
}

# ======================================================
# Base de données MySQL (IaaS: runs in Docker Compose on separate VM)
# ======================================================

output "db_vm_names" {
  description = "The names of the database virtual machines"
  value       = azurerm_linux_virtual_machine.db[*].name
}

output "db_vm_private_ips" {
  description = "The private IP addresses of the database VMs"
  value       = azurerm_network_interface.db[*].private_ip_address
}

output "database_host" {
  description = "The database host (private IP of DB VM)"
  value       = length(azurerm_network_interface.db) > 0 ? azurerm_network_interface.db[0].private_ip_address : "10.0.2.4"
}

output "database_name" {
  description = "The name of the database"
  value       = var.db_name
}
