variable "resource_group_name" {
  description = "The name of the existing resource group to use"
  type        = string
}

variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "acr_sku" {
  description = "The SKU tier of the Container Registry"
  type        = string
  default     = "Standard"
}

# variable "storage_account_tier" {
#   description = "The tier of the storage account"
#   type        = string
#   default     = "Standard"
# }
#
# variable "storage_replication_type" {
#   description = "The replication type for the storage account"
#   type        = string
#   default     = "LRS"
# }
