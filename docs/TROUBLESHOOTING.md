# Troubleshooting Guide

Common issues and solutions for TerraCloud infrastructure deployment and operations.

## Table of Contents

- [Infrastructure Issues](#infrastructure-issues)
- [Deployment Issues](#deployment-issues)
- [Ansible Issues](#ansible-issues)
- [Database Issues](#database-issues)
- [Network Issues](#network-issues)
- [Application Issues](#application-issues)
- [GitHub Actions Issues](#github-actions-issues)

---

## Infrastructure Issues

### Issue: Terraform State Lock

**Symptoms**:
```
Error: Error acquiring the state lock
Error message: ConflictError: The specified blob is currently locked
```

**Causes**:
- Previous terraform/terragrunt command interrupted
- Multiple users running terraform simultaneously
- Workflow run cancelled mid-execution

**Solutions**:

**1. Wait for lock to expire** (automatic after timeout)

**2. Force unlock** (if you're sure no one else is running terraform):
```bash
cd terragrunt/<path>
terragrunt force-unlock <LOCK_ID>

# Lock ID is shown in error message
```

**3. Check Azure Storage for locks**:
```bash
az storage blob list \
  --account-name terracloudtfstate \
  --container-name tfstate \
  --auth-mode login
```

**Prevention**:
- Use pull request workflow for planning
- Coordinate with team before applying changes
- Don't cancel workflows mid-execution

---

### Issue: Terragrunt "Dependency cycle"

**Symptoms**:
```
Error: Dependency cycle detected
```

**Causes**:
- Circular dependencies in terragrunt.hcl files
- Incorrect dependency paths

**Solutions**:

**1. Check dependency graph**:
```bash
terragrunt graph-dependencies
```

**2. Review dependencies** in terragrunt.hcl:
```hcl
# Check for circular references
dependency "shared" {
  config_path = "../../shared"
}
```

**3. Remove circular dependencies**:
- Ensure dependencies flow in one direction
- Shared → QA/Prod (not bidirectional)

---

### Issue: Azure OIDC Authentication Failed

**Symptoms**:
```
Error: Failed to exchange OIDC token
Error: AADSTS700016: Application with identifier '...' was not found
```

**Causes**:
- Federated credential not configured correctly
- Wrong Client ID in GitHub secrets
- Service principal missing permissions

**Solutions**:

**1. Verify federated credentials exist**:
```bash
az ad app federated-credential list --id <APP_ID>
```

**2. Check GitHub secrets match**:
```bash
# Azure Client ID
az ad app list --display-name "terracloud-cd-deployer" --query "[0].appId" -o tsv

# Compare with GitHub secret AZURE_CLIENT_ID
```

**3. Recreate federated credential**:
```bash
az ad app federated-credential create \
  --id <APP_ID> \
  --parameters '{
    "name": "GitHub-Main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:ratataque/terracloud-infra:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

**4. Verify service principal has Contributor role**:
```bash
az role assignment list --assignee <APP_ID> --output table
```

---

### Issue: Resource Group Already Exists

**Symptoms**:
```
Error: A resource with the ID already exists
```

**Causes**:
- Previous deployment not fully destroyed
- Manual resource creation with same name
- State file out of sync

**Solutions**:

**1. Import existing resource into state**:
```bash
terragrunt import azurerm_resource_group.main /subscriptions/<SUB_ID>/resourceGroups/terracloud-qa-rg
```

**2. Delete resource group and redeploy**:
```bash
az group delete --name terracloud-qa-rg --yes
terragrunt apply
```

**3. Refresh state**:
```bash
terragrunt refresh
```

---

## Deployment Issues

### Issue: Container Fails to Start

**Symptoms**:
- Ansible playbook reports container started but exits immediately
- `docker ps` shows no running container

**Causes**:
- Application error on startup
- Missing environment variables
- Database connection failure
- Insufficient memory

**Solutions**:

**1. Check container logs**:
```bash
ssh azureuser@<VM_IP>
docker logs app

# Look for:
# - "Connection refused" (database)
# - "APP_KEY" errors
# - Memory errors
```

**2. Verify environment variables**:
```bash
docker inspect app | jq '.[0].Config.Env'
```

**3. Test container locally**:
```bash
docker run --rm \
  -e APP_KEY="base64:..." \
  -e DB_HOST="..." \
  terracloudacr.azurecr.io/app:1.2.3
```

**4. Check VM memory**:
```bash
free -h
# If low memory, reduce container resources or upgrade VM
```

---

### Issue: Image Pull Fails

**Symptoms**:
```
Error: Failed to pull image
Error response from daemon: unauthorized: authentication required
```

**Causes**:
- ACR authentication expired
- Managed identity not configured
- Network connectivity issues

**Solutions**:

**1. Test ACR authentication on VM**:
```bash
ssh azureuser@<VM_IP>

# Try pulling image
docker pull terracloudacr.azurecr.io/app:1.2.3
```

**2. Re-authenticate to ACR**:
```bash
# Via Azure CLI
az acr login --name terracloudacr

# Via managed identity
docker login terracloudacr.azurecr.io \
  --username 00000000-0000-0000-0000-000000000000 \
  --password-stdin <<< $(az account get-access-token --resource https://management.azure.com --query accessToken -o tsv)
```

**3. Check ACR firewall rules**:
```bash
az acr network-rule list --name terracloudacr
```

**4. Verify image exists**:
```bash
az acr repository show-tags --name terracloudacr --repository app
```

---

### Issue: Health Check Timeout

**Symptoms**:
```
TASK [Wait for container to be healthy] ***
fatal: [vm-1]: FAILED! => {"msg": "Timed out waiting for health check"}
```

**Causes**:
- Application not responding
- Wrong health check endpoint
- Container not fully started
- Database connection issues

**Solutions**:

**1. Check application logs**:
```bash
docker logs app -f
```

**2. Test health endpoint manually**:
```bash
# From VM
curl http://localhost/health

# From external
curl http://<VM_IP>/health
```

**3. Increase health check retries**:
```yaml
# In deploy.yml
vars:
  health_check_retries: 20  # Increase from 10
  health_check_delay: 15    # Increase delay
```

**4. Check if application port is accessible**:
```bash
nc -zv localhost 80
```

---

## Ansible Issues

### Issue: SSH Connection Refused

**Symptoms**:
```
fatal: [vm-1]: UNREACHABLE! => {
  "msg": "Failed to connect to the host via ssh: Connection refused"
}
```

**Causes**:
- VM not running
- Wrong IP address
- NSG blocking SSH
- SSH service not running

**Solutions**:

**1. Verify VM is running**:
```bash
cd terragrunt/iaas/qa
terragrunt output vm_public_ip

az vm list --resource-group terracloud-qa-rg --output table
```

**2. Check NSG rules**:
```bash
az network nsg rule list \
  --resource-group terracloud-qa-rg \
  --nsg-name terracloud-qa-nsg \
  --output table

# Verify SSH (port 22) is allowed from your IP
```

**3. Add your IP to NSG**:
```bash
az network nsg rule create \
  --resource-group terracloud-qa-rg \
  --nsg-name terracloud-qa-nsg \
  --name AllowSSHFromMyIP \
  --priority 1000 \
  --source-address-prefixes $(curl -s ifconfig.me) \
  --destination-port-ranges 22 \
  --access Allow \
  --protocol Tcp
```

**4. Test SSH manually**:
```bash
ssh -i ~/.ssh/terracloud_deploy azureuser@<VM_IP>
```

---

### Issue: SSH Permission Denied

**Symptoms**:
```
fatal: [vm-1]: UNREACHABLE! => {
  "msg": "Failed to connect: Permission denied (publickey)"
}
```

**Causes**:
- Wrong SSH key
- Key not loaded in ssh-agent
- Public key not on VM

**Solutions**:

**1. Verify SSH key**:
```bash
# Check key exists
ls -la ~/.ssh/terracloud_deploy

# Check permissions
chmod 600 ~/.ssh/terracloud_deploy
```

**2. Test SSH with key**:
```bash
ssh -i ~/.ssh/terracloud_deploy azureuser@<VM_IP>
```

**3. Add key to ssh-agent** (for GitHub Actions):
```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/terracloud_deploy
```

**4. Verify public key on VM**:
```bash
# Via Azure Serial Console or cloud-init logs
cat ~/.ssh/authorized_keys
```

---

### Issue: Ansible Module Not Found

**Symptoms**:
```
ERROR! couldn't resolve module/action 'community.docker.docker_container'
```

**Causes**:
- Ansible collection not installed
- Wrong Ansible version

**Solutions**:

**1. Install required collections**:
```bash
ansible-galaxy collection install community.docker
ansible-galaxy collection install azure.azcollection
```

**2. Verify collections installed**:
```bash
ansible-galaxy collection list
```

**3. Check Ansible version**:
```bash
ansible --version
# Ensure 2.9+ for collections support
```

---

## Database Issues

### Issue: Cannot Connect to MySQL

**Symptoms**:
```
SQLSTATE[HY000] [2002] Connection refused
SQLSTATE[HY000] [2002] Connection timed out
```

**Causes**:
- MySQL server not running
- Wrong connection credentials
- Firewall blocking connection
- SSL configuration issue

**Solutions**:

**1. Verify MySQL server is running**:
```bash
az mysql flexible-server show \
  --resource-group terracloud-qa-rg \
  --name terracloud-qa-mysql
```

**2. Test connection from VM**:
```bash
ssh azureuser@<VM_IP>

# Install mysql client
sudo apt-get install -y mysql-client

# Test connection
mysql -h terracloud-qa-mysql.mysql.database.azure.com \
  -u dbadmin \
  -p \
  -e "SHOW DATABASES;"
```

**3. Check MySQL firewall rules**:
```bash
az mysql flexible-server firewall-rule list \
  --resource-group terracloud-qa-rg \
  --name terracloud-qa-mysql \
  --output table
```

**4. Add firewall rule for VM**:
```bash
az mysql flexible-server firewall-rule create \
  --resource-group terracloud-qa-rg \
  --name terracloud-qa-mysql \
  --rule-name AllowVMSubnet \
  --start-ip-address <VM_PRIVATE_IP> \
  --end-ip-address <VM_PRIVATE_IP>
```

**5. Check SSL requirement**:
```bash
# MySQL requires SSL by default
# Ensure application has SSL certificate configured
```

---

### Issue: Database Migration Fails

**Symptoms**:
```
Error: Migration failed
SQLSTATE[42S01]: Base table or view already exists
```

**Causes**:
- Migration already run
- Schema out of sync
- Missing migration files

**Solutions**:

**1. Check migration status**:
```bash
docker exec app php artisan migrate:status
```

**2. Rollback and re-run**:
```bash
docker exec app php artisan migrate:rollback
docker exec app php artisan migrate --force
```

**3. Fresh migration** (WARNING: destroys data):
```bash
docker exec app php artisan migrate:fresh --force
docker exec app php artisan db:seed --force
```

**4. Restore database backup** (if migration corrupted data):
```bash
az mysql flexible-server restore \
  --resource-group terracloud-qa-rg \
  --name terracloud-qa-mysql-restored \
  --source-server terracloud-qa-mysql \
  --restore-time "2024-01-01T00:00:00Z"
```

---

## Network Issues

### Issue: Cannot Access Application

**Symptoms**:
- `curl http://<VM_IP>/` returns connection timeout
- Application not accessible from browser

**Causes**:
- NSG blocking HTTP/HTTPS
- Container not listening on correct port
- Traefik not configured correctly

**Solutions**:

**1. Check NSG rules allow HTTP**:
```bash
az network nsg rule list \
  --resource-group terracloud-qa-rg \
  --nsg-name terracloud-qa-nsg \
  --query "[?destinationPortRange=='80']" \
  --output table
```

**2. Test from VM itself**:
```bash
ssh azureuser@<VM_IP>
curl http://localhost/health
```

**3. Check container port mapping**:
```bash
docker ps
# Verify container is listening on port 80
```

**4. Check Traefik status**:
```bash
docker ps | grep traefik
docker logs traefik
```

**5. Test with direct container access**:
```bash
# Find container IP
docker inspect app | jq '.[0].NetworkSettings.Networks'

# Test directly
curl http://<CONTAINER_IP>/health
```

---

### Issue: Public IP Not Assigned

**Symptoms**:
- VM has no public IP
- Cannot SSH to VM

**Causes**:
- Public IP not created
- Public IP not associated with NIC
- Terraform apply didn't complete

**Solutions**:

**1. Check if public IP exists**:
```bash
az network public-ip show \
  --resource-group terracloud-qa-rg \
  --name terracloud-qa-public-ip
```

**2. Check NIC association**:
```bash
az network nic show \
  --resource-group terracloud-qa-rg \
  --name terracloud-qa-nic \
  --query ipConfigurations[0].publicIPAddress
```

**3. Re-apply Terraform**:
```bash
cd terragrunt/iaas/qa
terragrunt apply -target=azurerm_public_ip.main
terragrunt apply -target=azurerm_network_interface.main
```

---

## Application Issues

### Issue: Application Returns 500 Error

**Symptoms**:
- HTTP 500 Internal Server Error
- Application logs show errors

**Causes**:
- Missing environment variables
- Application bug
- Database connection issue
- Insufficient permissions

**Solutions**:

**1. Check application logs**:
```bash
docker logs app --tail 100

# Look for stack traces, error messages
```

**2. Enable debug mode temporarily**:
```bash
docker stop app
docker rm app

# Start with debug enabled
docker run -d \
  --name app \
  -e APP_DEBUG=true \
  -e APP_ENV=qa \
  # ... other env vars
  terracloudacr.azurecr.io/app:1.2.3

# Check logs
docker logs app -f
```

**3. Check environment variables**:
```bash
docker inspect app | jq '.[0].Config.Env'
```

**4. Test database connection**:
```bash
docker exec app php artisan tinker
# DB::connection()->getPdo();
```

---

### Issue: High Memory Usage

**Symptoms**:
- VM out of memory
- Container killed by OOM
- Application slow

**Causes**:
- Memory leak in application
- Too many processes
- Insufficient VM size
- Redis/cache not configured

**Solutions**:

**1. Check memory usage**:
```bash
# VM memory
free -h

# Container memory
docker stats app --no-stream
```

**2. Restart container** (temporary fix):
```bash
docker restart app
```

**3. Upgrade VM size**:
```hcl
# In terragrunt/iaas/qa/terragrunt.hcl
inputs = {
  vm_size = "Standard_B2s"  # 4GB instead of 512MB
}
```

```bash
terragrunt apply
```

**4. Configure PHP memory limit**:
```ini
# In Dockerfile
memory_limit = 256M
```

**5. Enable OPcache** (already enabled in production image)

---

## GitHub Actions Issues

### Issue: Workflow Not Triggering

**Symptoms**:
- Push to main doesn't trigger workflow
- Repository dispatch not received

**Causes**:
- Workflow file syntax error
- Paths filter excludes changes
- Workflow disabled

**Solutions**:

**1. Check workflow is enabled**:
```bash
gh workflow list
# Verify workflow is not disabled
```

**2. Check workflow syntax**:
```bash
# Locally validate YAML
yamllint .github/workflows/infra-deploy.yml
```

**3. Check paths filter**:
```yaml
on:
  push:
    paths:
      - "terragrunt/**"  # Only triggers if these paths changed
```

**4. Manually trigger**:
```bash
gh workflow run infra-deploy.yml
```

---

### Issue: Workflow Fails at OIDC Login

**Symptoms**:
```
Error: Login failed with Error: AADSTS700016
```

**See**: [Azure OIDC Authentication Failed](#issue-azure-oidc-authentication-failed) above

---

### Issue: Secrets Not Available

**Symptoms**:
```
Error: Input required and not supplied: AZURE_CLIENT_ID
```

**Causes**:
- Secret not configured in GitHub
- Wrong environment selected
- Secret name typo

**Solutions**:

**1. Verify secrets exist**:
- Go to repository Settings → Secrets and variables → Actions
- Check both repository secrets and environment secrets

**2. Check secret names match**:
```yaml
# In workflow
${{ secrets.AZURE_CLIENT_ID }}

# Must match exact name in GitHub
```

**3. Check environment name**:
```yaml
jobs:
  deploy:
    environment: qa  # Must match environment name in GitHub
```

---

## Getting Help

### Collect Diagnostic Information

When asking for help, provide:

**1. Terragrunt outputs**:
```bash
cd terragrunt/iaas/qa
terragrunt output
```

**2. VM status**:
```bash
az vm list --resource-group terracloud-qa-rg --output table
```

**3. Container status**:
```bash
ssh azureuser@<VM_IP>
docker ps -a
docker logs app --tail 100
```

**4. Application logs**:
```bash
docker logs app --tail 500 > app.log
```

**5. Ansible output**:
```bash
# Run with maximum verbosity
ansible-playbook -i inventories/qa.yml playbooks/deploy.yml -vvv
```

**6. GitHub Actions logs**:
```bash
gh run view <run-id> --log > workflow.log
```

### Useful Commands Reference

```bash
# Infrastructure
terragrunt output                    # View outputs
terragrunt plan                      # Preview changes
terragrunt apply                     # Apply changes
terragrunt destroy                   # Destroy resources

# Azure
az vm list --output table            # List VMs
az mysql flexible-server list        # List MySQL servers
az acr repository list --name <acr>  # List images

# Ansible
ansible -m ping all                  # Test connectivity
ansible -a "docker ps" all           # Run command
ansible-playbook playbooks/deploy.yml # Deploy

# Docker (on VM)
docker ps                            # List containers
docker logs app                      # View logs
docker exec app <command>            # Execute command
docker stats app                     # Resource usage

# GitHub
gh workflow list                     # List workflows
gh run list                          # List runs
gh run view <run-id>                 # View run details
```

---

## Preventive Measures

### Regular Maintenance

**Weekly**:
- Review application logs for errors
- Check VM disk space
- Monitor database size

**Monthly**:
- Update dependencies
- Review and clean up old Docker images
- Test backup restore procedures

**Quarterly**:
- Review and update NSG rules
- Rotate SSH keys
- Update Terraform providers

### Monitoring Setup

**Set up alerts for**:
- VM CPU > 80%
- VM memory > 90%
- Disk space < 10%
- Database connection failures
- Workflow failures

**Azure Monitor**:
```bash
# Create alert rule
az monitor metrics alert create \
  --name high-cpu-alert \
  --resource-group terracloud-prod-rg \
  --scopes <VM_RESOURCE_ID> \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m \
  --evaluation-frequency 1m
```

---

## Additional Resources

- [Azure Documentation](https://docs.microsoft.com/azure/)
- [Terraform Azure Provider Docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Ansible Documentation](https://docs.ansible.com/)
- [Docker Documentation](https://docs.docker.com/)

---

For issues not covered here, create an issue in the repository or contact the infrastructure team.
