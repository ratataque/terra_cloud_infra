# TerraCloud Infrastructure

Infrastructure as Code (Terraform + Terragrunt) and Configuration Management (Ansible) for TerraCloud application on Azure.

## Repository Structure

```
terra_cloud_infra/
├── terragrunt/
│   ├── modules/                    # Terraform modules
│   │   ├── azure-shared-infra/    # ACR, Key Vault, etc.
│   │   ├── azure-iaas-app-service/# VMs, networking
│   │   └── azure-paas-app-service/# App Service plans
│   ├── shared/                     # Shared infrastructure (ACR)
│   │   └── terragrunt.hcl
│   ├── iaas/                       # IaaS environments
│   │   ├── qa/terragrunt.hcl
│   │   └── prod/terragrunt.hcl
│   ├── paas/                       # PaaS environments
│   │   ├── qa/terragrunt.hcl
│   │   └── prod/terragrunt.hcl
│   └── root.hcl                    # Root configuration
├── ansible/
│   ├── inventories/                # Environment inventories
│   │   ├── qa.yml
│   │   └── prod.yml
│   ├── playbooks/
│   │   └── deploy.yml              # Application deployment
│   └── ansible.cfg
└── .github/workflows/
    ├── terraform-plan.yml          # PR plans
    ├── infra-deploy.yml            # Infrastructure deployment
    └── app-deploy.yml              # Application deployment
```

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Shared Resources                     │
│  ┌────────────────────────────────────────────────┐    │
│  │  Azure Container Registry (ACR)                 │    │
│  │  - Stores all Docker images                     │    │
│  │  - Shared across all environments               │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘

┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│   QA (IaaS)      │  │  QA (PaaS)       │  │  Prod (IaaS)     │
│  ┌────────────┐  │  │  ┌────────────┐  │  │  ┌────────────┐  │
│  │    VM      │  │  │  │ App Service│  │  │  │    VM      │  │
│  │  + Docker  │  │  │  │  (Docker)  │  │  │  │  + Docker  │  │
│  └────────────┘  │  │  └────────────┘  │  │  └────────────┘  │
│  ┌────────────┐  │  │  ┌────────────┐  │  │  ┌────────────┐  │
│  │   MySQL    │  │  │  │   MySQL    │  │  │  │   MySQL    │  │
│  └────────────┘  │  │  └────────────┘  │  │  └────────────┘  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

## Workflows

### 1. Infrastructure Plan (PR)

**Trigger**: Pull request to `main` with terragrunt changes

**Workflow**: `terraform-plan.yml`

- Runs `terragrunt plan` for affected environments
- Posts plan as PR comment for review
- No changes applied

### 2. Infrastructure Deploy (Merge)

**Trigger**: Push to `main` with terragrunt changes

**Workflow**: `infra-deploy.yml`

**Flow**:
1. Deploy shared infrastructure (ACR)
2. Deploy QA environment
3. Deploy Stage/PaaS environment (requires approval)
4. Deploy Production (requires approval)

### 3. Application Deploy

**Trigger**: Manual or repository_dispatch from app repo

**Workflow**: `app-deploy.yml`

**Flow**:
1. Get infrastructure outputs (VM IP, ACR name)
2. Run Ansible playbook
3. Pull Docker image from ACR
4. Stop old container
5. Start new container
6. Run health checks
7. Run database migrations
8. Rollback on failure

## Setup Guide

### Prerequisites

- Azure CLI installed and authenticated
- Terraform 1.5.7+
- Terragrunt 0.54.0+
- Ansible 2.9+

### 1. Azure Authentication (OIDC)

Create Service Principal for GitHub Actions:

```bash
SUBSCRIPTION_ID="your-sub-id"
GITHUB_ORG="your-username"
GITHUB_REPO="terra_cloud_infra"

# Create app
APP_ID=$(az ad app create --display-name "TerraCloud-Infra-OIDC" --query appId -o tsv)
az ad sp create --id $APP_ID
SP_ID=$(az ad sp list --display-name "TerraCloud-Infra-OIDC" --query "[0].id" -o tsv)

# Grant Contributor role
az role assignment create --assignee $SP_ID --role Contributor \
  --scope "/subscriptions/$SUBSCRIPTION_ID"

# Setup OIDC federation
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "GitHub-Main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:'$GITHUB_ORG'/'$GITHUB_REPO':ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'

TENANT_ID=$(az account show --query tenantId -o tsv)
echo "AZURE_CLIENT_ID: $APP_ID"
echo "AZURE_TENANT_ID: $TENANT_ID"
echo "AZURE_SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
```

### 2. Setup GitHub Environments

Create three environments with protection rules:

#### QA Environment
- **Name**: `qa`
- **Protection**: None (auto-deploy)

#### Stage Environment  
- **Name**: `stage`
- **Protection**: Required reviewers (1+)

#### Prod Environment
- **Name**: `prod`
- **Protection**: Required reviewers (2+)

### 3. Configure GitHub Secrets

