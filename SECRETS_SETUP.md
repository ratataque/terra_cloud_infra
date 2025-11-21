# GitHub Secrets Configuration Guide

Complete guide to configure all secrets needed for both repositories.

---

## 📦 App Repository (`terra_cloud`)

### Repository Secrets

#### 1. `AZURE_CLIENT_ID`
**What**: Service Principal Application (Client) ID for Azure authentication

**How to get**:
```bash
# Using your existing service principal
az ad sp list --display-name "terracloud-cd-deployer" --query "[0].appId" -o tsv

# Or get from app registration
az ad app list --display-name "terracloud-cd-deployer" --query "[0].appId" -o tsv
```

#### 2. `AZURE_TENANT_ID`
**What**: Your Azure Active Directory Tenant ID

**How to get**:
```bash
az account show --query tenantId -o tsv
```

#### 3. `AZURE_SUBSCRIPTION_ID`
**What**: Your Azure Subscription ID

**How to get**:
```bash
az account show --query id -o tsv
```

#### 4. `ACR_NAME`
**What**: Azure Container Registry name (without .azurecr.io)

**How to get**:
```bash
# If ACR already exists
cd /home/ewan/projets/terra_cloud_infra/terragrunt/shared
terragrunt output -raw acr_name

# Or check in Azure Portal
az acr list --query "[].name" -o tsv

# Example value: terracloudacr
```

#### 5. `INFRA_REPO_PAT` (Optional - for automatic QA deployment)
**What**: GitHub Personal Access Token to trigger infra repo workflows

