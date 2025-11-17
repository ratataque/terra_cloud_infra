# Azure PaaS Infrastructure

This Terragrunt configuration manages Azure PaaS resources for the TerraCloud application.

## Structure

```
terragrunt/
├── terragrunt.hcl           # Root configuration with Azure backend
├── modules/
│   └── azure-app-service/   # Reusable Terraform module
│       ├── main.tf          # Main resource definitions
│       ├── variables.tf     # Input variables
│       └── outputs.tf       # Output values
├── prod/                    # Production environment
│   └── terragrunt.hcl
└── qa/                      # QA environment
    └── terragrunt.hcl
```

## Resources Deployed

Each environment provisions:
- **Resource Group**: Container for all resources
- **Container Registry (ACR)**: Private Docker registry
- **MySQL Flexible Server**: Managed database with automated backups
- **App Service Plan**: Compute resources for web apps
- **Linux Web App**: Containerized application hosting
- **IAM**: Managed identity and role assignments

## Prerequisites

1. Azure CLI installed and authenticated
2. Terragrunt installed
3. Environment variables set:
   - `DB_ADMIN_PASSWORD`: MySQL admin password
   - `APP_KEY`: Laravel application key
   - `TF_STATE_RG`: (Optional) Terraform state resource group
   - `TF_STATE_SA`: (Optional) Terraform state storage account

## Usage

### Deploy QA Environment
```bash
cd qa
terragrunt init
terragrunt plan
terragrunt apply
```

### Deploy Production Environment
```bash
cd prod
terragrunt init
terragrunt plan
terragrunt apply
```

### Destroy Environment
```bash
terragrunt destroy
```

## Environment Differences

| Resource | QA | Production |
|----------|-----|------------|
| App Service Plan | B2 | P1v3 |
| ACR SKU | Basic | Standard |
| Database SKU | B_Standard_B2s | GP_Standard_D2ds_v4 |
| Storage | 20GB | 100GB |

## Security Features

- HTTPS enforced on App Service
- System-assigned managed identity
- Private ACR access via role assignment
- Firewall rules for database access
- Sensitive values in environment variables
