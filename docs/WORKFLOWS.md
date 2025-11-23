# CI/CD Workflows

Detailed documentation of GitHub Actions workflows for infrastructure and application deployment.

## Table of Contents

- [Overview](#overview)
- [Workflow: Terraform Plan](#workflow-terraform-plan)
- [Workflow: Infrastructure Deploy](#workflow-infrastructure-deploy)
- [Workflow: Application Deploy](#workflow-application-deploy)
- [Cross-Repository Integration](#cross-repository-integration)
- [Workflow Customization](#workflow-customization)

---

## Overview

The TerraCloud infrastructure uses **three GitHub Actions workflows**:

| Workflow | File | Trigger | Purpose |
|----------|------|---------|---------|
| **Terraform Plan** | `terraform-plan.yml` | Pull Request | Validate and plan infrastructure changes |
| **Infrastructure Deploy** | `infra-deploy.yml` | Push to main | Deploy Terraform/Terragrunt infrastructure |
| **Application Deploy** | `app-deploy.yml` | Manual / Dispatch | Deploy application via Ansible |

### Workflow Relationships

```
Pull Request Created
   ↓
[terraform-plan.yml]
   - Runs terragrunt plan
   - Posts plan as comment
   - No changes applied
   ↓
PR Approved & Merged to main
   ↓
[infra-deploy.yml]
   - Deploy shared infrastructure
   - Deploy QA environments (parallel)
   - Deploy Prod environments (with approval)
   ↓
Infrastructure Ready
   ↓
[app-deploy.yml]
   - Triggered manually or by app repo
   - Deploy application via Ansible
   - Health checks & migrations
```

---

## Workflow: Terraform Plan

**File**: `.github/workflows/terraform-plan.yml`

### Purpose

Validates infrastructure changes in pull requests by running `terragrunt plan` and posting results as PR comments.

### Triggers

```yaml
on:
  pull_request:
    branches: [main]
    paths:
      - "terragrunt/**"
      - ".github/workflows/terraform-plan.yml"
```

Runs when:
- ✅ Pull request opened/updated against `main`
- ✅ Changes in `terragrunt/` directory
- ✅ Changes to the workflow file itself

### Workflow Steps

```
1. Checkout code
   ↓
2. Setup Terragrunt (custom action)
   - Install Terraform 1.5.7
   - Install Terragrunt 0.54.0
   - Azure OIDC login
   ↓
3. Detect changed directories
   - Compare PR branch with main
   - Identify modified Terragrunt configs
   ↓
4. Run terragrunt plan
   - For each changed directory
   - Generate plan output
   ↓
5. Post plan as PR comment
   - Show resources to be added/changed/destroyed
   - Highlight any errors
```

### Example Output

PR comment will show:

```
## Terraform Plan: terragrunt/iaas/qa

Plan: 2 to add, 1 to change, 0 to destroy.

### Resources to Add
- azurerm_network_security_rule.https
- azurerm_public_ip.backup

### Resources to Change
- azurerm_linux_virtual_machine.main
  ~ vm_size: "Standard_B1s" → "Standard_B2s"
```

### Configuration

**Environment variables**:
```yaml
env:
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
  ARM_USE_OIDC: true
```

**Permissions**:
```yaml
permissions:
  id-token: write      # Required for OIDC
  contents: read       # Read repository
  pull-requests: write # Post comments
```

### Usage

**Automatic**: Plan runs automatically on PR creation/update

**Manual rerun**:
```bash
# Re-run workflow
gh run rerun <run-id>
```

---

## Workflow: Infrastructure Deploy

**File**: `.github/workflows/infra-deploy.yml`

### Purpose

Deploys infrastructure changes to Azure after PR merge to main branch.

### Triggers

```yaml
on:
  push:
    branches: [main]
    paths:
      - "terragrunt/**"
      - ".github/workflows/infra-deploy.yml"
  workflow_dispatch:  # Manual trigger
```

### Deployment Strategy

**Sequential deployment with parallelization**:

```
Stage 1: Shared Infrastructure
   ↓
Stage 2: QA Environments (parallel)
   ├─ QA IaaS
   └─ QA PaaS
   ↓
Stage 3: Production (requires approval, parallel)
   ├─ Prod IaaS
   └─ Prod PaaS
```

### Job: deploy-shared

**Purpose**: Deploy shared resources (ACR)

```yaml
deploy-shared:
  runs-on: ubuntu-latest
  steps:
    - name: Checkout
    - name: Setup Terragrunt
    - name: Deploy Shared Infrastructure
      working-directory: terragrunt/shared
      run: |
        terragrunt init
        terragrunt apply -auto-approve
```

**Resources deployed**:
- Azure Container Registry
- Shared resource group

**Duration**: ~2-3 minutes

### Job: deploy-qa

**Purpose**: Deploy QA environments in parallel

```yaml
deploy-qa:
  runs-on: ubuntu-latest
  needs: [deploy-shared]
  environment: qa
  strategy:
    matrix:
      deployment: [iaas, paas]
    fail-fast: false
```

**Matrix strategy**:
- Runs two parallel jobs: `iaas` and `paas`
- `fail-fast: false` - Both deployments attempt even if one fails

**Resources deployed per deployment**:
- IaaS: VNet, VM, MySQL, NSG, Public IP
- PaaS: App Service Plan, App Service, MySQL

**Duration**: ~10-15 minutes per deployment

### Job: deploy-prod

**Purpose**: Deploy production with approval

```yaml
deploy-prod:
  runs-on: ubuntu-latest
  needs: [deploy-shared]
  environment: prod  # Requires approval
  strategy:
    matrix:
      deployment: [iaas, paas]
```

**Approval process**:
1. Workflow pauses at `environment: prod`
2. Designated reviewers notified
3. Reviewer approves/rejects in GitHub UI
4. On approval, deployment proceeds

**Protection rules** (configured in GitHub Settings):
- Required reviewers: 1-2 people
- Wait timer: 5 minutes (optional)
- Restrict to specific branches: main

### Configuration

**Secrets required**:
```
Repository secrets:
  - AZURE_CLIENT_ID
  - AZURE_TENANT_ID
  - AZURE_SUBSCRIPTION_ID
  - SSH_PUBLIC_KEY

Environment secrets (qa/prod):
  - DB_HOST
  - DB_PORT
  - DB_DATABASE
  - DB_USERNAME
  - DB_PASSWORD
  - APP_KEY
```

### Usage

**Automatic**: Runs on push to main

**Manual trigger**:
```bash
gh workflow run infra-deploy.yml
```

**Monitor deployment**:
```bash
# List recent runs
gh run list --workflow=infra-deploy.yml

# Watch specific run
gh run watch <run-id>

# View logs
gh run view <run-id> --log
```

---

## Workflow: Application Deploy

**File**: `.github/workflows/app-deploy.yml`

### Purpose

Deploys application to VMs using Ansible playbooks.

### Triggers

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Environment to deploy to"
        required: true
        type: choice
        options:
          - qa
          - prod
      image_tag:
        description: "Docker image tag to deploy"
        required: true
        type: string

  repository_dispatch:
    types: [deploy-app]
```

**Two trigger methods**:

1. **Manual** (`workflow_dispatch`):
   - Triggered via GitHub UI or CLI
   - User selects environment and image tag

2. **Automatic** (`repository_dispatch`):
   - Triggered by application repository after successful build
   - Payload includes environment and image tag

### Workflow Steps

```
1. Checkout code
   ↓
2. Set environment variables
   - ENV_NAME (qa/prod)
   - IMAGE_TAG (e.g., 1.2.3)
   ↓
3. Azure Login (OIDC)
   ↓
4. Setup Terraform/Terragrunt
   ↓
5. Get infrastructure outputs
   - VM public IPs
   - Database credentials
   - ACR name
   ↓
6. Setup Ansible
   - Install Ansible
   - Install community.docker collection
   ↓
7. Configure SSH
   - Add private key to agent
   - Disable host key checking (first-time)
   ↓
8. Create dynamic inventory
   - Populate inventory from Terragrunt outputs
   ↓
9. Get ACR credentials
   - Login to ACR via Azure identity
   ↓
10. Run Ansible playbook
   - Deploy application
   - Health checks
   - Database migrations
   ↓
11. Deployment complete
```

### Dynamic Inventory Generation

The workflow creates Ansible inventory dynamically from Terragrunt outputs:

```yaml
- name: Create dynamic inventory
  run: |
    mkdir -p ansible/inventories/dynamic
    cat > ansible/inventories/dynamic/${{ env.ENV_NAME }}.yml <<EOF
    all:
      children:
        app_servers:
          hosts:
            $(echo "$VM_IPS" | jq -r '.[]' | awk '{print "vm-"NR":"}')
          vars:
            ansible_user: azureuser
            ansible_ssh_private_key_file: ~/.ssh/id_rsa
            env_name: ${{ env.ENV_NAME }}
            acr_name: $ACR_NAME
            app_image_tag: ${{ env.IMAGE_TAG }}
    EOF
```

### Ansible Playbook Execution

```yaml
- name: Deploy application
  working-directory: ansible
  env:
    DB_HOST: ${{ secrets.DB_HOST }}
    DB_PORT: ${{ secrets.DB_PORT }}
    DB_DATABASE: ${{ secrets.DB_DATABASE }}
    DB_USERNAME: ${{ secrets.DB_USERNAME }}
    DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
    APP_KEY: ${{ secrets.APP_KEY }}
  run: |
    ansible-playbook \
      -i inventories/dynamic/${{ env.ENV_NAME }}.yml \
      playbooks/deploy.yml \
      -v
```

**Environment variables passed to Ansible**:
- Database connection details
- Application encryption key
- Environment name
- Image tag
- ACR credentials

### Deployment Flow

See [ANSIBLE.md](ANSIBLE.md) for detailed playbook documentation.

**Summary**:
1. Authenticate to ACR
2. Pull Docker image
3. Stop existing container
4. Start new container
5. Wait for health check
6. Run database migrations
7. Rollback on failure

### Usage

**Manual deployment via UI**:
1. Go to Actions tab
2. Select "Application Deploy"
3. Click "Run workflow"
4. Select environment: `qa` or `prod`
5. Enter image tag: e.g., `1.2.3`
6. Run

**Manual deployment via CLI**:
```bash
gh workflow run app-deploy.yml \
  -f environment=qa \
  -f image_tag=1.2.3

# Watch deployment
gh run watch
```

**Automatic deployment from app repo**:

Application repository triggers deployment after successful build:

```yaml
# In terracloud repo .github/workflows/ci.yml
- name: Trigger deployment
  run: |
    curl -X POST \
      -H "Authorization: token ${{ secrets.INFRA_REPO_PAT }}" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/${{ vars.INFRA_REPO }}/dispatches \
      -d '{
        "event_type": "deploy-app",
        "client_payload": {
          "environment": "qa",
          "image_tag": "${{ steps.semver.outputs.version }}"
        }
      }'
```

### Troubleshooting Deployment

**Check workflow logs**:
```bash
gh run view --log
```

**SSH to VM directly**:
```bash
# Get VM IP
cd terragrunt/iaas/qa
VM_IP=$(terragrunt output -raw vm_public_ip)

# SSH
ssh -i ~/.ssh/terracloud_deploy azureuser@$VM_IP

# Check container
docker ps
docker logs app
```

**Re-run failed deployment**:
```bash
gh run rerun <run-id>
```

---

## Cross-Repository Integration

### Application Repository → Infrastructure Repository

**Flow**:
```
[App Repo: terracloud]
   Build successful
   ↓
   Create Git tag (v1.2.3)
   ↓
   Push image to ACR
   ↓
   Trigger repository_dispatch
   ↓
[Infra Repo: terracloud-infra]
   Receive dispatch event
   ↓
   Run app-deploy.yml workflow
```

### Setup Requirements

**In application repository** (`terracloud`):

**Repository secrets**:
```
INFRA_REPO_PAT  # GitHub Personal Access Token with repo scope
```

**Repository variables**:
```
INFRA_REPO      # e.g., "ratataque/terracloud-infra"
```

**CI workflow** (`.github/workflows/ci.yml`):
```yaml
- name: Trigger deployment to QA
  if: github.ref == 'refs/heads/main'
  run: |
    curl -X POST \
      -H "Authorization: token ${{ secrets.INFRA_REPO_PAT }}" \
      -H "Accept: application/vnd.github.v3+json" \
      https://api.github.com/repos/${{ vars.INFRA_REPO }}/dispatches \
      -d '{
        "event_type": "deploy-app",
        "client_payload": {
          "environment": "qa",
          "image_tag": "${{ steps.semver.outputs.version }}"
        }
      }'
```

**In infrastructure repository** (`terracloud-infra`):

**Workflow listener** (`.github/workflows/app-deploy.yml`):
```yaml
on:
  repository_dispatch:
    types: [deploy-app]

jobs:
  deploy:
    environment: ${{ github.event.client_payload.environment }}
    steps:
      - name: Set variables
        run: |
          echo "IMAGE_TAG=${{ github.event.client_payload.image_tag }}" >> $GITHUB_ENV
```

### GitHub PAT Setup

**Create Personal Access Token**:
1. GitHub → Settings → Developer settings
2. Personal access tokens → Tokens (classic)
3. Generate new token
4. Name: "TerraCloud Deploy"
5. Scopes: ☑️ `repo` (full control)
6. Generate token
7. Copy token
8. Add to app repository as secret: `INFRA_REPO_PAT`

**Token permissions**:
- `repo:status` - Access commit status
- `repo_deployment` - Access deployment status
- `public_repo` or `repo` - Access repository (depends on visibility)

---

## Workflow Customization

### Adding New Environment

**1. Create environment in GitHub**:
- Settings → Environments → New environment
- Name: `staging`
- Configure protection rules

**2. Add environment secrets**:
- DB_HOST, DB_PORT, DB_DATABASE, etc.

**3. Add to workflow**:

```yaml
# In infra-deploy.yml
deploy-staging:
  runs-on: ubuntu-latest
  needs: [deploy-qa]
  environment: staging
  strategy:
    matrix:
      deployment: [iaas]
  steps:
    # ... same as deploy-qa
```

**4. Create Terragrunt config**:
```bash
mkdir -p terragrunt/iaas/staging
# Create terragrunt.hcl with staging-specific inputs
```

### Customizing Approval Process

**Multiple reviewers**:
```
Settings → Environments → prod → Required reviewers
  Add: user1, user2
  Required approvals: 2
```

**Wait timer**:
```
Settings → Environments → prod → Wait timer
  Minutes: 10
```

**Deployment branches**:
```
Settings → Environments → prod → Deployment branches
  Selected branches: main
```

### Adding Pre-Deployment Checks

```yaml
pre-deploy-checks:
  runs-on: ubuntu-latest
  steps:
    - name: Check application health
      run: |
        curl -f https://qa.terracloud.com/health || exit 1
    
    - name: Run security scan
      uses: aquasecurity/trivy-action@master
      with:
        image-ref: ${{ env.ACR_NAME }}.azurecr.io/app:${{ env.IMAGE_TAG }}

deploy:
  needs: [pre-deploy-checks]
  # ... deployment steps
```

### Notifications

**Add Slack notifications**:

```yaml
- name: Notify deployment success
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "Deployment to ${{ env.ENV_NAME }} succeeded!",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "✅ Deployment to *${{ env.ENV_NAME }}* succeeded!\nImage: `${{ env.IMAGE_TAG }}`"
            }
          }
        ]
      }