**How to get**:
1. Go to GitHub → Settings (your profile) → Developer settings
2. Personal access tokens → Tokens (classic)
3. Generate new token (classic)
4. Name: `TerraCloud Deploy`
5. Expiration: 90 days or No expiration (your choice)
6. Scopes: ☑️ **repo** (Full control of private repositories)
7. Generate token
8. **Copy the token immediately** (can't see it again!)

### Repository Variables

#### `INFRA_REPO` (Optional - for automatic QA deployment)
**What**: Path to infrastructure repository

**Value**: `YOUR_GITHUB_USERNAME/terra_cloud_infra`

**Example**: `ewanbrilliant/terra_cloud_infra`

---

## 🏗️ Infrastructure Repository (`terra_cloud_infra`)

### Repository Secrets

#### 1. `AZURE_CLIENT_ID`
**Same as app repo** - Service Principal ID

#### 2. `AZURE_TENANT_ID`
**Same as app repo** - Azure Tenant ID

#### 3. `AZURE_SUBSCRIPTION_ID`
**Same as app repo** - Azure Subscription ID

#### 4. `SSH_PRIVATE_KEY`
**What**: Private SSH key for Ansible to connect to VMs (used by app-deploy workflow)

**How to get**:

**Option A: Use existing key**
```bash
cat ~/.ssh/id_rsa
# Copy the entire output including:
# -----BEGIN OPENSSH PRIVATE KEY-----
# ...
# -----END OPENSSH PRIVATE KEY-----
```

**Option B: Create new key for deployment**
```bash
# Generate new key pair
ssh-keygen -t rsa -b 4096 -C "github-actions-deploy" -f ~/.ssh/github_deploy_key -N ""

# Display private key (for GitHub secret SSH_PRIVATE_KEY)
cat ~/.ssh/github_deploy_key

# Display public key (for GitHub secret SSH_PUBLIC_KEY)
cat ~/.ssh/github_deploy_key.pub
```

**Note**: You need BOTH the private and public keys as separate secrets.

#### 5. `SSH_PUBLIC_KEY`
**What**: Public SSH key to provision on VMs during Terraform deployment (used by infra-deploy workflow)

**How to get**:
```bash
# If you used Option A above
cat ~/.ssh/id_rsa.pub

# If you used Option B above
cat ~/.ssh/github_deploy_key.pub
```

**Format**: Should start with `ssh-rsa` or `ssh-ed25519` followed by the key data.

**Example**: `ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQ... github-actions-deploy`

---

### Environment Secrets (QA)

Navigate to: Settings → Environments → qa → Add secret

#### 1. `DB_HOST`
**What**: MySQL server hostname

**How to get**:
```bash
cd /home/ewan/projets/terra_cloud_infra/terragrunt/iaas/qa
terragrunt output -raw mysql_fqdn

# Or from Azure
az mysql flexible-server list --query "[?contains(name,'qa')].fullyQualifiedDomainName" -o tsv
```

**Example**: `terracloud-qa-mysql.mysql.database.azure.com`

#### 2. `DB_PORT`
**What**: MySQL port (usually 3306)

**Value**: `3306`

#### 3. `DB_DATABASE`
**What**: Database name

**How to get**:
```bash
cd /home/ewan/projets/terra_cloud_infra/terragrunt/iaas/qa
terragrunt output -raw database_name
```

**Example**: `terracloud_qa`

#### 4. `DB_USERNAME`
**What**: MySQL admin username

**How to get**:
```bash
cd /home/ewan/projets/terra_cloud_infra/terragrunt/iaas/qa
terragrunt output -raw mysql_admin_username
```

**Example**: `dbadmin`

#### 5. `DB_PASSWORD`
**What**: MySQL admin password

**How to get**: 
- This was set when you created the MySQL server
- Check your notes or password manager
- Or reset it:
```bash
az mysql flexible-server update \
  --resource-group terracloud-qa-rg \
  --name terracloud-qa-mysql \
  --admin-password "YourNewSecurePassword123!"
```

#### 6. `APP_KEY`
**What**: Laravel application encryption key

**How to get**:
```bash
cd /home/ewan/projets/terra_cloud/app
php artisan key:generate --show
```

**Output example**: `base64:abcd1234efgh5678ijkl...`

---

### Environment Secrets (Prod)

Navigate to: Settings → Environments → prod → Add secret

**Same secrets as QA, but with production values:**

#### 1. `DB_HOST`
```bash
cd /home/ewan/projets/terra_cloud_infra/terragrunt/iaas/prod
terragrunt output -raw mysql_fqdn
```

#### 2. `DB_PORT`
**Value**: `3306`

#### 3. `DB_DATABASE`
```bash
cd /home/ewan/projets/terra_cloud_infra/terragrunt/iaas/prod
terragrunt output -raw database_name
```

#### 4. `DB_USERNAME`
```bash
cd /home/ewan/projets/terra_cloud_infra/terragrunt/iaas/prod
terragrunt output -raw mysql_admin_username
```

#### 5. `DB_PASSWORD`
**Production MySQL password**

#### 6. `APP_KEY`
```bash
# Generate a separate key for production
cd /home/ewan/projets/terra_cloud/app
php artisan key:generate --show
```

**⚠️ Important**: Use a **different** APP_KEY for production than QA!

---

## 🔐 Complete Setup Checklist

### Prerequisites
```bash
# 1. Login to Azure
az login

# 2. Set correct subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# 3. Ensure infrastructure is deployed
cd /home/ewan/projets/terra_cloud_infra/terragrunt/shared
terragrunt apply

cd ../iaas/qa
terragrunt apply
```

### App Repo (`terra_cloud`) - 5 Secrets + 1 Variable

**Settings → Secrets and variables → Actions → Secrets → New repository secret**

- [ ] `AZURE_CLIENT_ID` = `...`
- [ ] `AZURE_TENANT_ID` = `...`
- [ ] `AZURE_SUBSCRIPTION_ID` = `...`
- [ ] `ACR_NAME` = `terracloudacr`
- [ ] `INFRA_REPO_PAT` = `ghp_...` (optional)

**Settings → Secrets and variables → Actions → Variables → New repository variable**

- [ ] `INFRA_REPO` = `username/terra_cloud_infra` (optional)

### Infra Repo (`terra_cloud_infra`) - 4 Repository + 12 Environment Secrets

**Settings → Secrets and variables → Actions → Secrets → New repository secret**

- [ ] `AZURE_CLIENT_ID` = `...`
- [ ] `AZURE_TENANT_ID` = `...`
- [ ] `AZURE_SUBSCRIPTION_ID` = `...`
- [ ] `SSH_PRIVATE_KEY` = `-----BEGIN OPENSSH PRIVATE KEY-----...`
- [ ] `SSH_PUBLIC_KEY` = `ssh-rsa AAAAB3NzaC1yc2E...`

**Settings → Environments**

Create environments:
- [ ] `qa` (no protection rules)
- [ ] `prod` (required reviewers: 1-2 people)

**Settings → Environments → qa → Add environment secret**

- [ ] `DB_HOST` = `terracloud-qa-mysql.mysql.database.azure.com`
- [ ] `DB_PORT` = `3306`
- [ ] `DB_DATABASE` = `terracloud_qa`
- [ ] `DB_USERNAME` = `dbadmin`
- [ ] `DB_PASSWORD` = `...`
- [ ] `APP_KEY` = `base64:...`

**Settings → Environments → prod → Add environment secret**

- [ ] `DB_HOST` = `terracloud-prod-mysql.mysql.database.azure.com`
- [ ] `DB_PORT` = `3306`
- [ ] `DB_DATABASE` = `terracloud_prod`
- [ ] `DB_USERNAME` = `dbadmin`
- [ ] `DB_PASSWORD` = `...`
- [ ] `APP_KEY` = `base64:...` (different from QA!)

---

## 🔍 Verification

### Test App Repo Secrets
```bash
# In GitHub Actions workflow run, check if secrets are set
# Look for error messages about missing secrets
```

### Test Infra Repo Secrets
```bash
# Run a manual workflow
# Actions → Application Deploy → Run workflow
# If secrets are missing, it will fail with clear error messages
```

### Quick Test Script

Create a test workflow to verify secrets (optional):

```yaml
# .github/workflows/test-secrets.yml
name: Test Secrets
on: workflow_dispatch

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Check Repository Secrets
        run: |
          echo "✅ AZURE_CLIENT_ID: ${AZURE_CLIENT_ID:0:8}..."
          echo "✅ AZURE_TENANT_ID: ${AZURE_TENANT_ID:0:8}..."
          echo "✅ ACR_NAME: $ACR_NAME"
        env:
          AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          ACR_NAME: ${{ secrets.ACR_NAME }}
```

---

## 📝 Summary Table

| Secret | App Repo | Infra Repo | QA Env | Prod Env | How to Get |
|--------|----------|------------|--------|----------|------------|
| `AZURE_CLIENT_ID` | ✅ | ✅ | ❌ | ❌ | `az ad sp list` |
| `AZURE_TENANT_ID` | ✅ | ✅ | ❌ | ❌ | `az account show` |
| `AZURE_SUBSCRIPTION_ID` | ✅ | ✅ | ❌ | ❌ | `az account show` |
| `ACR_NAME` | ✅ | ❌ | ❌ | ❌ | `terragrunt output` |
| `INFRA_REPO_PAT` | ✅* | ❌ | ❌ | ❌ | GitHub PAT |
| `SSH_PRIVATE_KEY` | ❌ | ✅ | ❌ | ❌ | `cat ~/.ssh/id_rsa` |
| `SSH_PUBLIC_KEY` | ❌ | ✅ | ❌ | ❌ | `cat ~/.ssh/id_rsa.pub` |
| `DB_HOST` | ❌ | ❌ | ✅ | ✅ | `terragrunt output` |
| `DB_PORT` | ❌ | ❌ | ✅ | ✅ | `3306` |
| `DB_DATABASE` | ❌ | ❌ | ✅ | ✅ | `terragrunt output` |
| `DB_USERNAME` | ❌ | ❌ | ✅ | ✅ | `terragrunt output` |
| `DB_PASSWORD` | ❌ | ❌ | ✅ | ✅ | Your password |
| `APP_KEY` | ❌ | ❌ | ✅ | ✅ | `php artisan key:generate` |

**\*** Optional - only needed for automatic QA deployment

---

## 🆘 Troubleshooting

### "Secret not found" error
- Check spelling (case-sensitive)
- Verify secret is in correct location (repository vs environment)
- Re-add the secret if needed

### "Invalid credentials" for Azure
- Verify OIDC federation is set up correctly
- Check service principal has Contributor role
- Ensure subscription ID is correct

### "Cannot connect to MySQL"
- Verify MySQL server is running
- Check firewall rules allow GitHub Actions IPs
- Test connection manually from VM

### "Invalid APP_KEY"
- Must start with `base64:`
- Generate new one: `php artisan key:generate --show`
- Copy full value including `base64:` prefix

---

All secrets documented! Follow the checklist above to configure everything. 🎉
