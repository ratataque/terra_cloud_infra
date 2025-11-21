include "root" {
  path = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../modules/azure-iaas-app-service"
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

  # VM Configuration (IaaS)
  vm_size  = "Standard_B2s"  # 2 vCPU, 4 GB RAM for production
  vm_count = 1
  enable_load_balancer = false

  # SSH Key for VM access
  ssh_public_key = get_env("SSH_PUBLIC_KEY", "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... votre-cle-publique")

  # Reference shared ACR
  acr_login_server    = dependency.shared.outputs.acr_login_server
  acr_admin_username  = dependency.shared.outputs.acr_admin_username
  acr_admin_password  = dependency.shared.outputs.acr_admin_password
  acr_id              = dependency.shared.outputs.acr_id

  # Database Configuration (IaaS: MySQL in Docker Compose)
  db_name           = "terracloud_prod"
  db_admin_username = "sqladmin"
  db_admin_password = include.root.locals.db_admin_password
  db_root_password  = include.root.locals.db_root_password

  # Docker Image Configuration
  docker_image     = "app"
  docker_image_tag = get_env("DOCKER_TAG", "latest")

  # Application Settings
  app_key = include.root.locals.common_app_settings["APP_KEY"]

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
