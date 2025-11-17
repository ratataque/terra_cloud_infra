output "resource_group_name" {
  description = "The name of the resource group"
  value       = data.azurerm_resource_group.main.name
}

output "app_service_url" {
  description = "The default URL of the App Service"
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "app_service_name" {
  description = "The name of the App Service"
  value       = azurerm_linux_web_app.main.name
}

output "database_host" {
  description = "The FQDN of the MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.main.fqdn
}

output "database_name" {
  description = "The name of the database"
  value       = azurerm_mysql_flexible_database.main.name
}
