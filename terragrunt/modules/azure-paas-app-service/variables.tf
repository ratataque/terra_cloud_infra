variable "resource_group_name" {
  description = "The name of the existing resource group to use"
  type        = string
}

variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "environment" {
  description = "The environment (e.g., dev, qa, prod)"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "westeurope"
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "docker_image" {
  description = "The Docker image name (without tag)"
  type        = string
}

variable "docker_image_tag" {
  description = "The tag of the Docker image to deploy"
  type        = string
  default     = "latest"
}

variable "app_settings" {
  description = "A map of application settings for the App Service"
  type        = map(string)
  default     = {}
}

variable "db_name" {
  description = "The name of the MySQL database to create"
  type        = string
  default     = "laravel"
}

variable "db_admin_username" {
  description = "The admin username for the MySQL server"
  type        = string
}

variable "db_admin_password" {
  description = "The admin password for the MySQL server"
  type        = string
  sensitive   = true
}

variable "app_service_plan_sku" {
  description = "The SKU for the App Service Plan"
  type        = string
  default     = "B1"
}

variable "db_sku" {
  description = "The SKU for the MySQL Flexible Server"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "db_storage_gb" {
  description = "The storage size in GB for the MySQL Flexible Server"
  type        = number
  default     = 20
}

variable "acr_login_server" {
  description = "The login server URL for the Azure Container Registry"
  type        = string
}

variable "acr_admin_username" {
  description = "The admin username for the Azure Container Registry"
  type        = string
  sensitive   = true
}

variable "acr_admin_password" {
  description = "The admin password for the Azure Container Registry"
  type        = string
  sensitive   = true
}

variable "acr_id" {
  description = "The ID of the Azure Container Registry for role assignment"
  type        = string
}
