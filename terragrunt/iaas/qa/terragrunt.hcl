include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../modules/azure-paas-app-service"
}

dependency "shared" {
  config_path = "../../shared"
}

inputs = {
  resource_group_name = include.root.locals.resource_group_name
  project_name        = include.root.locals.project_name
  environment         = "qa"
  location            = include.root.locals.location

  tags = merge(
    include.root.locals.common_tags,
    {
      Environment = "QA"
    }
  )

  app_service_plan_sku = "B1"

  # Reference shared ACR
  acr_login_server    = dependency.shared.outputs.acr_login_server
  acr_admin_username  = dependency.shared.outputs.acr_admin_username
  acr_admin_password  = dependency.shared.outputs.acr_admin_password
  acr_id              = dependency.shared.outputs.acr_id

  db_name           = "terracloud_qa"
  db_admin_username = "dbadmin"
  db_admin_password = include.root.locals.db_admin_password
  db_sku            = "B_Standard_B1ms"
  db_storage_gb     = 20

  docker_image     = "app"  # Just the image name, not the full path
  docker_image_tag = get_env("DOCKER_TAG", "latest")

  app_settings = merge(
    include.root.locals.common_app_settings,
    {
      "APP_ENV"     = "qa"
      "APP_DEBUG"   = "false"
      "APP_URL"     = "https://terracloud-qa-app.azurewebsites.net"
      "LOG_LEVEL"   = "debug"
    }
  )
}