```

---

## Best Practices

### Workflow Security

✅ **Do:**
- Use OIDC instead of static credentials
- Store secrets in GitHub Environments
- Use least privilege for PATs
- Enable branch protection on main
- Require PR reviews before merge

❌ **Don't:**
- Commit credentials to workflows
- Share PATs across repositories
- Use admin PATs for deployments
- Disable security features for convenience

### Workflow Performance

**Optimize Terragrunt**:
```bash
# Use -parallelism flag
terragrunt apply -auto-approve -parallelism=10
```

**Cache dependencies**:
```yaml
- name: Cache Terraform
  uses: actions/cache@v3
  with:
    path: |
      ~/.terraform.d/plugin-cache
    key: ${{ runner.os }}-terraform-${{ hashFiles('**/*.tf') }}
```

### Monitoring Workflows

**Set up workflow alerts**:
```
Settings → Notifications → Actions
  ☑️ Failed workflows
  ☑️ Workflow run requires approval
```

**Review workflow logs regularly**:
```bash
# List failed runs
gh run list --workflow=infra-deploy.yml --status=failure

# View details
gh run view <run-id> --log
```

---

## Next Steps

- **Deploy application**: See [DEPLOYMENT.md](DEPLOYMENT.md)
- **Ansible details**: See [ANSIBLE.md](ANSIBLE.md)
- **Troubleshooting**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
