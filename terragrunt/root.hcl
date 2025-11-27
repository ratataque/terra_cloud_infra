# Root Terragrunt Configuration for Azure PaaS
locals {
  # get_path_from_repo_root() returns the relative path from the root 
  # of the Git repository to the current directory.
  # e.g., "terragrunt/iaas/prod"
  path_from_root = get_path_from_repo_root()

  # The key used in the storage_account_map, e.g., "iaas/prod"
  map_key = replace(local.path_from_root, "terragrunt/", "")
  
  # If you still need the absolute path to the repo root for other variables:
  repo_root = get_repo_root()

  # --- Original Logic (now using robust path) ---
  env         = basename(get_terragrunt_dir())
  region      = get_env("AZURE_REGION", "France Central")

  # Map each environment to its own storage account
  storage_account_map = {
    "shared"    = "tfstatesharedcloud"
    "iaas/qa"   = "tfstateiaasqa"
    "iaas/prod" = "tfstateiaasprod"
    "paas/qa"   = "tfstatepaasqa"
    "paas/prod" = "tfstatepaasprod"
  }
  
  # Get the storage account for this environment
  storage_account_name = lookup(local.storage_account_map, local.map_key, "terracloudtfstate")
  
  # --- The rest of the locals are unchanged ---
  # Project-wide configuration
  resource_group_name = "rg-stg_1"
  project_name        = "terracloud"
  location            = "westeurope"
  
  # Custom VM image with Docker pre-installed
  custom_image_id = "/subscriptions/6b9318b1-2215-418a-b0fd-ba0832e9b333/resourceGroups/rg-stg_1/providers/Microsoft.Compute/images/vm-optimized-img"
  
  # Database common configuration
  db_admin_password = get_env("DB_ADMIN_PASSWORD", "TerraCloud2024!")
  db_root_password  = get_env("DB_ROOT_PASSWORD", "RootTerraCloud2024!")
  
  # SSH Configuration for IaaS VMs
  # Must be a valid SSH public key (ssh-rsa, ssh-ed25519, etc.)
  ssh_public_key = get_env("SSH_PUBLIC_KEY", "")
  
  # Docker configuration
  docker_image_base = "app"
  
  # Common app settings
  common_app_settings = {
    "APP_NAME"    = "TerraCloud"
    "APP_KEY"     = get_env("TF_VAR_APP_KEY", "base64:wkuprmf1hR1Z5e+MHa/9gAXI69/n6N6KYiOINXwRmq0=")
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
    resource_group_name  = "rg-stg_1"
    storage_account_name = local.storage_account_name
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
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
