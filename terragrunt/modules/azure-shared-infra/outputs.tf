output "acr_name" {
  description = "The name of the Azure Container Registry"
  value       = azurerm_container_registry.shared.name
}

output "acr_login_server" {
  description = "The login server URL for the Azure Container Registry"
  value       = azurerm_container_registry.shared.login_server
}

output "acr_admin_username" {
  description = "The admin username for the Azure Container Registry"
  value       = azurerm_container_registry.shared.admin_username
  sensitive   = true
}

output "acr_admin_password" {
  description = "The admin password for the Azure Container Registry"
  value       = azurerm_container_registry.shared.admin_password
  sensitive   = true
}

output "acr_id" {
  description = "The ID of the Azure Container Registry"
  value       = azurerm_container_registry.shared.id
}

# output "storage_account_name" {
#   description = "The name of the storage account"
#   value       = azurerm_storage_account.shared.name
# }
#
# output "storage_account_primary_access_key" {
#   description = "The primary access key for the storage account"
#   value       = azurerm_storage_account.shared.primary_access_key
#   sensitive   = true
# }
#
# output "storage_account_primary_connection_string" {
#   description = "The primary connection string for the storage account"
#   value       = azurerm_storage_account.shared.primary_connection_string
#   sensitive   = true
# }
