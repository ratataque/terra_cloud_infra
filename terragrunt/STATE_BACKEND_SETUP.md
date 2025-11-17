# Azure Storage Account State Backend - Ideal Setup

## Overview

Terraform state tracks your infrastructure resources. Using Azure Storage Account as the backend allows:
- **Shared State**: Multiple team members can work on the same infrastructure
- **State Locking**: Prevents concurrent modifications that could corrupt state
- **Versioning**: Track state file history and enable rollbacks
- **Security**: Encrypted storage with access controls
- **Durability**: Azure handles backups and redundancy

## Architecture

```
Azure Storage Account (Remote Backend)
├── Container: tfstate
│   ├── qa/terraform.tfstate           # QA environment state
│   ├── prod/terraform.tfstate         # Production environment state
│   └── .terraform.lock.hcl            # State locking info
└── Features:
    ├── Versioning (Blob soft delete)
    ├── Encryption at rest
    ├── Private endpoint (optional)
    └── RBAC access control
```

## Ideal Setup Script

### Production-Ready Configuration

```bash
#!/bin/bash

# Configuration
RESOURCE_GROUP="terracloud-tfstate-rg"
STORAGE_ACCOUNT="terracloudtfstate"
LOCATION="westeurope"
CONTAINER_NAME="tfstate"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# 1. Create dedicated resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --tags \
    Environment=Shared \
    Purpose=TerraformState \
    ManagedBy=Manual

# 2. Create storage account with enhanced security
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_GRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true \
  --encryption-services blob file \
  --default-action Deny

# 3. Enable versioning for state file recovery
az storage account blob-service-properties update \
  --account-name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --enable-versioning true \
  --enable-change-feed true

# 4. Enable soft delete (30 days retention)
az storage account blob-service-properties update \
  --account-name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --enable-delete-retention true \
  --delete-retention-days 30 \
  --enable-container-delete-retention true \
  --container-delete-retention-days 30

# 5. Create container with private access
az storage container create \
  --name $CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT \
  --auth-mode login \
  --public-access off

# 6. Enable diagnostic logging
WORKSPACE_ID=$(az monitor log-analytics workspace create \
  --resource-group $RESOURCE_GROUP \
  --workspace-name "$STORAGE_ACCOUNT-logs" \
  --location $LOCATION \
  --query id -o tsv)

az monitor diagnostic-settings create \
  --name "tfstate-diagnostics" \
  --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
  --workspace $WORKSPACE_ID \
  --logs '[
    {
      "category": "StorageRead",
      "enabled": true
    },
    {
      "category": "StorageWrite",
      "enabled": true
    },
    {
      "category": "StorageDelete",
      "enabled": true
    }
  ]' \
  --metrics '[
    {
      "category": "Transaction",
      "enabled": true
    }
  ]'

# 7. Create lock to prevent accidental deletion
az lock create \
  --name "DoNotDelete" \
  --resource-group $RESOURCE_GROUP \
  --lock-type CanNotDelete \
  --notes "Protect Terraform state storage"

# 8. Output configuration
echo "========================================="
echo "Terraform State Backend Configuration"
echo "========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Storage Account: $STORAGE_ACCOUNT"
echo "Container: $CONTAINER_NAME"
echo "Location: $LOCATION"
echo ""
echo "Export these environment variables:"
echo "export TF_STATE_RG=\"$RESOURCE_GROUP\""
echo "export TF_STATE_SA=\"$STORAGE_ACCOUNT\""
echo "========================================="
```

## Key Features Explained

### 1. **Standard_GRS (Geo-Redundant Storage)**
- Data replicated to secondary region (hundreds of miles away)
- Protects against regional disasters
- Essential for production state files

**Alternative Options:**
- `Standard_LRS`: Cheaper, local redundancy only (dev/test)
- `Standard_ZRS`: Zone-redundant within region (good middle ground)

### 2. **Blob Versioning**
- Every state file change creates a new version
- Can restore previous versions if state becomes corrupted
- Essential for disaster recovery

### 3. **Soft Delete (30 days)**
- Deleted state files recoverable for 30 days
- Protects against accidental deletion
- Compliance requirement for many organizations

### 4. **Private Access**
- No public internet access to blobs
- Access only via Azure AD authentication
- Can add private endpoints for additional security

### 5. **Encryption**
- Automatic encryption at rest (Microsoft-managed keys)
- HTTPS enforced for all connections
- TLS 1.2 minimum

### 6. **State Locking**
- Azure automatically provides locking via blob leases
- Prevents concurrent `terraform apply` operations
- No additional configuration needed

