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
  environment         = "prod"
  location            = include.root.locals.location

  tags = merge(
    include.root.locals.common_tags,
    {
      Environment = "Production"
    }
  )

  app_service_plan_sku = "P1v3"

  # Reference shared ACR
  acr_login_server    = dependency.shared.outputs.acr_login_server
  acr_admin_username  = dependency.shared.outputs.acr_admin_username
  acr_admin_password  = dependency.shared.outputs.acr_admin_password
  acr_id              = dependency.shared.outputs.acr_id

  db_name           = "terracloud_prod"
  db_admin_username = "sqladmin"
  db_admin_password = include.root.locals.db_admin_password
  db_sku            = "GP_Standard_D2ds_v4"
  db_storage_gb     = 100

  docker_image     = "${dependency.shared.outputs.acr_login_server}/${include.root.locals.docker_image_base}"
  docker_image_tag = get_env("DOCKER_TAG", "stable")

  app_settings = merge(
    include.root.locals.common_app_settings,
    {
      "APP_ENV"       = "production"
      "APP_DEBUG"     = "false"
      "APP_URL"       = "https://terracloud-prod-app.azurewebsites.net"
      "LOG_LEVEL"     = "warning"
      "CACHE_DRIVER"  = "redis"
      "SESSION_DRIVER" = "redis"
    }
  )
}
