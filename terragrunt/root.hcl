# Root Terragrunt Configuration for Azure PaaS
locals {
  env         = basename(get_terragrunt_dir())
  region      = get_env("AZURE_REGION", "France Central")
  
  # Project-wide configuration
  resource_group_name = "rg-stg_1"
  project_name        = "terracloud"
  location            = "westeurope"
  
  # Database common configuration
  db_admin_password = get_env("DB_ADMIN_PASSWORD", "TerraCloud2024!")
  
  # Docker configuration
  docker_image_base = "app"
  
  # Common app settings
  common_app_settings = {
    "APP_NAME"    = "TerraCloud"
    "APP_KEY"     = get_env("TF_VAR_APP_KEY", "base64:PLACEHOLDER-CHANGE-BEFORE-APPLY")
    "LOG_CHANNEL" = "stack"
  }
  
  # Common tags
  common_tags = {
    CostCenter = "Engineering"
  }
  
  tags = {
    Environment = local.env
    ManagedBy   = "Terragrunt"
    Project     = "TerraCloud"
  }
}

remote_state {
  backend = "azurerm"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    resource_group_name  = get_env("TF_STATE_RG", "rg-stg_1")
    storage_account_name = get_env("TF_STATE_SA", "terracloudtfstate")
    container_name       = "tfstate"
    key                  = "${local.env}/terraform.tfstate"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
  subscription_id = "6b9318b1-2215-418a-b0fd-ba0832e9b333"
}
EOF
}
