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

# VM Configuration
variable "vm_size" {
  description = "The size of the Virtual Machine"
  type        = string
  default     = "Standard_B1s"
}

variable "vm_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 1
}

variable "admin_username" {
  description = "Admin username for the VMs"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for the subnet"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

# Database Configuration
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
  description = "The admin password for the MySQL database"
  type        = string
  sensitive   = true
}

variable "db_root_password" {
  description = "The root password for MySQL (IaaS mode)"
  type        = string
  sensitive   = true
}

# ACR Configuration
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

# Application Configuration
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
  description = "A map of application settings"
  type        = map(string)
  default     = {}
}

variable "app_key" {
  description = "The application encryption key (Laravel APP_KEY)"
  type        = string
  sensitive   = true
}

variable "enable_load_balancer" {
  description = "Create an Azure Load Balancer. Must be false where policy denies LB."
  type        = bool
  default     = false
}