**Repository Secrets** (all environments):
```
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
SSH_PRIVATE_KEY          # For Ansible SSH access
```

**Environment Secrets** (per environment: qa, prod):
```
DB_HOST                  # MySQL server hostname
DB_PORT                  # 3306
DB_DATABASE              # Database name
DB_USERNAME              # Database username
DB_PASSWORD              # Database password
APP_KEY                  # Laravel app key (base64:...)
```

### 4. Initial Deployment

#### Deploy Shared Infrastructure

```bash
cd terragrunt/shared
terragrunt init
terragrunt plan
terragrunt apply
```

#### Deploy QA Environment

```bash
cd terragrunt/iaas/qa
terragrunt init
terragrunt apply
```

#### Deploy Production

```bash
cd terragrunt/iaas/prod
terragrunt init
terragrunt apply
```

## Application Deployment with Ansible

### Manual Deployment

```bash
cd ansible

# Set environment variables
export QA_VM_IP="x.x.x.x"
export ACR_NAME="youracrname"
export IMAGE_TAG="1.2.3"
export SSH_KEY_PATH="~/.ssh/id_rsa"
export AZURE_CLIENT_ID="..."
export AZURE_TENANT_ID="..."
export AZURE_SUBSCRIPTION_ID="..."
export DB_HOST="..."
export DB_DATABASE="..."
export DB_USERNAME="..."
export DB_PASSWORD="..."
export APP_KEY="base64:..."

# Deploy to QA
ansible-playbook -i inventories/qa.yml playbooks/deploy.yml

# Deploy to Production
ansible-playbook -i inventories/prod.yml playbooks/deploy.yml
```

### Automated Deployment (GitHub Actions)

Trigger from app repository or manually:

```bash
# Via GitHub UI
Actions → Application Deploy → Run workflow
  Environment: qa
  Image tag: 1.2.3

# Via gh CLI
gh workflow run app-deploy.yml -f environment=qa -f image_tag=1.2.3
```

## Ansible Playbook Features

The `deploy.yml` playbook:

✅ Ensures Docker is installed  
✅ Logs in to ACR  
✅ Pulls specified image version  
✅ Stops old container  
✅ Starts new container  
✅ Waits for health check (10 retries)  
✅ Runs database migrations  
❌ Rolls back to previous version on failure

## Terraform State Backend

State is stored in Azure Storage Account:

```hcl
remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = "terracloud-tfstate-rg"
    storage_account_name = "terracloudtfstate"
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
  }
}
```

## Cloud-Init Strategy

**Minimal bootstrap only**:
- Create admin user
- Install base packages (Docker, Azure CLI)
- Configure SSH keys
- Enable Docker service

**All ongoing configuration via Ansible**:
- Application deployments
- Container updates
- Environment variables
- Service management

## End-to-End Release Flow

```
1. Developer pushes to app repo
   ↓
2. CI: Build image → Tag v1.2.3 → Push to ACR
   ↓
3. CI: Trigger infra repo deployment (optional)
   ↓
4. Ansible: Deploy v1.2.3 to QA VM
   ↓
5. QA validation & approval
   ↓
6. Ansible: Promote v1.2.3 to Prod VM
   ↓
7. Same tested image running in production ✅
```

## Monitoring & Troubleshooting

### Check Infrastructure Outputs

```bash
cd terragrunt/iaas/qa
terragrunt output

# Get specific output
terragrunt output -raw vm_public_ip
```

### Check Ansible Deployment

```bash
# Test connectivity
ansible -i inventories/qa.yml all -m ping

# Check container status
ansible -i inventories/qa.yml all -a "docker ps"

# View container logs
ansible -i inventories/qa.yml all -a "docker logs terracloud-app"
```

### Access VM

```bash
# Get VM IP
VM_IP=$(cd terragrunt/iaas/qa && terragrunt output -raw vm_public_ip)

# SSH to VM
ssh -i ~/.ssh/id_rsa azureuser@$VM_IP

# Check running containers
docker ps

# View logs
docker logs terracloud-app -f
```

## Cost Optimization

- **Stop VMs**: When not in use (QA after hours)
- **Scale down**: Use smaller VM sizes for QA
- **Shared ACR**: Single ACR for all environments
- **MySQL**: Stop flexible server when unused

## Updating Infrastructure

```bash
# 1. Create feature branch
git checkout -b feature/add-key-vault

# 2. Modify Terraform modules
vim terragrunt/modules/azure-shared-infra/main.tf

# 3. Push and create PR
git push origin feature/add-key-vault

# 4. Review plan in PR comments

# 5. Merge to apply changes
```

## Security Best Practices

✅ Use OIDC authentication (no long-lived secrets)  
✅ Managed identities for Azure resources  
✅ Secrets in GitHub Environments  
✅ SSH key-based authentication  
✅ Network security groups on VMs  
✅ Private endpoints for databases  
✅ ACR admin disabled, use RBAC  

## Related Repositories

- **Application Code**: [terra_cloud](../terra_cloud)

## Support

For application issues, see the terra_cloud repository.
