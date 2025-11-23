# Infrastructure Architecture

Detailed documentation of the TerraCloud infrastructure architecture, modules, and resource organization.

## Table of Contents

- [Overview](#overview)
- [Infrastructure Layers](#infrastructure-layers)
- [Terraform Modules](#terraform-modules)
- [Environment Strategy](#environment-strategy)
- [Network Architecture](#network-architecture)
- [Resource Naming](#resource-naming)

---

## Overview

The TerraCloud infrastructure follows a **modular, multi-environment architecture** designed for:

- **Scalability**: Easy to add new environments or services
- **Maintainability**: DRY principles with Terragrunt
- **Flexibility**: Support for both IaaS (VMs) and PaaS (App Service)
- **Security**: Network isolation and managed identities
- **Cost Efficiency**: Shared resources and right-sizing

### Architecture Principles

1. **Separation of Concerns**: App code separate from infrastructure
2. **Immutable Infrastructure**: Replace, don't modify
3. **Infrastructure as Code**: All resources defined in Terraform
4. **Environment Parity**: QA mirrors Production
5. **Least Privilege**: Minimal permissions and network access

---

## Infrastructure Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     Layer 1: Shared                         │
│                                                             │
│  ┌─────────────────────────────────────────────────┐       │
│  │  Azure Container Registry (ACR)                  │       │
│  │  - Single registry for all environments          │       │
│  │  - Geo-replication available                     │       │
│  │  - RBAC-based access                             │       │
│  └─────────────────────────────────────────────────┘       │
│                                                             │
│  Managed by: terragrunt/shared                             │
└─────────────────────────────────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
┌────────────────┐  ┌──────────────┐  ┌──────────────┐
│   Layer 2:     │  │  Layer 2:    │  │  Layer 2:    │
│   QA (IaaS)    │  │  QA (PaaS)   │  │  Prod (IaaS) │
│                │  │              │  │              │
│  VNet          │  │  App Service │  │  VNet        │
│  NSG           │  │  Plan        │  │  NSG         │
│  VM            │  │  App Service │  │  VM          │
│  MySQL         │  │  MySQL       │  │  MySQL       │
│  Public IP     │  │              │  │  Public IP   │
│                │  │              │  │              │
│  Managed by:   │  │  Managed by: │  │  Managed by: │
│  iaas/qa       │  │  paas/qa     │  │  iaas/prod   │
└────────────────┘  └──────────────┘  └──────────────┘
```

### Layer 1: Shared Resources

**Purpose**: Resources shared across all environments to reduce costs and complexity.

**Resources**:
- Azure Container Registry (ACR)
- (Future) Key Vault
- (Future) Log Analytics Workspace

**Lifecycle**: Long-lived, rarely destroyed

### Layer 2: Environment Resources

**Purpose**: Environment-specific resources with complete isolation.

**Resources per environment**:
- Virtual Network (IaaS only)
- Virtual Machine (IaaS only)
- App Service Plan + App Service (PaaS only)
- MySQL Flexible Server
- Network Security Group (IaaS only)
- Public IP (IaaS only)

**Lifecycle**: Can be destroyed and recreated independently

---

## Terraform Modules

### Module: azure-shared-infra

**Location**: `terragrunt/modules/azure-shared-infra/`

**Purpose**: Deploy shared resources (ACR)

**Resources**:
```hcl
resource "azurerm_resource_group" "shared"
resource "azurerm_container_registry" "acr"
```

**Inputs**:
| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `location` | string | Azure region | `westeurope` |
| `resource_group_name` | string | Resource group name | `terracloud-shared-rg` |
| `acr_name` | string | ACR name (globally unique) | `terracloudacr` |
| `acr_sku` | string | ACR tier | `Basic` |

**Outputs**:
| Output | Description |
|--------|-------------|
| `acr_id` | ACR resource ID |
| `acr_name` | ACR name |
| `acr_login_server` | ACR login server URL |

**Used by**: All environments

---

### Module: azure-iaas-app-service

**Location**: `terragrunt/modules/azure-iaas-app-service/`

**Purpose**: Deploy IaaS environment with VM and MySQL

**Resources**:
```hcl
resource "azurerm_resource_group" "main"
resource "azurerm_virtual_network" "main"
resource "azurerm_subnet" "main"
resource "azurerm_public_ip" "main"
resource "azurerm_network_interface" "main"
resource "azurerm_network_security_group" "main"
resource "azurerm_linux_virtual_machine" "main"
resource "azurerm_mysql_flexible_server" "main"
resource "azurerm_mysql_flexible_database" "main"
```

**Inputs**:
| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `environment` | string | Environment name | - |
| `location` | string | Azure region | `westeurope` |
| `vm_size` | string | VM SKU | `Standard_B1s` |
| `mysql_sku` | string | MySQL SKU | `B_Standard_B1s` |
| `admin_username` | string | VM admin user | `azureuser` |
| `ssh_public_key` | string | SSH public key | - |

**Outputs**:
| Output | Description |
|--------|-------------|
| `vm_id` | VM resource ID |
| `vm_public_ip` | VM public IP address |
| `vm_public_ips` | List of VM IPs (for compatibility) |
| `database_host` | MySQL FQDN |
| `database_name` | Database name |
| `database_admin_username` | MySQL admin username |

**Network Configuration**:
```
VNet: 10.0.0.0/16
├── Subnet 1: 10.0.1.0/24 (VM)
└── Subnet 2: 10.0.2.0/24 (MySQL)
```

**Used by**: `iaas/qa`, `iaas/prod`

---

### Module: azure-paas-app-service

**Location**: `terragrunt/modules/azure-paas-app-service/`

**Purpose**: Deploy PaaS environment with App Service and MySQL

**Resources**:
```hcl
resource "azurerm_resource_group" "main"
resource "azurerm_service_plan" "main"
resource "azurerm_linux_web_app" "main"
resource "azurerm_mysql_flexible_server" "main"
resource "azurerm_mysql_flexible_database" "main"
```

**Inputs**:
| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `environment` | string | Environment name | - |
| `location` | string | Azure region | `westeurope` |
| `app_service_sku` | string | App Service SKU | `B1` |
| `mysql_sku` | string | MySQL SKU | `B_Standard_B1s` |
| `acr_login_server` | string | ACR URL | - |
| `docker_image` | string | Docker image name | `app:latest` |

**Outputs**:
| Output | Description |
|--------|-------------|
| `app_service_url` | App Service URL |
| `app_service_id` | App Service resource ID |
| `database_host` | MySQL FQDN |
| `database_name` | Database name |

**Used by**: `paas/qa`, `paas/prod`

---

## Environment Strategy

### Environment Hierarchy

```
terragrunt/
├── root.hcl                    # Root configuration (backend, provider)
├── shared/
│   └── terragrunt.hcl         # Shared resources
├── iaas/
│   ├── qa/
│   │   └── terragrunt.hcl     # QA IaaS (VM + MySQL)
│   └── prod/
│       └── terragrunt.hcl     # Prod IaaS (VM + MySQL)
└── paas/
    ├── qa/
    │   └── terragrunt.hcl     # QA PaaS (App Service + MySQL)
    └── prod/
        └── terragrunt.hcl     # Prod PaaS (App Service + MySQL)
```

### Environment Characteristics

| Environment | Type | VM Size | MySQL SKU | Purpose |
|-------------|------|---------|-----------|---------|
| **QA IaaS** | IaaS | B1s (512MB) | B_Standard_B1s | Testing, integration |
| **QA PaaS** | PaaS | B1 | B_Standard_B1s | PaaS testing |
| **Prod IaaS** | IaaS | B2s (4GB) | GP_Standard_D2ds_v4 | Production workload |
| **Prod PaaS** | PaaS | P1v2 | GP_Standard_D2ds_v4 | Production PaaS |

### Terragrunt DRY Principles

**Root configuration** (`root.hcl`):
```hcl
# Backend configuration (inherited by all)
remote_state {
  backend = "azurerm"
  config = {
    resource_group_name  = "terracloud-tfstate-rg"
    storage_account_name = "terracloudtfstate"
    container_name       = "tfstate"
    key                  = "${path_relative_to_include()}/terraform.tfstate"
  }
}

# Provider configuration (inherited by all)
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
provider "azurerm" {
  features {}
}
EOF
}
```

**Environment configuration** (e.g., `iaas/qa/terragrunt.hcl`):
```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules//azure-iaas-app-service"
}

inputs = {
  environment     = "qa"
  location        = "westeurope"
  vm_size         = "Standard_B1s"
  mysql_sku       = "B_Standard_B1s"
  admin_username  = "azureuser"
  ssh_public_key  = get_env("SSH_PUBLIC_KEY", "")
}
```

**Benefits**:
- ✅ Backend configured once, used everywhere
- ✅ Provider version consistent across environments
- ✅ Easy to add new environments
- ✅ Environment-specific values in inputs

---

## Network Architecture

### IaaS Network Design

```
┌─────────────────────────────────────────────────────────┐
│  Virtual Network: terracloud-{env}-vnet                 │
│  Address Space: 10.0.0.0/16                             │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Subnet: vm-subnet                                │  │
│  │  Range: 10.0.1.0/24                               │  │
│  │                                                   │  │
│  │  ┌─────────────────────┐                         │  │
│  │  │  Virtual Machine    │                         │  │
│  │  │  Private IP: DHCP   │                         │  │
│  │  │  Public IP: Dynamic │                         │  │
│  │  └─────────────────────┘                         │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Subnet: mysql-subnet                             │  │
│  │  Range: 10.0.2.0/24                               │  │
│  │                                                   │  │
│  │  ┌─────────────────────┐                         │  │
│  │  │  MySQL Server       │                         │  │
│  │  │  Private Endpoint   │                         │  │
│  │  └─────────────────────┘                         │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  Network Security Group (NSG)                          │
│  - Allow: SSH (22), HTTP (80), HTTPS (443)            │
│  - Deny: All other inbound                            │
└─────────────────────────────────────────────────────────┘
```

### NSG Rules

**Inbound Rules** (IaaS):

| Priority | Name | Port | Source | Action |
|----------|------|------|--------|--------|
| 1001 | SSH | 22 | Specific IP | Allow |
| 1002 | HTTP | 80 | Any | Allow |
| 1003 | HTTPS | 443 | Any | Allow |
| 65000 | DenyAllInbound | Any | Any | Deny |

**MySQL Firewall**:
- Allow Azure services: Yes
- Require SSL: Yes
- Public access: Disabled (delegated subnet only)

### PaaS Network Design

App Service uses Azure backbone network:
- No VNet required
- Outbound: Via Azure backbone
- Inbound: Public endpoint with optional IP restrictions
- MySQL: Private endpoint or service endpoint

---

## Resource Naming

### Naming Convention

Format: `{project}-{environment}-{resource_type}`

Examples:
- `terracloud-qa-rg` (Resource Group)
- `terracloud-qa-vnet` (Virtual Network)
- `terracloud-qa-vm` (Virtual Machine)
- `terracloud-qa-mysql` (MySQL Server)
- `terracloudacr` (ACR - no hyphens, globally unique)

### Resource Tags

All resources are tagged with:

```hcl
tags = {
  Project     = "TerraCloud"
  Environment = var.environment
  ManagedBy   = "Terraform"
  Repository  = "terracloud-infra"
}
```

---

## State Management

### Backend Configuration

**Location**: Azure Storage Account
- **Resource Group**: `terracloud-tfstate-rg`
- **Storage Account**: `terracloudtfstate`
- **Container**: `tfstate`

**State Files**:
```
tfstate/
├── shared/terraform.tfstate
├── iaas/qa/terraform.tfstate
├── iaas/prod/terraform.tfstate
├── paas/qa/terraform.tfstate
└── paas/prod/terraform.tfstate
```

**State Locking**: Automatic with Azure Storage blob leases

### State Best Practices

✅ **Do:**
- Use remote state (Azure Storage)
- Enable state locking
- Use separate state files per environment
- Review state before destroying

❌ **Don't:**
- Store state in Git
- Share state files between environments
- Manually edit state files
- Delete state storage without backup

---

## Scaling Strategy

### Vertical Scaling (IaaS)

Change VM size in `terragrunt.hcl`:

```hcl
inputs = {
  vm_size = "Standard_B2s"  # Upgrade from B1s
}
```

Apply changes:
```bash
terragrunt apply
```

**Note**: Requires VM restart (brief downtime)

### Horizontal Scaling (IaaS)

Add VM count variable to module (future enhancement):

```hcl
variable "vm_count" {
  default = 1
}

resource "azurerm_linux_virtual_machine" "main" {
  count = var.vm_count
  # ...
}
```

### Scaling (PaaS)

App Service scales automatically or manually:
- **Auto-scale**: Based on CPU/memory metrics
- **Manual scale**: Change SKU in Terragrunt

---

## High Availability

### Current Setup

- **Single region**: West Europe
- **Single VM/App Service**: No HA
- **MySQL**: Automated backups enabled

### HA Improvements (Future)

1. **Multi-region deployment**:
   - Primary: West Europe
   - Secondary: North Europe
   - Traffic Manager for routing

2. **Load balancing**:
   - Azure Load Balancer (IaaS)
   - Traffic Manager (cross-region)

3. **Database replication**:
   - MySQL read replicas
   - Cross-region replication

---

## Disaster Recovery

### Current Backup Strategy

**MySQL**:
- Automated backups: 7 days retention
- Point-in-time restore available
- Geo-redundant backups: Optional

**VM**:
- Azure Backup: Not configured (use Terraform to recreate)
- Disk snapshots: Manual

**ACR**:
- Geo-replication: Not enabled (Basic tier)
- Image retention: Unlimited

### Recovery Procedures

**Recover MySQL**:
```bash
az mysql flexible-server restore \
  --resource-group terracloud-prod-rg \
  --name terracloud-prod-mysql-restored \
  --source-server terracloud-prod-mysql \
  --restore-time "2024-01-01T00:00:00Z"
```

**Rebuild VM**:
```bash
cd terragrunt/iaas/prod
terragrunt destroy -target=azurerm_linux_virtual_machine.main
terragrunt apply
```

---

## Cost Analysis

### Estimated Monthly Costs (USD)

**QA Environment (IaaS)**:
- VM (B1s, Linux): ~$8
- MySQL (Burstable B1s): ~$12
- Network (Public IP, egress): ~$5
- **Total**: ~$25/month

**Production Environment (IaaS)**:
- VM (B2s, Linux): ~$30
- MySQL (GP D2ds_v4): ~$150
- Network: ~$10
- **Total**: ~$190/month

**Shared Resources**:
- ACR (Basic): ~$5/month
- Storage (State): ~$1/month

**Total Infrastructure**: ~$221/month

### Cost Optimization Tips

1. **Stop QA VMs outside business hours**: Save ~60%
2. **Use Reserved Instances**: Save ~30-40% on VMs
3. **Right-size resources**: Monitor and adjust VM/MySQL sizes
4. **Use Burstable tier for non-prod databases**
5. **Enable auto-shutdown on QA VMs**

---

## Next Steps

- **Deploy application**: See [DEPLOYMENT.md](DEPLOYMENT.md)
- **Configure workflows**: See [WORKFLOWS.md](WORKFLOWS.md)
- **Troubleshooting**: See [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
