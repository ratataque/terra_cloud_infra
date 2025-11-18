# Integration Guide: Migrating from Monorepo to Two-Repo Architecture

This guide will help you integrate the existing monorepo into two separate repositories.

## Overview

**Before**: One repository with app code + infrastructure  
**After**: Two repositories with clean separation

```
terra_cloud (app repo)          terra_cloud_infra (infra repo)
├── app/                        ├── terragrunt/
│   ├── Dockerfile              │   ├── modules/
│   └── ...                     │   ├── shared/
└── .github/workflows/          │   ├── iaas/
    └── ci.yml                  │   └── paas/
                                ├── ansible/
                                │   ├── inventories/
                                │   └── playbooks/
                                └── .github/workflows/
                                    ├── terraform-plan.yml
                                    ├── infra-deploy.yml
                                    └── app-deploy.yml
```

## Step-by-Step Integration

### Phase 1: Prepare Infrastructure Repository

#### 1.1 Create GitHub Repository

```bash
# Create new repo on GitHub (via UI or gh CLI)
gh repo create terra_cloud_infra --public --description "Infrastructure as Code for TerraCloud"

# Push the local infra repo
cd /home/ewan/projets/terra_cloud_infra
git remote add origin https://github.com/YOUR_USERNAME/terra_cloud_infra.git
git branch -M main
git push -u origin main
```

#### 1.2 Configure GitHub Environments

In `terra_cloud_infra` repository settings:

**Create Environments:**
1. **qa**: No protection rules (auto-deploy)
2. **prod**: Require 1-2 reviewers

#### 1.3 Setup Repository Secrets

**Repository Secrets** (Settings → Secrets → Actions):
```
AZURE_CLIENT_ID=<from OIDC setup>
AZURE_TENANT_ID=<from OIDC setup>
AZURE_SUBSCRIPTION_ID=<your subscription>
SSH_PRIVATE_KEY=<SSH private key for VM access>
```

**Environment Secrets** (for each: qa, prod):

**QA Environment:**
```
DB_HOST=terracloud-qa-mysql.mysql.database.azure.com
DB_PORT=3306
DB_DATABASE=terracloud_qa
DB_USERNAME=dbadmin
DB_PASSWORD=<password>
APP_KEY=<base64:...>
```

**Prod Environment:**
```
DB_HOST=terracloud-prod-mysql.mysql.database.azure.com
DB_PORT=3306
DB_DATABASE=terracloud_prod
DB_USERNAME=dbadmin
DB_PASSWORD=<password>
APP_KEY=<base64:...>
```

### Phase 2: Update Application Repository

#### 2.1 Remove Infrastructure Files

```bash
cd /home/ewan/projets/terra_cloud

# Backup first (optional)
cp -r terragrunt terragrunt.backup

# Remove terragrunt directory
git rm -r terragrunt
git commit -m "refactor: extract infrastructure to separate repo"
```

#### 2.2 Update App Repository Secrets

**Add to existing secrets:**
```
ACR_NAME=<your-acr-name>  # e.g., terracloudacr
INFRA_REPO_PAT=<GitHub Personal Access Token with repo scope>
```

**Get ACR name from infrastructure:**
```bash
cd /home/ewan/projets/terra_cloud_infra/terragrunt/shared
terragrunt output -raw acr_name
```

**Add Repository Variable:**
```
INFRA_REPO=YOUR_USERNAME/terra_cloud_infra
```

#### 2.3 Test the CI Workflow

The updated `.github/workflows/ci.yml` should:
- Run on push to main
- Calculate semantic version
- Build Docker image
- Push to ACR with tags: `v1.2.3`, `v1.2.3-sha`, `latest`
- Optionally trigger deployment

### Phase 3: Connect the Repositories

#### 3.1 Create GitHub Personal Access Token (PAT)

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token (classic)
3. Name: `TerraCloud Infra Deploy`
4. Scopes: ☑️ `repo` (full control)
5. Copy the token
6. Add to `terra_cloud` repo as secret: `INFRA_REPO_PAT`

#### 3.2 Add Repository Variable

In `terra_cloud` repository:
- Settings → Secrets and variables → Actions → Variables
- New repository variable:
  - Name: `INFRA_REPO`
  - Value: `YOUR_USERNAME/terra_cloud_infra`

### Phase 4: Testing the Integration

#### 4.1 Test Infrastructure Deployment

```bash
# Clone infra repo
git clone https://github.com/YOUR_USERNAME/terra_cloud_infra.git
cd terra_cloud_infra

# Deploy shared infrastructure
cd terragrunt/shared
terragrunt init
terragrunt apply

# Note the ACR name from output
```

#### 4.2 Test Application Build

```bash
cd /home/ewan/projets/terra_cloud

# Make a small change
echo "# Test" >> README.md

# Commit with semantic version trigger
git add .
git commit -m "test: verify CI pipeline (MINOR)"
git push origin main

# Watch GitHub Actions
# Should:
# 1. Run tests
# 2. Build image with version tag
# 3. Push to ACR
# 4. (Optional) Trigger infra repo deployment
```

#### 4.3 Test Manual Deployment

In `terra_cloud_infra` repository:

