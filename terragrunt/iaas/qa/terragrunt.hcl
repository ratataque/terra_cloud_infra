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
  environment         = "qa"
  location            = include.root.locals.location

  tags = merge(
    include.root.locals.common_tags,
    {
      Environment = "QA"
    }
  )

  # VM Configuration (remplace App Service Plan du PaaS)
  vm_size  = "Standard_B1ls"# 1 vCPU, 1 GB RAM
  vm_count = 1               # ne seule VM
  enable_load_balancer = false # (par défaut false, mais explicite)

  # Clé SSH pour accéder aux VMs (vous devez générer une clé SSH)
  ssh_public_key = get_env("SSH_PUBLIC_KEY", "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... votre-cle-publique")

  # Reference shared ACR (t)
  acr_login_server    = dependency.shared.outputs.acr_login_server
  acr_admin_username  = dependency.shared.outputs.acr_admin_username
  acr_admin_password  = dependency.shared.outputs.acr_admin_password
  acr_id              = dependency.shared.outputs.acr_id

  # Database Configuration (IaaS: MySQL in Docker Compose)
  db_name           = "terracloud_qa"
  db_admin_username = "dbadmin"
  db_admin_password = include.root.locals.db_admin_password
  db_root_password  = include.root.locals.db_root_password

  # Docker Image Configuration
  docker_image     = "app"  # Just the image name, not the full path
  docker_image_tag = get_env("DOCKER_TAG", "latest")

  # Application Settings
  app_key = include.root.locals.common_app_settings["APP_KEY"]

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