## Access Control Setup

### Option 1: Service Principal (CI/CD)

```bash
# Create service principal for Terraform
SP_NAME="terraform-deployer"
SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

SP=$(az ad sp create-for-rbac \
  --name $SP_NAME \
  --role "Storage Blob Data Contributor" \
  --scopes $SCOPE \
  --sdk-auth)

echo "Save these credentials securely:"
echo $SP | jq .
```

### Option 2: User Access (Developers)

```bash
# Grant developer access to state
USER_EMAIL="developer@company.com"

az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee $USER_EMAIL \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
```

### Option 3: Managed Identity (Recommended for VMs)

```bash
# If running Terraform from Azure VM
VM_IDENTITY=$(az vm show \
  --resource-group my-vm-rg \
  --name terraform-vm \
  --query identity.principalId -o tsv)

az role assignment create \
  --role "Storage Blob Data Contributor" \
  --assignee-object-id $VM_IDENTITY \
  --assignee-principal-type ServicePrincipal \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
```

## Enhanced Terragrunt Configuration

Update `terragrunt/terragrunt.hcl`:

```hcl
# Root Terragrunt Configuration for Azure PaaS
locals {
  env    = basename(get_terragrunt_dir())
  region = get_env("AZURE_REGION", "westeurope")
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
    resource_group_name  = get_env("TF_STATE_RG", "terracloud-tfstate-rg")
    storage_account_name = get_env("TF_STATE_SA", "terracloudtfstate")
    container_name       = "tfstate"
    key                  = "${local.env}/terraform.tfstate"
    
    # Enhanced security options
    use_azuread_auth     = true  # Use Azure AD instead of storage keys
    use_msi              = false # Set to true if using Managed Identity
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
  
  # Optional: specify subscription
  subscription_id = "${get_env("AZURE_SUBSCRIPTION_ID", "")}"
}

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
EOF
}
```

## Authentication Methods

### Method 1: Azure CLI (Development)

```bash
# Already logged in with az login
cd terragrunt/qa
terragrunt init  # Automatically uses your Azure CLI credentials
```

### Method 2: Service Principal (CI/CD)

```bash
# Set environment variables
export ARM_CLIENT_ID="00000000-0000-0000-0000-000000000000"
export ARM_CLIENT_SECRET="your-secret"
export ARM_TENANT_ID="00000000-0000-0000-0000-000000000000"
export ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"

terragrunt init
```

### Method 3: Managed Identity (Azure VMs)

```bash
# No credentials needed when running on Azure VM with assigned identity
export ARM_USE_MSI=true
terragrunt init
```

## State File Structure

Each environment gets its own state file:

```
tfstate/
├── qa/
│   └── terraform.tfstate          # QA environment resources
├── prod/
│   └── terraform.tfstate          # Production environment resources
└── dev/                           # Optional: development environment
    └── terraform.tfstate
```

Benefits:
- **Isolation**: Changes in QA don't affect prod state
- **Security**: Can apply different access controls per environment
- **Clarity**: Each team member knows which state file to use

## State Management Commands

### View Current State

```bash
cd terragrunt/qa
terragrunt show
```

### List Resources in State

```bash
terragrunt state list
```

### View State File Versions (Azure Portal)

1. Navigate to Storage Account → Containers → tfstate
2. Click on `qa/terraform.tfstate`
3. Click "Versions" tab to see all historical versions

### Restore Previous State Version

```bash
# Download specific version from Azure
az storage blob download \
  --account-name terracloudtfstate \
  --container-name tfstate \
  --name qa/terraform.tfstate \
  --version-id "2024-01-15T10:30:00.0000000Z" \
  --file terraform.tfstate.backup \
  --auth-mode login

# Restore it (be careful!)
terragrunt state push terraform.tfstate.backup
```

## Monitoring and Alerts

### Set Up Alert for State Changes

```bash
# Create alert when state file is modified
az monitor metrics alert create \
  --name "terraform-state-modified" \
  --resource-group $RESOURCE_GROUP \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
  --condition "avg Transactions > 0" \
  --description "Alert when Terraform state is modified" \
  --evaluation-frequency 5m \
  --window-size 5m \
  --action email admin@company.com
```

### Query State Access Logs

```bash
# View who accessed state files
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "
    StorageBlobLogs
    | where TimeGenerated > ago(7d)
    | where Uri contains 'terraform.tfstate'
    | project TimeGenerated, OperationName, CallerIpAddress, UserAgentHeader
    | order by TimeGenerated desc
  " \
  --output table
```