1. Go to Actions tab
2. Select "Application Deploy" workflow
3. Click "Run workflow"
4. Select:
   - Environment: `qa`
   - Image tag: `1.0.0` (or the version from previous step)
5. Run

Watch the deployment:
- Ansible connects to VM
- Pulls image from ACR
- Deploys container
- Runs health checks
- Runs migrations

### Phase 5: Verify End-to-End Flow

#### Full Release Cycle Test

1. **Make app change:**
   ```bash
   cd /home/ewan/projets/terra_cloud/app
   # Make code change
   git add .
   git commit -m "feat: add new feature (MINOR)"
   git push origin main
   ```

2. **CI builds and pushes:**
   - Watch GitHub Actions in `terra_cloud`
   - Verify image pushed to ACR

3. **Manual deployment to QA:**
   - Go to `terra_cloud_infra` Actions
   - Run "Application Deploy" for QA with new version

4. **Test in QA:**
   - Access QA environment
   - Verify feature works

5. **Promote to Production:**
   - Run "Application Deploy" for prod with same version
   - Requires approval (if configured)

## Architecture Decisions

### Why Two Repositories?

✅ **Separation of Concerns**: App developers don't need to know Terraform  
✅ **Different Release Cycles**: Infrastructure changes less frequently  
✅ **Better Access Control**: Restrict who can change infrastructure  
✅ **Cleaner CI/CD**: Each repo has focused workflows  
✅ **Easier Auditing**: Clear history of infra vs app changes

### Image Promotion Strategy

**Same image, multiple environments:**
```
Build once → QA → Prod
  v1.2.3  → v1.2.3 → v1.2.3 (exact same digest)
```

**Never rebuild between environments** - eliminates "works on my machine" issues.

### Ansible vs Native Deployment

**Ansible chosen for:**
- Complex deployment logic (health checks, rollbacks)
- SSH-based access to VMs
- Flexibility for IaaS deployments
- Can manage multiple VMs/services

**For PaaS (App Service):**
- ACR webhooks handle deployment automatically
- No Ansible needed

## Troubleshooting

### Issue: CI fails to push to ACR

**Symptoms**: Docker login fails or push fails

**Solution**: Verify terragrunt/shared is deployed and accessible:
```bash
cd terragrunt/shared
terragrunt output
```

### Issue: repository_dispatch doesn't trigger deployment

**Symptoms**: App build succeeds but deployment doesn't start

**Check:**
1. `INFRA_REPO_PAT` is set correctly
2. `INFRA_REPO` variable points to correct repo
3. PAT has `repo` scope
4. Workflow is enabled in infra repo

**Manual workaround:**
```bash
gh workflow run app-deploy.yml \
  -R YOUR_USERNAME/terra_cloud_infra \
  -f environment=qa \
  -f image_tag=1.2.3
```

### Issue: Ansible can't connect to VM

**Symptoms**: SSH connection timeout or permission denied

**Solution:**
1. Verify VM is running:
   ```bash
   cd terragrunt/iaas/qa
   terragrunt output vm_public_ip
   ```

2. Test SSH manually:
   ```bash
   ssh -i ~/.ssh/id_rsa azureuser@<VM_IP>
   ```

3. Check NSG allows SSH (port 22) from GitHub Actions IPs

### Issue: Health check fails during deployment

**Symptoms**: Ansible rolls back deployment

**Solution:**
1. Check container logs:
   ```bash
   ssh azureuser@<VM_IP>
   docker logs terracloud-app
   ```

2. Verify app has `/api/health` endpoint

3. Check environment variables are correct

## Migration Checklist

- [ ] Create `terra_cloud_infra` repository on GitHub
- [ ] Push infra code to new repo
- [ ] Configure GitHub Environments (qa, prod)
- [ ] Setup repository secrets (Azure OIDC)
- [ ] Setup environment secrets (DB, APP_KEY)
- [ ] Generate GitHub PAT for cross-repo triggers
- [ ] Add PAT to app repo secrets
- [ ] Add INFRA_REPO variable to app repo
- [ ] Remove terragrunt from app repo
- [ ] Test infra deployment (shared + qa)
- [ ] Test app CI (build + push to ACR)
- [ ] Test manual deployment via Ansible
- [ ] Test full release cycle (dev → qa → prod)
- [ ] Update team documentation
- [ ] Train team on new workflow

## Rollback Plan

If issues arise, you can quickly rollback:

```bash
cd /home/ewan/projets/terra_cloud

# Restore terragrunt directory
git checkout <previous-commit> -- terragrunt

# Restore old CI workflow
git checkout <previous-commit> -- .github/workflows/terraform-cd.yml

git commit -m "Rollback to monorepo architecture"
git push origin main
```

## Next Steps After Integration

1. **Setup Branch Protection**: Require PR reviews for both repos
2. **Configure Dependabot**: Keep dependencies updated
3. **Add Monitoring**: Setup alerts for failed deployments
4. **Document Runbooks**: Create playbooks for common issues
5. **Setup Cost Alerts**: Monitor Azure spending
6. **Create Backup Strategy**: Regular ACR backups, VM snapshots

## Support

- **App Issues**: `terra_cloud` repository
- **Infrastructure Issues**: `terra_cloud_infra` repository
- **Integration Issues**: Create issue in either repo with `integration` label
