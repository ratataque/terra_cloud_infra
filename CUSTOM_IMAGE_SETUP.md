# Azure Custom VM Image Setup for IaaS Deployment

This guide walks through creating a custom Azure VM image with Docker pre-installed to work around the 512 MB RAM limitation during cloud-init.

---

## 🎯 Goal

Create a custom Ubuntu 22.04 image with Docker pre-installed, so that B1ls VMs (512 MB RAM) can boot without running out of memory during package installation.

---

## 📋 Prerequisites

- Azure CLI logged in
- Permissions to create VMs and images in `rg-stg_1`
- SSH access configured

---

## 🔧 Step 1: Create Temporary Builder VM

Create a larger VM to prepare the image:

```bash
# Create a temporary B2s VM (4 GB RAM) for image preparation
az vm create \
  --resource-group rg-stg_1 \
  --name temp-image-builder \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --ssh-key-value "$(cat ~/.ssh/id_rsa_terraform.pub)" \
  --public-ip-sku Standard
```

**Wait for VM creation to complete**, then get the public IP:

```bash
BUILDER_IP=$(az vm show -d --resource-group rg-stg_1 --name temp-image-builder --query publicIps -o tsv)
echo "Builder VM IP: $BUILDER_IP"
```

---

## 🐳 Step 2: Install Docker on Builder VM

SSH into the builder VM and install Docker:

```bash
# SSH into the builder VM
ssh azureuser@$BUILDER_IP

# Update package list
sudo apt update

# Install Docker and dependencies
sudo apt install -y docker.io docker-compose-plugin curl

# Enable Docker to start on boot
sudo systemctl enable docker

# Verify installation
docker --version
docker compose version

# Clean up package cache to reduce image size
sudo apt clean
sudo apt autoremove -y

# Remove any temporary files
sudo rm -rf /tmp/*
sudo rm -rf /var/tmp/*

# Clear bash history
history -c

# Deprovision the VM (prepare for image capture)
sudo waagent -deprovision+user -force

# Exit SSH session
exit
```

---

## 📸 Step 3: Capture the Custom Image

Back on your local machine, capture the image:

```bash
# Deallocate the VM
az vm deallocate --resource-group rg-stg_1 --name temp-image-builder

# Mark the VM as generalized
az vm generalize --resource-group rg-stg_1 --name temp-image-builder

# Create the custom image
az image create \
  --resource-group rg-stg_1 \
  --name ubuntu2204-docker-image \
  --source temp-image-builder \
  --location westeurope \
  --tags "OS=Ubuntu22.04" "Docker=Preinstalled" "Purpose=TerraCloudIaaS"

# Get the image ID
IMAGE_ID=$(az image show \
  --resource-group rg-stg_1 \
  --name ubuntu2204-docker-image \
  --query id -o tsv)

echo "Custom Image ID: $IMAGE_ID"
# Save this ID - you'll need it for Terraform
```

---

## 🧹 Step 4: Clean Up Builder VM

Delete the temporary builder VM (no longer needed):

```bash
# Delete the builder VM and its resources
az vm delete --resource-group rg-stg_1 --name temp-image-builder --yes

# Clean up associated resources (NIC, Public IP, NSG)
az network nic delete --resource-group rg-stg_1 --name temp-image-builderVMNic
az network public-ip delete --resource-group rg-stg_1 --name temp-image-builderPublicIP
az network nsg delete --resource-group rg-stg_1 --name temp-image-builderNSG
az disk delete --resource-group rg-stg_1 --name temp-image-builder_OsDisk_1_* --yes
```

---

## 🔧 Step 5: Update Terragrunt/Terraform Configuration

### 5.1 Update the IaaS Module

Edit `terragrunt/modules/azure-iaas-app-service/main.tf`:

```hcl
resource "azurerm_linux_virtual_machine" "vm" {
  count               = var.vm_count
  name                = "${var.project_name}-${var.environment}-vm-${count.index}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = "azureuser"

  # Use custom image instead of marketplace image
  source_image_id = var.custom_image_id

  # REMOVE or COMMENT OUT the source_image_reference block:
  # source_image_reference {
  #   publisher = "Canonical"
  #   offer     = "0001-com-ubuntu-server-jammy"
  #   sku       = "22_04-lts-gen2"
  #   version   = "latest"
  # }

  # ... rest of the configuration stays the same
}
```

### 5.2 Add Variable for Custom Image

Edit `terragrunt/modules/azure-iaas-app-service/variables.tf`, add:

```hcl
variable "custom_image_id" {
  description = "The ID of the custom VM image with Docker pre-installed"
  type        = string
  default     = ""  # Optional: use marketplace image if not provided
}
```

### 5.3 Update cloud-init to Skip Docker Installation

Edit `terragrunt/modules/azure-iaas-app-service/cloud-init-docker.yaml`:

Change the beginning to:

