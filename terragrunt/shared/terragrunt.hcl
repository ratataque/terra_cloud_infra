include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../modules/azure-shared-infra"
}

inputs = {
  resource_group_name = include.root.locals.resource_group_name
  project_name        = include.root.locals.project_name
  location            = include.root.locals.location

  tags = merge(
    include.root.locals.common_tags,
    {
      Environment = "Shared"
      Purpose     = "Shared Infrastructure"
    }
  )

  acr_sku                  = "Standard"
  storage_account_tier     = "Standard"
  storage_replication_type = "LRS"
}
