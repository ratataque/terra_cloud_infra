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

resource "azurerm_container_registry" "shared" {
  name                = "${var.project_name}sharedacr"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = true

  tags = var.tags
}

# resource "azurerm_storage_account" "shared" {
#   name                     = "${var.project_name}sharedsa"
#   resource_group_name      = data.azurerm_resource_group.main.name
#   location                 = data.azurerm_resource_group.main.location
#   account_tier             = var.storage_account_tier
#   account_replication_type = var.storage_replication_type
#
#   tags = var.tags
# }