```yaml
#cloud-config
# Minimal cloud-init - Docker already in custom image
package_update: false
package_upgrade: false

# No packages needed - Docker is pre-installed in custom image

write_files:
  # docker-compose.yml (same as before)
  - path: /opt/app/docker-compose.yml
    permissions: "0644"
    content: |
      # ... (keep existing docker-compose content)

runcmd:
  # Docker is already installed, just configure
  - mkdir -p /opt/app
  - usermod -aG docker azureuser
  - systemctl enable docker
  - systemctl start docker
  - sleep 5
  - docker login ${acr_login_server} -u ${acr_admin_username} -p ${acr_admin_password}
  - docker pull ${acr_login_server}/${docker_image}:${docker_image_tag}
  - cd /opt/app && docker compose up -d

final_message: "TerraCloud IaaS VM ready with pre-installed Docker!"
```

### 5.4 Update root.hcl with Image ID

Edit `terragrunt/root.hcl`, add the image ID as a local:

```hcl
locals {
  # ... existing locals ...
  
  # Custom VM image with Docker pre-installed
  custom_image_id = "/subscriptions/6b9318b1-2215-418a-b0fd-ba0832e9b333/resourceGroups/rg-stg_1/providers/Microsoft.Compute/images/ubuntu2204-docker-image"
}
```

### 5.5 Update QA and Prod terragrunt.hcl

Edit both `terragrunt/iaas/qa/terragrunt.hcl` and `terragrunt/iaas/prod/terragrunt.hcl`:

Add this input:

```hcl
inputs = {
  # ... existing inputs ...
  
  # Use custom image with Docker pre-installed
  custom_image_id = include.root.locals.custom_image_id
}
```

---

## 🚀 Step 6: Test the Custom Image

### 6.1 Destroy Existing VMs

```bash
# Destroy QA VM
cd /home/ewan/projets/terra_cloud_infra/terragrunt/iaas/qa
terragrunt destroy -auto-approve

# Destroy Prod VM
cd /home/ewan/projets/terra_cloud_infra/terragrunt/iaas/prod
terragrunt destroy -auto-approve
```

### 6.2 Deploy with Custom Image

```bash
# Deploy QA with custom image
cd /home/ewan/projets/terra_cloud_infra/terragrunt/iaas/qa
terragrunt apply -auto-approve

# Wait for completion, then check
QA_VM_IP=$(terragrunt output -raw vm_public_ips | jq -r '.[0]')
echo "QA VM IP: $QA_VM_IP"

# SSH and verify Docker is pre-installed
ssh azureuser@$QA_VM_IP
docker --version
docker ps
exit
```

### 6.3 Deploy Prod

```bash
cd /home/ewan/projets/terra_cloud_infra/terragrunt/iaas/prod
terragrunt apply -auto-approve
```

---

## ✅ Verification

After deployment, verify everything works:

```bash
# SSH into QA VM
ssh azureuser@<QA_VM_IP>

# Check Docker is installed and running
docker --version
sudo systemctl status docker

# Check if app stack is running
cd /opt/app
docker ps

# Check logs
docker logs app
docker logs db
docker logs traefik

# Test the app
curl http://localhost
```

---

## 🔄 Updating the Custom Image

If you need to update the image (e.g., new Docker version):

1. Create a new builder VM from the current custom image
2. Make your updates
3. Capture a new image with a version number:
   - `ubuntu2204-docker-image-v2`
4. Update the image ID in `root.hcl`
5. Redeploy VMs

---

## 📊 Benefits

✅ **Fast Boot**: No package installation during cloud-init  
✅ **Memory Efficient**: Works with 512 MB RAM VMs  
✅ **Consistent**: Same Docker version across all VMs  
✅ **Reliable**: No OOM killer during provisioning  
✅ **Cost Effective**: Can use smallest VM sizes  

---

## 🐛 Troubleshooting

### Image Creation Fails

```bash
# Check if VM is properly deallocated
az vm get-instance-view --resource-group rg-stg_1 --name temp-image-builder --query instanceView.statuses

# Should show "VM deallocated" and "VM generalized"
```

### VM Won't Boot from Custom Image

```bash
# Check image exists
az image show --resource-group rg-stg_1 --name ubuntu2204-docker-image

# Check image ID in terraform
cd terragrunt/iaas/qa
terragrunt console
> var.custom_image_id
```

### Docker Not Starting

```bash
# SSH into VM
ssh azureuser@<VM_IP>

# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log

# Check if Docker was enabled
sudo systemctl status docker
sudo journalctl -u docker
```

---

## 📝 Notes

- The custom image is stored in the same resource group as your VMs
- Images are region-specific (stored in `westeurope`)
- Consider creating images in each region you deploy to
- Image size will be ~2-3 GB (Ubuntu + Docker)
- No additional cost for storing images in Azure

---

**Created**: 2025-11-21  
**Author**: GitHub Copilot CLI  
**Purpose**: TerraCloud IaaS deployment with memory-constrained VMs
