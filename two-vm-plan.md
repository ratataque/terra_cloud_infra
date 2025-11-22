# Two-VM IaaS Architecture Plan

## Overview
Separate database and application into two VMs for better isolation and resource management.

## Architecture
```
VM1 (App VM - B1ls):
  - Traefik (reverse proxy)
  - App container
  - Connects to DB VM

VM2 (DB VM - B1ls):
  - MariaDB (lighter than MySQL)
  - Private network only
  - No public IP
```

## Changes Required

### 1. Terraform Module Changes (`modules/azure-iaas-app-service/`)

#### A. `variables.tf`
- Add `db_vm_size` variable (default: "Standard_B1ls")
- Add `db_vm_count` variable (default: 1)
- Keep existing `vm_size` and `vm_count` for app VMs

#### B. `main.tf`
- Create separate subnet for database (10.0.2.0/24)
- Create DB NSG (allow MySQL 3306 only from app subnet)
- Create DB VM resource (no public IP)
- Modify app VM to remove MySQL container
- Update docker-compose to point to DB VM private IP

#### C. New files
- `cloud-init-db.yaml` - Installs MariaDB (lightweight MySQL)
- `cloud-init-app.yaml` - App + Traefik only (no MySQL)

### 2. Custom Image Updates

Need TWO custom images:
- `ubuntu2204-docker-mariadb-image` - DB VM with Docker + MariaDB
- `ubuntu2204-docker-image` - App VM with Docker (already exists)

### 3. Network Configuration

```
VNet: 10.0.0.0/16
  ├─ app-subnet: 10.0.1.0/24 (App VMs + Traefik)
  └─ db-subnet: 10.0.2.0/24 (DB VMs only)

NSG Rules:
  App NSG:
    - Allow 80/443 from Internet
    - Allow 22 from your IP
    - Allow 3306 outbound to db-subnet
  
  DB NSG:
    - Allow 3306 from app-subnet only
    - Allow 22 from app-subnet only (for management)
    - Deny all else
```

### 4. Docker Compose Changes

**App VM** (`docker-compose-app.yml`):
```yaml
services:
  traefik:
    image: traefik:v3.0
    ports:
      - "80:80"
    # ... traefik config

  app:
    image: acr.azurecr.io/app:latest
    environment:
      - DB_HOST=10.0.2.4  # DB VM private IP
      - DB_PORT=3306
    labels:
      - "traefik.enable=true"
```

**DB VM** (`docker-compose-db.yml`):
```yaml
services:
  mariadb:
    image: mariadb:10.11-jammy  # Lighter than mysql:8.0
    environment:
      - MARIADB_ROOT_PASSWORD=${ROOT_PASS}
      - MARIADB_DATABASE=${DB_NAME}
      - MARIADB_USER=${DB_USER}
      - MARIADB_PASSWORD=${DB_PASS}
    volumes:
      - db_data:/var/lib/mysql
    command: >
      --max-connections=20
      --innodb-buffer-pool-size=64M
      --innodb-log-file-size=16M
    restart: unless-stopped
```

### 5. Implementation Steps

1. **Update Terraform module**
   - Add DB subnet + NSG
   - Add DB VM resource
   - Split cloud-init scripts
   - Pass DB VM private IP to app cloud-init

2. **Create DB custom image**
   - Deploy temp VM with Docker + MariaDB
   - Clean cloud-init
   - Capture image

3. **Update environment configs**
   - qa/terragrunt.hcl - enable 2 VMs
   - prod/terragrunt.hcl - enable 2 VMs

4. **Test deployment**
   - Deploy QA first
   - Verify app can connect to DB VM
   - Run migrations
   - Deploy Prod

### 6. Benefits

✅ Better isolation (DB not exposed to internet)
✅ Independent scaling (can upgrade DB VM separately)
✅ MariaDB uses ~50% less memory than MySQL 8.0
✅ Can take DB snapshots independently
✅ Security: DB only accessible from app subnet

### 7. Estimated Resource Usage

**App VM (B1ls - 512MB)**:
- Traefik: ~50MB
- App: ~200MB
- System: ~100MB
- **Total: ~350MB** ✅

**DB VM (B1ls - 512MB)**:
- MariaDB (tuned): ~150MB
- System: ~100MB
- **Total: ~250MB** ✅

### 8. Cost Impact

- Current: 1 VM × €3.14/month = €3.14/month
- New: 2 VMs × €3.14/month = **€6.28/month** (+€3.14)

QA + Prod total: **€12.56/month** (~$13.50 USD)

