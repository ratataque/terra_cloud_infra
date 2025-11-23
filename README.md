# TerraCloud Infrastructure

> Infrastructure as Code (Terraform + Terragrunt) and Configuration Management (Ansible) for deploying TerraCloud application on Azure

[![Infrastructure Deploy](https://github.com/ratataque/terracloud-infra/workflows/Infrastructure%20Deploy/badge.svg)](https://github.com/ratataque/terracloud-infra/actions)

## 📋 Table of Contents

- [Project Overview](#-project-overview)
- [Repository Structure](#-repository-structure)
- [Architecture](#-architecture)
- [Quick Start](#-quick-start)
- [Documentation](#-documentation)
- [Contributing](#-contributing)

---

## 🎯 Project Overview

**TerraCloud Infrastructure** is the Infrastructure as Code (IaC) repository for the TerraCloud application. This repository is **separate from the application code**, following a clean separation of concerns architecture.

### What This Repository Contains

This repository manages:

- ✅ **Terraform/Terragrunt modules** - Azure resource definitions
- ✅ **Ansible playbooks** - Application deployment automation
- ✅ **CI/CD workflows** - Infrastructure provisioning and app deployment
- ✅ **Environment configurations** - QA and Production settings

### What This Repository Does NOT Contain

Application-related code lives in a separate repository:

- ❌ Laravel application code
- ❌ Application CI/CD (build, test, push to ACR)
- ❌ Dockerfile and docker-compose

### Architecture Separation

```
┌─────────────────────────────────────┐
│   TerraCloud App Repository         │
│   (Separate repo)                    │
│                                      │
│   • Laravel Application              │
│   • Docker Configuration             │
│   • CI: Build & Push to ACR          │
└──────────────┬──────────────────────┘
               │
               │ Triggers deployment via
               │ repository_dispatch event
               ▼
┌─────────────────────────────────────┐
│   TerraCloud Infra Repository       │
│   (This repo)                        │
│                                      │
│   • Terraform/Terragrunt             │
│   • Ansible Playbooks                │
│   • CD: Deploy from ACR to VMs       │
└─────────────────────────────────────┘
```

### Technology Stack

- **IaC**: Terraform 1.5.7 + Terragrunt 0.54.0
- **Configuration Management**: Ansible 2.9+
- **Cloud Provider**: Microsoft Azure
- **CI/CD**: GitHub Actions with OIDC authentication
- **Container Registry**: Azure Container Registry (ACR)
- **Deployment Targets**: IaaS (VMs) and PaaS (App Service)

---

## 📁 Repository Structure

```
terracloud-infra/
├── docs/                           # Detailed documentation
│   ├── SETUP.md                    # Initial setup guide
│   ├── ARCHITECTURE.md             # Infrastructure architecture
│   ├── WORKFLOWS.md                # CI/CD workflows
│   ├── DEPLOYMENT.md               # Deployment guide
│   ├── ANSIBLE.md                  # Ansible playbook docs
│   └── TROUBLESHOOTING.md          # Common issues
│
├── terragrunt/
│   ├── modules/                    # Terraform modules
│   │   ├── azure-shared-infra/    # ACR, shared resources
│   │   ├── azure-iaas-app-service/# VMs, networking, MySQL
│   │   └── azure-paas-app-service/# App Service, MySQL
│   │
│   ├── shared/                     # Shared infrastructure
│   │   └── terragrunt.hcl         # ACR deployment
│   │
│   ├── iaas/                       # IaaS environments
│   │   ├── qa/terragrunt.hcl
│   │   └── prod/terragrunt.hcl
│   │
│   ├── paas/                       # PaaS environments
│   │   ├── qa/terragrunt.hcl
│   │   └── prod/terragrunt.hcl
│   │
│   ├── root.hcl                    # Root Terragrunt config
│   ├── backend.tf                  # Azure backend config
│   └── provider.tf                 # Azure provider config
│
├── ansible/
│   ├── inventories/
│   │   ├── qa.yml                  # QA inventory
│   │   └── prod.yml                # Production inventory
│   ├── playbooks/
│   │   └── deploy.yml              # Application deployment
│   └── ansible.cfg                 # Ansible configuration
│
├── .github/
│   ├── workflows/
│   │   ├── terraform-plan.yml      # PR validation
│   │   ├── infra-deploy.yml        # Infrastructure deployment
│   │   └── app-deploy.yml          # Application deployment
│   └── actions/
│       └── setup-terragrunt/       # Reusable action
│
└── README.md                       # This file
```

---

## 🏗️ Architecture

### Infrastructure Layers

```
┌─────────────────────────────────────────────────────────┐
│                    Shared Resources                     │
│  ┌────────────────────────────────────────────────┐    │
│  │  Azure Container Registry (ACR)                 │    │
│  │  - Stores all Docker images                     │    │
│  │  - Shared across all environments               │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
┌────────▼────────┐ ┌──────▼──────┐ ┌───────▼────────┐
│   QA (IaaS)     │ │  QA (PaaS)  │ │  Prod (IaaS)   │
│  ┌──────────┐   │ │ ┌─────────┐ │ │  ┌──────────┐  │
│  │    VM    │   │ │ │App Svc. │ │ │  │    VM    │  │
│  │ + Docker │   │ │ │(Docker) │ │ │  │ + Docker │  │
│  └──────────┘   │ │ └─────────┘ │ │  └──────────┘  │
│  ┌──────────┐   │ │ ┌─────────┐ │ │  ┌──────────┐  │
│  │  MySQL   │   │ │ │  MySQL  │ │ │  │  MySQL   │  │
│  └──────────┘   │ │ └─────────┘ │ │  └──────────┘  │
└─────────────────┘ └─────────────┘ └────────────────┘
```

### Key Features

- **Shared ACR**: Single container registry for all environments
- **Dual Deployment**: Support for both IaaS (VMs) and PaaS (App Service)
- **Environment Isolation**: Separate QA and Production with independent resources
- **Automated Deployment**: Ansible playbooks with health checks and rollback
- **Immutable Infrastructure**: Deploy same container image across environments

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture documentation.

---

## 🚀 Quick Start

### Prerequisites

- **Azure CLI** 2.50+ (authenticated)
- **Terraform** 1.5.7+
- **Terragrunt** 0.54.0+
- **Ansible** 2.9+
- **GitHub CLI** (optional, for workflow triggers)

### 1. Clone Repository

```bash
git clone https://github.com/ratataque/terracloud-infra.git
cd terracloud-infra
```

### 2. Configure Azure OIDC

```bash
# Set your Azure subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Run setup script (see docs/SETUP.md for details)
```

### 3. Deploy Shared Infrastructure

```bash
cd terragrunt/shared
terragrunt init
terragrunt apply
```

### 4. Deploy QA Environment

```bash
cd terragrunt/iaas/qa
terragrunt init
terragrunt apply
```

### 5. Deploy Application

```bash
cd ansible

# Set environment variables (see docs/DEPLOYMENT.md)
export IMAGE_TAG="1.0.0"
export ENV_NAME="qa"

# Deploy via Ansible
ansible-playbook -i inventories/qa.yml playbooks/deploy.yml
```

**For complete setup instructions, see [docs/SETUP.md](docs/SETUP.md)**

---

## 📚 Documentation

### Core Documentation

| Document | Description |
|----------|-------------|
| [SETUP.md](docs/SETUP.md) | Complete initial setup guide with Azure OIDC, GitHub secrets, and first deployment |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Infrastructure architecture, modules, and resource organization |
| [WORKFLOWS.md](docs/WORKFLOWS.md) | CI/CD workflows explanation and usage |
| [DEPLOYMENT.md](docs/DEPLOYMENT.md) | Application deployment guide (manual and automated) |
| [ANSIBLE.md](docs/ANSIBLE.md) | Ansible playbook structure and customization |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and solutions |

### Quick Reference

**Deploy infrastructure:**
```bash
cd terragrunt/<iaas|paas>/<qa|prod>
terragrunt apply
```

**Deploy application:**
```bash
# Via GitHub Actions
gh workflow run app-deploy.yml -f environment=qa -f image_tag=1.2.3

# Via Ansible
cd ansible
ansible-playbook -i inventories/qa.yml playbooks/deploy.yml
```

**View outputs:**
```bash
cd terragrunt/iaas/qa
terragrunt output
```

---

## 🔄 Deployment Workflow

### End-to-End Release Flow

```
1. Developer pushes to app repo (terracloud)
   ↓
2. App CI: Build image → Tag v1.2.3 → Push to ACR
   ↓
3. App CI: Trigger infra repo deployment (optional)
   ↓
4. Ansible: Deploy v1.2.3 to QA
   - Pull image from ACR
   - Stop old container
   - Start new container
   - Health checks
   - Run migrations
   ↓
5. QA Testing & Approval
   ↓
6. Ansible: Promote v1.2.3 to Production
   - Same image, no rebuild ✅
   - Requires approval
```

See [docs/WORKFLOWS.md](docs/WORKFLOWS.md) for detailed workflow documentation.

---

## 🔐 Security

- **OIDC Authentication**: No long-lived secrets in GitHub Actions
- **Managed Identities**: Azure resources use managed identities
- **Environment Protection**: GitHub Environments with approval workflows
- **SSH Key-Based Auth**: Ansible connects to VMs via SSH keys
- **Network Security**: NSGs restrict access to VMs and databases
- **Secret Management**: Sensitive values in GitHub Environment secrets

See [docs/SETUP.md#security-configuration](docs/SETUP.md#security-configuration) for security setup.

---

## 🛠️ Development

### Making Infrastructure Changes

1. **Create feature branch**
   ```bash
   git checkout -b feature/add-key-vault
   ```

2. **Modify Terraform modules**
   ```bash
   vim terragrunt/modules/azure-shared-infra/main.tf
   ```

3. **Test locally**
   ```bash
   cd terragrunt/shared
   terragrunt plan
   ```

4. **Create Pull Request**
   ```bash
   git add .
   git commit -m "feat: add Azure Key Vault for secrets"
   git push origin feature/add-key-vault
   ```

5. **Review Terraform plan** in PR comments

6. **Merge to deploy** infrastructure changes

### Testing Changes

- **Local testing**: Use `terragrunt plan` before pushing
- **PR validation**: GitHub Actions runs plan on all affected environments
- **Selective apply**: Deploy to QA first, then Production

---

## 💰 Cost Optimization

- **Shared ACR**: Single registry reduces costs
- **Stop VMs**: Shutdown QA VMs outside business hours
- **Right-sizing**: Use B1s VMs for QA (512MB RAM optimized)
- **Flexible MySQL**: Use Burstable tier for non-production
- **Auto-shutdown**: Configure Azure auto-shutdown policies

---

## 🤝 Contributing

### Workflow

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test with `terragrunt plan`
5. Commit (`git commit -m 'feat: add amazing feature'`)
6. Push to branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Commit Convention

Follow conventional commits:

- `feat:` - New features or infrastructure additions
- `fix:` - Bug fixes or infrastructure corrections
- `docs:` - Documentation updates
- `refactor:` - Code refactoring without behavior changes
- `chore:` - Maintenance tasks

---

## 📞 Support

- **Application Issues**: See [terracloud repository](https://github.com/ratataque/terracloud)
- **Infrastructure Issues**: Create an issue in this repository
- **Documentation**: Check [docs/](docs/) folder

---

## 📄 License

[Add your license here]

---

## 🔗 Related Repositories

- **Application Repository**: [ratataque/terracloud](https://github.com/ratataque/terracloud)
- **Azure Documentation**: [Azure App Service](https://docs.microsoft.com/azure/app-service/)
- **Terraform Azure Provider**: [hashicorp/azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
