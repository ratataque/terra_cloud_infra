# Deployment Guide

Complete guide for deploying the TerraCloud application to Azure infrastructure.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Deployment Methods](#deployment-methods)
- [Manual Deployment](#manual-deployment)
- [Automated Deployment](#automated-deployment)
- [Environment Promotion](#environment-promotion)
- [Rollback Procedures](#rollback-procedures)
- [Post-Deployment Verification](#post-deployment-verification)

---

## Overview

The TerraCloud application can be deployed using two methods:

1. **Manual deployment** - Using Ansible playbooks directly
2. **Automated deployment** - Using GitHub Actions workflows

Both methods deploy the same Docker container from Azure Container Registry (ACR) to VMs.

### Deployment Flow

```
1. Application built and pushed to ACR
   ↓
2. Infrastructure provisioned (if needed)
   ↓
3. Application deployment triggered
   ↓
4. Ansible connects to VMs
   ↓
5. Pull image from ACR
   ↓
6. Stop old container
   ↓
7. Start new container
   ↓
8. Health checks (10 retries)
   ↓
9. Run database migrations
   ↓
10. Deployment complete ✅
```

---

## Prerequisites

### For Manual Deployment

**Required tools**:
```bash
# Ansible
pip3 install ansible

# Ansible Docker collection
ansible-galaxy collection install community.docker

# Azure CLI (for ACR authentication)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

**Required access**:
- SSH access to target VMs
- Azure subscription access (for ACR)
- Database credentials

### For Automated Deployment

**Required setup**:
- GitHub Actions workflows configured
- GitHub Environments created (qa, prod)
- GitHub secrets configured
- Infrastructure already deployed

See [SETUP.md](SETUP.md) for complete setup instructions.

---

## Deployment Methods

### Method Comparison

| Feature | Manual Deployment | Automated Deployment |
|---------|-------------------|---------------------|
| **Trigger** | Command line | GitHub Actions UI or dispatch |
| **Authentication** | Local SSH key | GitHub secrets |
| **Environment vars** | Local export | GitHub Environment secrets |
| **Audit trail** | Terminal logs | GitHub Actions logs (permanent) |
| **Approval workflow** | Manual confirmation | GitHub Environment protection |
| **Best for** | Testing, debugging | Production releases |

---

## Manual Deployment

### Step 1: Prepare Environment Variables

```bash
# Set deployment environment
export ENV_NAME="qa"  # or "prod"

# Set image tag to deploy
export IMAGE_TAG="1.2.3"  # Use semantic version from app repo

# Get infrastructure outputs
cd terragrunt/iaas/$ENV_NAME
export VM_IP=$(terragrunt output -raw vm_public_ip)
export ACR_NAME=$(cd ../../shared && terragrunt output -raw acr_name)
export DB_HOST=$(terragrunt output -raw database_host)
export DB_NAME=$(terragrunt output -raw database_name)
export DB_USERNAME=$(terragrunt output -raw database_admin_username)

# Set database password (from secure storage)
export DB_PASSWORD="your-db-password"
export DB_PORT="3306"

# Set application key (from secure storage)
export APP_KEY="base64:your-app-key"

# Set ACR credentials
export ACR_USERNAME=$(az acr credential show --name $ACR_NAME --query username -o tsv)
export ACR_PASSWORD=$(az acr credential show --name $ACR_NAME --query passwords[0].value -o tsv)

# SSH configuration
export SSH_KEY_PATH="~/.ssh/terracloud_deploy"
export ANSIBLE_HOST_KEY_CHECKING=False
```

### Step 2: Verify Inventory

Check that the inventory file exists and has correct values:

```bash
cd ansible

# View inventory
cat inventories/$ENV_NAME.yml
```

Expected content:
```yaml
all:
  children:
    app_servers:
      hosts:
        vm-1:
          ansible_host: <VM_PUBLIC_IP>
      vars:
        ansible_user: azureuser
        ansible_ssh_private_key_file: ~/.ssh/terracloud_deploy
        env_name: qa
        acr_name: terracloudacr
        app_image_tag: "1.2.3"
```

### Step 3: Test Connectivity

```bash
# Test SSH connectivity
ansible -i inventories/$ENV_NAME.yml all -m ping

# Expected output:
# vm-1 | SUCCESS => {
#     "changed": false,
#     "ping": "pong"
# }
```

### Step 4: Run Deployment Playbook

```bash
# Dry run (check mode)
ansible-playbook \
  -i inventories/$ENV_NAME.yml \
  playbooks/deploy.yml \
  --check \
  -v

# Actual deployment
ansible-playbook \
  -i inventories/$ENV_NAME.yml \
  playbooks/deploy.yml \
  -v

# Watch deployment progress
# You'll see:
# - Image pull
# - Container stop/start
# - Health checks (with retries)
# - Database migrations
```

### Step 5: Verify Deployment

```bash
# Check container status
ansible -i inventories/$ENV_NAME.yml all -a "docker ps"

# Check application logs
ansible -i inventories/$ENV_NAME.yml all -a "docker logs app --tail 50"

# Test application endpoint
curl http://$VM_IP/health
```

### Manual Deployment Options

**Deploy with extra verbosity**:
```bash
ansible-playbook -i inventories/qa.yml playbooks/deploy.yml -vvv
```

**Deploy to specific host**:
```bash
ansible-playbook -i inventories/qa.yml playbooks/deploy.yml --limit vm-1
```

**Skip health checks** (for debugging):
```bash
ansible-playbook -i inventories/qa.yml playbooks/deploy.yml --skip-tags health_check
```

**Force redeployment** (even if same tag):
```bash
ansible-playbook -i inventories/qa.yml playbooks/deploy.yml -e force_deploy=true
```

---

## Automated Deployment

### Via GitHub Actions UI

**Step 1: Navigate to Actions**
- Go to repository: https://github.com/ratataque/terracloud-infra
- Click "Actions" tab
- Select "Application Deploy" workflow

**Step 2: Run Workflow**
- Click "Run workflow" button
- Select branch: `main`
- Choose environment: `qa` or `prod`
- Enter image tag: e.g., `1.2.3`
- Click "Run workflow"

**Step 3: Monitor Progress**
- Workflow starts immediately
- Click on the running workflow to see live logs
- For production: approval required before deployment

**Step 4: Approve Production Deployment**
- Designated reviewer(s) receive notification
- Review deployment details
- Click "Review deployments"
- Approve or reject

### Via GitHub CLI

**Deploy to QA**:
```bash
gh workflow run app-deploy.yml \
  -f environment=qa \
  -f image_tag=1.2.3

# Watch progress
gh run watch
```

**Deploy to Production**:
```bash
gh workflow run app-deploy.yml \
  -f environment=prod \
  -f image_tag=1.2.3

# Workflow will wait for approval
# Approve via UI or CLI
gh run list --workflow=app-deploy.yml
gh run view <run-id>
```

**Check deployment status**:
```bash
# List recent runs
gh run list --workflow=app-deploy.yml --limit 5

# View specific run
gh run view <run-id>

# View logs
gh run view <run-id> --log

# Download logs
gh run download <run-id>
```

### Via Repository Dispatch

**Triggered automatically from application repository** after successful build.

**Trigger from command line** (for testing):
```bash
# Get GitHub token
export GITHUB_TOKEN="ghp_your_token"

# Trigger deployment
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/ratataque/terracloud-infra/dispatches \
  -d '{
    "event_type": "deploy-app",
    "client_payload": {
      "environment": "qa",
      "image_tag": "1.2.3"
    }
  }'
```

**Verify dispatch received**:
```bash
# Check recent workflow runs
gh run list --workflow=app-deploy.yml --limit 1
```

---

## Environment Promotion

### QA to Production Promotion

**Best practice**: Promote the **exact same Docker image** from QA to Production.

**Step-by-step**:

**1. Deploy to QA**:
```bash
# Build version 1.2.3 in app repo
# Automatically deployed to QA
```

**2. Test in QA**:
```bash
# Manual testing
# Automated tests
# Smoke tests
```

**3. Promote to Production**:
```bash
# Deploy SAME image tag to production
gh workflow run app-deploy.yml \
  -f environment=prod \
  -f image_tag=1.2.3  # Same tag as QA
```

**4. Verify Production**:
```bash
# Smoke tests
curl https://terracloud.com/health

# Check logs
ssh azureuser@<PROD_VM_IP>
docker logs app --tail 100
```

### Blue-Green Deployment (Future)

For zero-downtime deployments:

**1. Deploy to "green" VM**:
```bash
# Deploy new version to standby VM
ansible-playbook -i inventories/prod-green.yml playbooks/deploy.yml
```

**2. Test green environment**:
```bash
# Verify green VM works
curl http://<GREEN_VM_IP>/health
```

**3. Switch traffic** (via Load Balancer or DNS):
```bash
# Update load balancer backend pool
# Or update DNS to point to green VM
```

**4. Keep blue as rollback**:
```bash
# Blue VM kept running for quick rollback
```

---

## Rollback Procedures

### Automatic Rollback

Ansible playbook includes automatic rollback if deployment fails.

**Rollback triggers**:
- Health check fails after 10 retries
- Container fails to start
- Database migration fails

**Rollback process**:
```
1. Health check fails
   ↓
2. Stop new container
   ↓
3. Start previous container (if exists)
   ↓
4. Verify previous container healthy
   ↓
5. Rollback complete
```

**Check rollback in logs**:
```
TASK [Rollback: Start previous container] ****
ok: [vm-1]

TASK [Wait for application to be healthy (rollback)] ****
ok: [vm-1]
```

### Manual Rollback

**Rollback to previous version**:

**Option 1: Redeploy previous image tag**:
```bash
# Find previous working version
# From git tags or ACR tags

# Redeploy
gh workflow run app-deploy.yml \
  -f environment=prod \
  -f image_tag=1.2.2  # Previous version
```

**Option 2: Rollback via Ansible**:
```bash
# SSH to VM
ssh azureuser@<VM_IP>

# List images
docker images

# Stop current container
docker stop app
docker rm app

# Start previous image
docker run -d \
  --name app \
  --network app_app-net \
  -e APP_ENV=production \
  -e DB_HOST=<DB_HOST> \
  # ... other env vars
  <ACR_NAME>.azurecr.io/app:1.2.2

# Verify
docker ps
docker logs app
```

**Option 3: Restore from backup** (database):
```bash
# If database migration caused issues
az mysql flexible-server restore \
  --resource-group terracloud-prod-rg \
  --name terracloud-prod-mysql-restored \
  --source-server terracloud-prod-mysql \
  --restore-time "2024-01-01T00:00:00Z"

# Update app to use restored database
```

### Database Rollback

**If migration fails**:

**1. Restore database backup**:
```bash
# Point-in-time restore (Azure MySQL)
az mysql flexible-server restore \
  --resource-group terracloud-prod-rg \
  --name terracloud-prod-mysql-restored \
  --source-server terracloud-prod-mysql \
  --restore-time "<TIMESTAMP_BEFORE_MIGRATION>"
```

**2. Update database connection**:
```bash
# Update environment variable to point to restored DB
# Redeploy application
```

**3. Fix migration** (for next deployment):
```bash
# Fix migration in app repo
# Deploy new version with corrected migration
```

---

## Post-Deployment Verification

### Application Health Checks

**1. Container status**:
```bash
# Via Ansible
ansible -i inventories/prod.yml all -a "docker ps"

# Via SSH
ssh azureuser@<VM_IP> "docker ps"

# Expected: Container "app" with status "Up"
```

**2. Application endpoint**:
```bash
# Health check endpoint
curl http://<VM_IP>/health

# Expected: HTTP 200 OK
# Response: {"status":"ok","timestamp":"2024-01-01T00:00:00Z"}
```

**3. Application logs**:
```bash
# Last 100 lines
docker logs app --tail 100

# Follow logs
docker logs app -f

# Check for errors
docker logs app 2>&1 | grep -i error
```

### Database Connectivity

**Test database connection**:
```bash
# From VM
ssh azureuser@<VM_IP>

# Test connection
docker exec app php artisan tinker
# In tinker:
DB::connection()->getPdo();
// Should return PDO instance
```

**Check migration status**:
```bash
docker exec app php artisan migrate:status
```

### Performance Verification

**Response time**:
```bash
# Test response time
time curl http://<VM_IP>/

# Expected: < 200ms for cached responses
```

**Memory usage**:
```bash
# Container memory
docker stats app --no-stream

# VM memory
ssh azureuser@<VM_IP> "free -h"
```

**Database queries**:
```bash
# Slow query log (if enabled)
# Check MySQL slow query log for performance issues
```

### Smoke Tests

**Run automated smoke tests**:
```bash
# Example smoke test script
#!/bin/bash
BASE_URL="http://<VM_IP>"

# Test homepage
curl -f $BASE_URL/ || exit 1

# Test health endpoint
curl -f $BASE_URL/health || exit 1

# Test API endpoint
curl -f $BASE_URL/api/users || exit 1

echo "✅ All smoke tests passed"
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] Infrastructure deployed and healthy
- [ ] Database backups verified
- [ ] Image built and pushed to ACR
- [ ] Image tag identified (e.g., 1.2.3)
- [ ] Environment secrets up to date
- [ ] Deployment window communicated (for prod)

### During Deployment

- [ ] Deployment triggered (manual or automated)
- [ ] Monitor deployment logs
- [ ] Health checks passing
- [ ] Database migrations successful
- [ ] No errors in application logs

### Post-Deployment

- [ ] Application responding to requests
- [ ] Database connectivity verified
- [ ] Smoke tests passing
- [ ] Performance metrics acceptable
- [ ] Rollback plan ready (if issues arise)
- [ ] Team notified of successful deployment

---

## Deployment Best Practices

### 1. Always Use Semantic Versioning

```bash
# Good
image_tag: "1.2.3"

# Bad
image_tag: "latest"  # Not immutable
```

### 2. Deploy During Low Traffic

- **QA**: Anytime
- **Production**: Outside peak hours

### 3. Test in QA First

```bash
# Always deploy to QA before production
gh workflow run app-deploy.yml -f environment=qa -f image_tag=1.2.3

# Test thoroughly

# Then deploy to production with SAME tag
gh workflow run app-deploy.yml -f environment=prod -f image_tag=1.2.3
```

### 4. Monitor After Deployment

- Watch application logs for 10-15 minutes
- Check error rates in monitoring tools
- Verify key user flows work

### 5. Have Rollback Plan Ready

- Document previous working version
- Have rollback command ready
- Know database restore procedure

---

## Deployment Scenarios

### Scenario 1: Feature Deployment

**Goal**: Deploy new feature to production

**Steps**:
1. Deploy to QA: `image_tag=1.3.0`
2. Test feature in QA
3. Get approval from product team
4. Deploy to prod: `image_tag=1.3.0`
5. Verify feature in production
6. Monitor for 1 hour

### Scenario 2: Hotfix Deployment

**Goal**: Fix critical bug in production

**Steps**:
1. Build hotfix in app repo: `image_tag=1.2.4`
2. Minimal testing in QA (if time permits)
3. Deploy directly to prod: `image_tag=1.2.4`
4. Verify fix immediately
5. Monitor closely

### Scenario 3: Database Migration

**Goal**: Deploy version with database schema changes

**Steps**:
1. Backup database before deployment
2. Deploy to QA with migration
3. Verify migration succeeded
4. Test application with new schema
5. Deploy to prod (migration runs automatically)
6. Verify migration succeeded
7. **Do not rollback image** if migration succeeded (can cause schema mismatch)

### Scenario 4: Rollback Deployment

**Goal**: Revert to previous version due to issues

**Steps**:
1. Identify previous working version: `1.2.2`
2. Trigger deployment: `image_tag=1.2.2`
3. **Warning**: Check if database migrations are compatible
4. If migration incompatible, restore database backup
5. Verify rollback successful

---

## Next Steps

- **Ansible details**: See [ANSIBLE.md](ANSIBLE.md)
- **Architecture**: See [ARCHITECTURE.md](ARCHITECTURE.md)
