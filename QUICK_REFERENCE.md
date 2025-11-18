# TerraCloud Quick Reference

## Repository URLs

- **App**: `/home/ewan/projets/terra_cloud`
- **Infra**: `/home/ewan/projets/terra_cloud_infra`

## Common Commands

### Application Development

```bash
cd /home/ewan/projets/terra_cloud/app

# Local development
composer install
php artisan serve

# Run tests
php artisan test

# Build Docker image locally
docker build -t test:dev -f Dockerfile .

# Release (semantic versioning)
git commit -m "feat: new feature (MINOR)"  # Bumps minor
git commit -m "fix: bug fix"                # Bumps patch
git commit -m "breaking: API change (MAJOR)" # Bumps major
git push origin main
```

### Infrastructure Management

```bash
cd /home/ewan/projets/terra_cloud_infra

# Deploy shared infrastructure (ACR)
cd terragrunt/shared
terragrunt init
terragrunt plan
terragrunt apply

# Deploy QA environment
cd terragrunt/iaas/qa
terragrunt apply

# Deploy Prod environment
cd terragrunt/iaas/prod
terragrunt apply

# Check outputs
terragrunt output
terragrunt output -raw vm_public_ip
```

### Application Deployment (Ansible)

```bash
cd /home/ewan/projets/terra_cloud_infra/ansible

# Set environment variables first:
export QA_VM_IP="x.x.x.x"
export ACR_NAME="youracr"
export IMAGE_TAG="1.2.3"
export SSH_KEY_PATH="~/.ssh/id_rsa"
# ... (see full list in INTEGRATION_GUIDE.md)

# Deploy to QA
ansible-playbook -i inventories/qa.yml playbooks/deploy.yml

# Deploy to Prod
ansible-playbook -i inventories/prod.yml playbooks/deploy.yml

# Test connectivity
ansible -i inventories/qa.yml all -m ping

# Check container status
ansible -i inventories/qa.yml all -a "docker ps"
```

## GitHub Actions Workflows

### In `terra_cloud` (app repo)

**CI Workflow** - `.github/workflows/ci.yml`
- **Trigger**: Push to main, PRs
- **Actions**: Test → Build → Tag → Push to ACR
- **Outputs**: Semantic version tag (v1.2.3)

### In `terra_cloud_infra` (infra repo)

**Terraform Plan** - `.github/workflows/terraform-plan.yml`
- **Trigger**: PR to main
- **Actions**: Plan changes, post as PR comment

**Infra Deploy** - `.github/workflows/infra-deploy.yml`
- **Trigger**: Push to main
- **Actions**: Deploy shared → QA → Prod (with approvals)

**App Deploy** - `.github/workflows/app-deploy.yml`
- **Trigger**: Manual or repository_dispatch
- **Actions**: Run Ansible to deploy specific version

## Secrets Configuration

### App Repo (`terra_cloud`)

**Repository Secrets**:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `ACR_NAME` (e.g., `terracloudacr`)
- `INFRA_REPO_PAT` (GitHub token)

**Repository Variables**:
- `INFRA_REPO` (e.g., username/terra_cloud_infra)

### Infra Repo (`terra_cloud_infra`)

**Repository Secrets**:
- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `SSH_PRIVATE_KEY`

**Environment Secrets** (qa, prod):
- `DB_HOST`
- `DB_PORT`
- `DB_DATABASE`
- `DB_USERNAME`
- `DB_PASSWORD`
- `APP_KEY`

## Image Tags

Every build creates 3 tags:
- `v1.2.3` - Semantic version (use for prod)
- `v1.2.3-abc123` - Version + git SHA
- `latest` - Latest build (dev/testing only)

**Always deploy to prod using semantic version, never `latest`!**

## Troubleshooting

### CI fails to connect to ACR
```bash
cd /home/ewan/projets/terra_cloud_infra/terragrunt/shared
terragrunt output  # Verify shared infra exists
```

### Ansible can't connect to VM
```bash
# Get VM IP
cd terragrunt/iaas/qa
terragrunt output vm_public_ip

# Test SSH
ssh -i ~/.ssh/id_rsa azureuser@<VM_IP>
```

### Container won't start
```bash
ssh azureuser@<VM_IP>
docker logs terracloud-app
docker ps -a
```

### Health check fails
```bash
# Check if health endpoint exists
curl http://<VM_IP>/api/health

# View logs
docker logs terracloud-app -f
```

## File Locations

### Documentation
- `/home/ewan/projets/INTEGRATION_GUIDE.md` - Integration steps
- `/home/ewan/projets/SUMMARY.md` - What was done
- `/home/ewan/projets/terra_cloud/README.md` - App guide
- `/home/ewan/projets/terra_cloud_infra/README.md` - Infra guide

### Key Files
- App Dockerfile: `terra_cloud/app/Dockerfile`
- App CI: `terra_cloud/.github/workflows/ci.yml`
- Ansible deploy: `terra_cloud_infra/ansible/playbooks/deploy.yml`
- Terragrunt root: `terra_cloud_infra/terragrunt/root.hcl`

## Quick Deploy Checklist

- [ ] Code pushed to app repo
- [ ] CI passes (green checkmark)
- [ ] Docker image in ACR
- [ ] Note semantic version (e.g., v1.2.3)
- [ ] Trigger deploy workflow in infra repo
- [ ] Select environment (qa/prod)
- [ ] Enter version tag
- [ ] Watch Ansible playbook
- [ ] Verify health check passes
- [ ] Test the deployment

## Emergency Rollback

### Via GitHub Actions
1. Go to infra repo → Actions → Application Deploy
2. Enter previous working version
3. Run workflow

### Via Ansible
```bash
cd /home/ewan/projets/terra_cloud_infra/ansible
export IMAGE_TAG="1.2.2"  # Previous version
ansible-playbook -i inventories/prod.yml playbooks/deploy.yml
```

### Via SSH (emergency)
```bash
ssh azureuser@<VM_IP>
docker stop terracloud-app
docker run -d --name terracloud-app \
  -p 80:80 \
  <acr>.azurecr.io/app:1.2.2
```

## Support

- App issues → `terra_cloud` repo
- Infra issues → `terra_cloud_infra` repo
- Integration issues → Either repo with `integration` label
