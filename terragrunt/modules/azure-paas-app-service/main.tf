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

resource "azurerm_mysql_flexible_server" "main" {
  name                   = "${var.project_name}-${var.environment}-mysql"
  resource_group_name    = data.azurerm_resource_group.main.name
  location               = data.azurerm_resource_group.main.location
  administrator_login    = var.db_admin_username
  administrator_password = var.db_admin_password
  sku_name               = var.db_sku
  version                = "8.0.21"

  storage {
    size_gb = var.db_storage_gb
  }

  tags = var.tags
}

resource "azurerm_mysql_flexible_server_firewall_rule" "azure_services" {
  name                = "AllowAzureServices"
  resource_group_name = data.azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.main.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

resource "azurerm_mysql_flexible_database" "main" {
  name                = var.db_name
  resource_group_name = data.azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

resource "azurerm_service_plan" "main" {
  name                = "${var.project_name}-${var.environment}-asp"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku

  tags = var.tags
}

resource "azurerm_linux_web_app" "main" {
  name                = "${var.project_name}-${var.environment}-app"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  site_config {
    always_on     = var.environment == "prod" ? true : false
    http2_enabled = true
    ftps_state    = "Disabled"

    application_stack {
      docker_image_name        = "${var.docker_image}:${var.docker_image_tag}"
      docker_registry_url      = "https://${var.acr_login_server}"
      docker_registry_username = var.acr_admin_username
      docker_registry_password = var.acr_admin_password
    }
  }

  app_settings = merge(var.app_settings, {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "DOCKER_ENABLE_CI"                    = "true"
    "DB_CONNECTION"                       = "mysql"
    "DB_HOST"                             = azurerm_mysql_flexible_server.main.fqdn
    "DB_PORT"                             = "3306"
    "DB_DATABASE"                         = azurerm_mysql_flexible_database.main.name
    "DB_USERNAME"                         = azurerm_mysql_flexible_server.main.administrator_login
    "DB_PASSWORD"                         = azurerm_mysql_flexible_server.main.administrator_password
  })

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "app_to_acr" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.main.identity[0].principal_id
}

# Create ACR webhook for this app service
resource "azurerm_container_registry_webhook" "app" {
  name                = "${var.project_name}${var.environment}hook"
  registry_name       = split("/", var.acr_id)[8] # Extract ACR name from resource ID
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location

  service_uri = format(
    "https://$%s:%s@%s.scm.azurewebsites.net/docker/hook",
    azurerm_linux_web_app.main.name,
    azurerm_linux_web_app.main.site_credential[0].password,
    azurerm_linux_web_app.main.name
  )
  status  = "enabled"
  scope   = "app:latest"
  actions = ["push"]

  custom_headers = {
    "Content-Type" = "application/json"
  }

  tags = var.tags
}