## Cost Optimization

Current setup cost estimate:
- **Standard_GRS Storage**: ~$0.05/GB/month
- **Typical state file size**: 1-10 MB
- **Versioning overhead**: ~2-5x original size
- **Monthly cost**: < $1 USD for typical usage

To reduce costs (for dev/test):
```bash
# Use Standard_LRS instead
az storage account update \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --sku Standard_LRS
```

## Security Best Practices

1. **Never commit state files to Git**
   ```bash
   # Add to .gitignore
   echo "**/*.tfstate" >> .gitignore
   echo "**/*.tfstate.backup" >> .gitignore
   echo ".terraform/" >> .gitignore
   ```

2. **Use Azure AD authentication** (not storage account keys)
   ```hcl
   # In terragrunt.hcl
   use_azuread_auth = true
   ```

3. **Rotate storage keys regularly** (if you must use them)
   ```bash
   az storage account keys renew \
     --account-name $STORAGE_ACCOUNT \
     --resource-group $RESOURCE_GROUP \
     --key primary
   ```

4. **Enable firewall rules**
   ```bash
   # Allow only specific IPs
   az storage account network-rule add \
     --account-name $STORAGE_ACCOUNT \
     --resource-group $RESOURCE_GROUP \
     --ip-address "203.0.113.0/24"
   ```

## Disaster Recovery

### Backup Strategy

1. **Automatic**: Azure handles geo-redundancy
2. **Versioning**: Previous versions available for 30 days
3. **Manual**: Periodic downloads for critical states

```bash
# Manual backup script
#!/bin/bash
BACKUP_DIR="state-backups/$(date +%Y-%m-%d)"
mkdir -p $BACKUP_DIR

for ENV in qa prod; do
  az storage blob download \
    --account-name terracloudtfstate \
    --container-name tfstate \
    --name "$ENV/terraform.tfstate" \
    --file "$BACKUP_DIR/$ENV-terraform.tfstate" \
    --auth-mode login
done
```

### Recovery Scenarios

**Scenario 1: Corrupted State**
```bash
# List versions
az storage blob list \
  --account-name terracloudtfstate \
  --container-name tfstate \
  --prefix qa/ \
  --include v \
  --auth-mode login

# Restore previous version
az storage blob download \
  --account-name terracloudtfstate \
  --container-name tfstate \
  --name qa/terraform.tfstate \
  --version-id "<version-id>" \
  --file terraform.tfstate \
  --auth-mode login

terragrunt state push terraform.tfstate
```

**Scenario 2: Accidental Deletion**
```bash
# Recover from soft delete (within 30 days)
az storage blob undelete \
  --account-name terracloudtfstate \
  --container-name tfstate \
  --name qa/terraform.tfstate \
  --auth-mode login
```

**Scenario 3: Regional Disaster**
```bash
# With Standard_GRS, initiate failover
az storage account failover \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP
```

## Migration from Local State

If you're currently using local state:

```bash
# 1. Set up remote backend (run setup script above)

# 2. Update terragrunt.hcl with remote_state config

# 3. Re-initialize with migration
cd terragrunt/qa
terragrunt init -migrate-state

# 4. Verify
terragrunt state list

# 5. Delete local state files
rm -f terraform.tfstate terraform.tfstate.backup
```

## Troubleshooting

### Issue: "Failed to acquire state lock"

```bash
# Check if lock exists
az storage blob show \
  --account-name terracloudtfstate \
  --container-name tfstate \
  --name qa/terraform.tfstate \
  --auth-mode login

# Force unlock (careful!)
terragrunt force-unlock <lock-id>
```

### Issue: "Authorization failed"

```bash
# Verify RBAC assignment
az role assignment list \
  --assignee $(az ad signed-in-user show --query id -o tsv) \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

# Re-authenticate
az login
```

### Issue: "Storage account not found"

```bash
# Verify environment variables
echo $TF_STATE_RG
echo $TF_STATE_SA

# Check if storage account exists
az storage account show \
  --name $TF_STATE_SA \
  --resource-group $TF_STATE_RG
```

## Summary

**Ideal setup includes:**
- ✅ Geo-redundant storage (Standard_GRS)
- ✅ Blob versioning enabled
- ✅ Soft delete (30 days)
- ✅ Private access only
- ✅ Azure AD authentication
- ✅ Diagnostic logging
- ✅ Resource lock protection
- ✅ Separate state files per environment

This provides enterprise-grade state management with security, reliability, and disaster recovery capabilities.
