# Initial Setup Guide

Complete guide to set up the TerraCloud infrastructure from scratch.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Azure Configuration](#azure-configuration)
- [GitHub Configuration](#github-configuration)
- [Backend Setup](#backend-setup)
- [First Deployment](#first-deployment)
- [Verification](#verification)

---

## Prerequisites

### Required Tools

Install the following tools before proceeding:

```bash
# Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Terraform
wget https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
unzip terraform_1.5.7_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Terragrunt
wget https://github.com/gruntwork-io/terragrunt/releases/download/v0.54.0/terragrunt_linux_amd64
chmod +x terragrunt_linux_amd64
sudo mv terragrunt_linux_amd64 /usr/local/bin/terragrunt

# Ansible
pip3 install ansible

# GitHub CLI (optional)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh
```

### Verify Installations

```bash
az --version          # Azure CLI 2.50+
terraform --version   # Terraform 1.5.7+
terragrunt --version  # Terragrunt 0.54.0+
ansible --version     # Ansible 2.9+
gh --version          # GitHub CLI (optional)
```

---

## Azure Configuration

### 1. Login to Azure

```bash
az login
```

### 2. Set Subscription

```bash
# List subscriptions
az account list --output table

# Set active subscription
az account set --subscription "YOUR_SUBSCRIPTION_NAME_OR_ID"

# Verify
az account show --output table
```

### 3. Register Resource Providers

```bash
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.DBforMySQL
```

### 4. Create Service Principal with OIDC

This service principal will be used by GitHub Actions to deploy infrastructure.

```bash
# Set variables
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
GITHUB_ORG="ratataque"  # Your GitHub username or org
GITHUB_REPO="terracloud-infra"

# Create Azure AD application
APP_ID=$(az ad app create \
  --display-name "terracloud-cd-deployer" \
  --query appId -o tsv)

echo "Application (Client) ID: $APP_ID"

# Create service principal
az ad sp create --id $APP_ID

# Get service principal object ID
SP_OBJECT_ID=$(az ad sp list \
  --filter "appId eq '$APP_ID'" \
  --query "[0].id" -o tsv)

echo "Service Principal Object ID: $SP_OBJECT_ID"

# Assign Contributor role at subscription level
az role assignment create \
  --assignee $APP_ID \
  --role Contributor \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Get tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Tenant ID: $TENANT_ID"
```

### 5. Configure OIDC Federation

Create federated credentials for GitHub Actions:

```bash
# For main branch
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "GitHub-Main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_ORG'/'$GITHUB_REPO':ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# For pull requests
az ad app federated-credential create \
  --id $APP_ID \
  --parameters '{
    "name": "GitHub-PR",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:'$GITHUB_ORG'/'$GITHUB_REPO':pull_request",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

### 6. Save Credentials

**Save these values** - you'll need them for GitHub secrets:

```bash
echo "=== Save these values for GitHub Secrets ==="
echo "AZURE_CLIENT_ID: $APP_ID"
echo "AZURE_TENANT_ID: $TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
```

---

## GitHub Configuration

### 1. Create GitHub Repository

If not already created:

```bash
gh repo create terracloud-infra --public --description "Infrastructure as Code for TerraCloud"
```

### 2. Configure Repository Secrets

Navigate to: **Settings → Secrets and variables → Actions → New repository secret**

Add the following **repository secrets**:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `AZURE_CLIENT_ID` | (from step above) | Service Principal Application ID |
| `AZURE_TENANT_ID` | (from step above) | Azure AD Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | (from step above) | Azure Subscription ID |
| `SSH_PRIVATE_KEY` | (see below) | Private SSH key for Ansible |
| `SSH_PUBLIC_KEY` | (see below) | Public SSH key for VM provisioning |

### 3. Generate SSH Keys

Generate SSH keys for Ansible to connect to VMs:

```bash
# Generate new key pair
ssh-keygen -t rsa -b 4096 \
  -C "github-actions-deploy" \
  -f ~/.ssh/terracloud_deploy \
  -N ""

# Display private key (for GitHub secret SSH_PRIVATE_KEY)
cat ~/.ssh/terracloud_deploy

# Display public key (for GitHub secret SSH_PUBLIC_KEY)
cat ~/.ssh/terracloud_deploy.pub
```

**Add to GitHub:**
- `SSH_PRIVATE_KEY`: Entire content of `~/.ssh/terracloud_deploy`
- `SSH_PUBLIC_KEY`: Content of `~/.ssh/terracloud_deploy.pub`

### 4. Create GitHub Environments

Navigate to: **Settings → Environments → New environment**

#### QA Environment

- **Name**: `qa`
- **Protection rules**: None (auto-deploy)
- **Environment secrets** (add these):

| Secret Name | Example Value | How to Get |
|-------------|---------------|------------|
| `DB_HOST` | `terracloud-qa-mysql.mysql.database.azure.com` | From Terragrunt output after deployment |
| `DB_PORT` | `3306` | Standard MySQL port |
| `DB_DATABASE` | `terracloud_qa` | Database name |
| `DB_USERNAME` | `dbadmin` | MySQL admin username |
| `DB_PASSWORD` | `SecurePassword123!` | Your chosen password |
| `APP_KEY` | `base64:...` | Run `php artisan key:generate --show` |

#### Production Environment

- **Name**: `prod`
- **Protection rules**: 
  - ✅ Required reviewers: 1-2 people
  - ✅ Wait timer: 5 minutes (optional)
- **Environment secrets** (same as QA but with production values):

| Secret Name | Example Value |
|-------------|---------------|
| `DB_HOST` | `terracloud-prod-mysql.mysql.database.azure.com` |
| `DB_PORT` | `3306` |
| `DB_DATABASE` | `terracloud_prod` |
| `DB_USERNAME` | `dbadmin` |
| `DB_PASSWORD` | `DifferentSecurePassword456!` |
| `APP_KEY` | `base64:...` (different from QA!) |

---

## Backend Setup

Terraform state needs to be stored in Azure Storage.

### 1. Create State Storage

```bash
# Set variables
RESOURCE_GROUP="terracloud-tfstate-rg"
STORAGE_ACCOUNT="terracloudtfstate"  # Must be globally unique
CONTAINER_NAME="tfstate"
LOCATION="westeurope"  # Change to your preferred region

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Create storage account
az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --encryption-services blob

# Create container
az storage container create \
  --name $CONTAINER_NAME \
  --account-name $STORAGE_ACCOUNT \
  --auth-mode login
```

### 2. Verify Backend Configuration

Check that `terragrunt/root.hcl` has the correct backend configuration:

```hcl
remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = "terracloud-tfstate-rg"
    storage_account_name = "terracloudtfstate"
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}
```

---

## First Deployment

### 1. Set SSH Public Key Environment Variable

**Required for local deployments** - Terragrunt needs your SSH public key to configure VM access:

```bash
# Generate SSH key if you haven't already
ssh-keygen -t rsa -b 4096 \
  -C "terracloud-deploy" \
  -f ~/.ssh/terracloud_deploy \
  -N ""

# Export the public key (REQUIRED for terraform/terragrunt apply)
export SSH_PUBLIC_KEY=$(cat ~/.ssh/terracloud_deploy.pub)

# Verify it's set
echo $SSH_PUBLIC_KEY
# Should output: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ...
```

**⚠️ Important**: You must export `SSH_PUBLIC_KEY` before every `terragrunt apply` for IaaS environments in your terminal session.

### 2. Deploy Shared Infrastructure

The shared infrastructure includes the Azure Container Registry (ACR).

```bash
cd terragrunt/shared

# Initialize Terragrunt
terragrunt init

# Review plan
terragrunt plan

# Apply changes
terragrunt apply
```

**Expected outputs:**
```
acr_name = "terracloudacr"
acr_login_server = "terracloudacr.azurecr.io"
```

**Save the ACR name** - you'll need it for the application repository.

### 3. Deploy QA IaaS Environment

**Ensure SSH_PUBLIC_KEY is still exported**:

```bash
# Verify SSH key is set
echo $SSH_PUBLIC_KEY

# If empty, export it again
export SSH_PUBLIC_KEY=$(cat ~/.ssh/terracloud_deploy.pub)

cd terragrunt/iaas/qa

# Initialize
terragrunt init

# Review plan
terragrunt plan

# Apply
terragrunt apply
```

**Expected resources:**
- Virtual Network
- Network Security Group
- Virtual Machine (B1s)
- MySQL Flexible Server
- Public IP address

**Get outputs:**
```bash
terragrunt output
```

**Save these values:**
- `vm_public_ip`: Use for SSH access
- `database_host`: Use in GitHub Environment secrets
- `database_name`: Use in GitHub Environment secrets

### 4. Deploy Production IaaS Environment (Optional)

**Ensure SSH_PUBLIC_KEY is exported**:

```bash
export SSH_PUBLIC_KEY=$(cat ~/.ssh/terracloud_deploy.pub)

cd terragrunt/iaas/prod

terragrunt init
terragrunt plan
terragrunt apply
```

### 5. Deploy PaaS Environments (Optional)

If you want to use App Service instead of VMs:

```bash
# QA PaaS
cd terragrunt/paas/qa
terragrunt init
terragrunt apply

# Production PaaS
cd terragrunt/paas/prod
terragrunt init
terragrunt apply
```

---

## Verification

### 1. Verify Shared Resources

```bash
cd terragrunt/shared
terragrunt output

# Test ACR access
az acr login --name $(terragrunt output -raw acr_name)
```

### 2. Verify QA Environment

```bash
cd terragrunt/iaas/qa

# Get VM IP
VM_IP=$(terragrunt output -raw vm_public_ip)
echo "VM IP: $VM_IP"

# Test SSH access
ssh -i ~/.ssh/terracloud_deploy azureuser@$VM_IP

# Inside VM, check Docker
docker --version
docker ps
```

### 3. Verify Database

```bash
# Get database details
DB_HOST=$(cd terragrunt/iaas/qa && terragrunt output -raw database_host)
DB_NAME=$(cd terragrunt/iaas/qa && terragrunt output -raw database_name)

# Test connection (from VM or with mysql client)
mysql -h $DB_HOST -u dbadmin -p -e "SHOW DATABASES;"
```

### 4. Test GitHub Actions

```bash
# Trigger infrastructure deployment workflow
gh workflow run infra-deploy.yml

# Check workflow status
gh run list --workflow=infra-deploy.yml
```

---

## Security Configuration

### 1. Network Security

The following NSG rules are configured by default:

**Allowed inbound:**
- SSH (22) from your IP (update in Terraform)
- HTTP (80) from anywhere
- HTTPS (443) from anywhere

**Update NSG rules** in `terragrunt/modules/azure-iaas-app-service/main.tf`:

```hcl
security_rule {
  name                       = "SSH"
  priority                   = 1001
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = "YOUR_IP_ADDRESS/32"  # Update this
  destination_address_prefix = "*"
}
```

### 2. MySQL Security

- SSL is required by default
- Firewall allows Azure services
- Admin password stored in GitHub Environment secrets

### 3. ACR Security

- Admin account disabled
- Access via managed identity
- RBAC-based authentication

---

## Troubleshooting Setup

### Issue: Missing SSH_PUBLIC_KEY

**Error**: "Error: ssh_public_key is required"

**Solution**:
```bash
# Generate SSH key if you haven't
ssh-keygen -t rsa -b 4096 -C "terracloud-deploy" -f ~/.ssh/terracloud_deploy -N ""

# Export the public key
export SSH_PUBLIC_KEY=$(cat ~/.ssh/terracloud_deploy.pub)

# Verify
echo $SSH_PUBLIC_KEY

# Then retry terraform/terragrunt apply
```

### Issue: Terraform state lock

**Error**: "Error acquiring the state lock"

**Solution**:
```bash
# List locks
az lock list --resource-group terracloud-tfstate-rg

# If stuck, force unlock (use with caution)
terragrunt force-unlock <LOCK_ID>
```

### Issue: OIDC authentication fails

**Error**: "Failed to exchange OIDC token"

**Solution**:
- Verify federated credential configuration in Azure AD
- Check GitHub secrets are correct
- Ensure service principal has Contributor role

### Issue: Can't SSH to VM

**Error**: "Connection refused" or "Permission denied"

**Solution**:
```bash
# Check NSG rules allow your IP
az network nsg rule list \
  --resource-group terracloud-qa-rg \
  --nsg-name terracloud-qa-nsg \
  --output table

# Check VM is running
az vm list --resource-group terracloud-qa-rg --output table

# Verify SSH key
cat ~/.ssh/terracloud_deploy.pub
```

### Issue: MySQL connection fails

**Error**: "Can't connect to MySQL server"

**Solution**:
- Verify firewall rules allow your IP
- Check SSL certificate is configured
- Test with mysql client from VM

---

## Next Steps

After completing setup:

1. ✅ **Deploy application**: See [DEPLOYMENT.md](DEPLOYMENT.md)
2. ✅ **Configure CI/CD**: See [WORKFLOWS.md](WORKFLOWS.md)
3. ✅ **Review architecture**: See [ARCHITECTURE.md](ARCHITECTURE.md)
4. ✅ **Setup monitoring**: Configure Azure Monitor and alerts

---

## Quick Reference

**Essential commands:**

```bash
# Deploy infrastructure
cd terragrunt/<path>
terragrunt init
terragrunt plan
terragrunt apply

# View outputs
terragrunt output

# Destroy (if needed)
terragrunt destroy

# Update all environments
terragrunt run-all apply
```

**Common paths:**

- Shared: `terragrunt/shared`
- QA IaaS: `terragrunt/iaas/qa`
- Prod IaaS: `terragrunt/iaas/prod`
- QA PaaS: `terragrunt/paas/qa`
- Prod PaaS: `terragrunt/paas/prod`
