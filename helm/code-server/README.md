# Development Environments

This directory contains Helm values configurations for deploying VS Code dev environments in Kubernetes using [code-server](https://github.com/coder/code-server).

## Overview

- **IDE**: code-server (VS Code in browser)
- **Access**: Browser-based at `https://dev.home.com` (and project-specific URLs)
- **Storage**: Longhorn persistent volumes (workspace + shared storage)
- **Namespace**: `devenv`

## Architecture

```
Browser (https://dev.home.com)
    ↓
Traefik Ingress (TLS via cert-manager)
    ↓
code-server Pod
    ├─ Workspace PVC (project-specific code)
    └─ Shared PVC (common tools, caches)
    ↓
Longhorn Storage
```

## Prerequisites

1. Helm repository added:
   ```bash
   helm repo add coder https://helm.coder.com/v2
   helm repo update
   ```

2. Namespace and shared storage created:
   ```bash
   kubectl create namespace devenv
   helm upgrade --install code-server . -n devenv
   ```

3. Each Ingress uses a hostname-specific TLS Secret. Its cert-manager
   annotation creates and renews the corresponding Certificate automatically.
   Never reuse one Secret name for Ingresses with different host lists.

## Deployment

### Main Dev Environment

Deploy the primary dev environment accessible at `https://dev.home.com`:

```bash
helm install code-server-main coder/code-server \
  -n devenv \
  -f values-main.yaml
```

**Configuration**:
- **URL**: https://dev.home.com
- **Workspace Storage**: 20Gi
- **Shared Storage**: 50Gi (mounted at `/mnt/shared`)
- **Resources**: 500m-2000m CPU, 1-4Gi memory

### Project-Specific Environment

Create a new dev environment for a specific project:

1. **Copy template**:
   ```bash
   cp values-project1.yaml values-myproject.yaml
   ```

2. **Edit configuration**:
   - Change `host:` under `ingress.hosts` (e.g., `myproject.home.com`)
   - Update `PROJECT_NAME` env var
   - Adjust `persistence.size` if needed
   - Update TLS hosts to match

3. **Add DNS entry** in `../../helm/pihole/values.yaml`:
   ```yaml
   customDnsEntries:
     - address: 192.168.1.50
       domain: myproject.home.com
   ```

4. **Update Pi-hole**:
   ```bash
   helm upgrade pihole mojo2600/pihole -n pihole -f ../../helm/pihole/values.yaml
   ```

5. **Deploy**:
   ```bash
   helm install code-server-myproject coder/code-server \
     -n devenv \
     -f values-myproject.yaml
   ```

## Management

### List Deployments

```bash
kubectl get deployments -n devenv
kubectl get pods -n devenv
kubectl get pvc -n devenv
kubectl get ingress -n devenv
```

### Access Dev Environment

**Via Browser**:
- Main: https://dev.home.com
- Projects: https://project1.home.com, https://myproject.home.com

**Via kubectl exec**:
```bash
# Interactive shell
kubectl exec -it -n devenv deployment/code-server-main -- bash

# Run command
kubectl exec -n devenv deployment/code-server-main -- git status
```

**Via Port-Forward** (local access):
```bash
kubectl port-forward -n devenv svc/code-server-main 8080:8080
# Then access: http://localhost:8080
```

### View Logs

```bash
kubectl logs -n devenv deployment/code-server-main
kubectl logs -n devenv deployment/code-server-main -f  # Follow logs
```

### Update Environment

```bash
# Edit values file, then:
helm upgrade code-server-main coder/code-server \
  -n devenv \
  -f values-main.yaml

# Check rollout status
kubectl rollout status deployment/code-server-main -n devenv
```

### Delete Environment

```bash
# Delete deployment (PVC is retained)
helm uninstall code-server-project1 -n devenv

# Delete PVC if you want to remove data permanently
kubectl delete pvc -n devenv <pvc-name>
```

## Storage

### Layout

```
/home/coder/                    # Workspace PVC (per environment)
├── .config/                    # code-server config
├── .local/                     # Extensions, settings
└── workspace/                  # Your code here

/mnt/shared/                    # Shared PVC (all environments)
├── tools/                      # Common binaries, SDKs
├── cache/                      # Package manager caches
│   ├── npm/
│   ├── pip/
│   └── cargo/
├── scripts/                    # Utility scripts
└── datasets/                   # Large shared files
```

### Check Storage Usage

```bash
kubectl exec -n devenv deployment/code-server-main -- df -h
kubectl exec -n devenv deployment/code-server-main -- du -sh /home/coder/*
kubectl exec -n devenv deployment/code-server-main -- du -sh /mnt/shared/*
```

### Expand PVC

If you need more storage:

```bash
kubectl edit pvc <pvc-name> -n devenv
# Change storage size, save
# Longhorn will automatically expand the volume
```

## Customization

### Password Protection

Edit values file and change authentication:

```yaml
extraArgs:
  - --auth
  - password

extraEnvVars:
  - name: PASSWORD
    value: "your-secure-password"
```

### Install Additional Tools

```bash
kubectl exec -it -n devenv deployment/code-server-main -- bash

# Inside the container
sudo apt-get update
sudo apt-get install -y <package-name>

# Or install to shared storage for all environments
cd /mnt/shared/tools
wget <tool-url>
chmod +x <tool>
```

### Pre-install VS Code Extensions

```bash
kubectl exec -n devenv deployment/code-server-main -- \
  code-server --install-extension ms-python.python

# Or via script in /mnt/shared/scripts/install-extensions.sh
```

### Adjust Resources

Edit values file:

```yaml
resources:
  limits:
    cpu: 4000m      # Increase CPU limit
    memory: 8Gi     # Increase memory limit
  requests:
    cpu: 1000m
    memory: 2Gi
```

## Troubleshooting

### Can't Access via Browser

1. **Check pod status**:
   ```bash
   kubectl get pods -n devenv
   kubectl describe pod <pod-name> -n devenv
   ```

2. **Check ingress**:
   ```bash
   kubectl get ingress -n devenv
   kubectl describe ingress <ingress-name> -n devenv
   ```

3. **Check DNS**:
   ```bash
   nslookup dev.home.com 192.168.1.51
   ```

4. **Check logs**:
   ```bash
   kubectl logs -n devenv deployment/code-server-main
   ```

### PVC Not Mounting

1. **Check PVC status**:
   ```bash
   kubectl get pvc -n devenv
   ```

2. **Check Longhorn**:
   - Navigate to https://longhorn.home.com
   - Check volume status

3. **Check events**:
   ```bash
   kubectl describe pod <pod-name> -n devenv
   ```

### Shared Storage Not Accessible

```bash
# Verify PVC exists
kubectl get pvc devenv-shared -n devenv

# Verify mount in pod
kubectl exec -n devenv deployment/code-server-main -- mount | grep shared
kubectl exec -n devenv deployment/code-server-main -- ls -la /mnt/shared
```

### Pod Won't Schedule

Check node resources:
```bash
kubectl describe node
kubectl top node
```

## Quick Reference

### Common Commands

```bash
# Deploy main environment
helm install code-server-main coder/code-server -n devenv -f values-main.yaml

# Deploy project environment
helm install code-server-project1 coder/code-server -n devenv -f values-project1.yaml

# Update environment
helm upgrade code-server-main coder/code-server -n devenv -f values-main.yaml

# Delete environment
helm uninstall code-server-main -n devenv

# Access shell
kubectl exec -it -n devenv deployment/code-server-main -- bash

# View logs
kubectl logs -n devenv deployment/code-server-main -f

# Port-forward
kubectl port-forward -n devenv svc/code-server-main 8080:8080
```

### Storage Sizes

| Environment | Workspace PVC | Shared PVC | Total |
|-------------|---------------|------------|-------|
| Main | 20Gi | 50Gi | 70Gi |
| Project | 10Gi | - | 10Gi |

Shared PVC is created once and reused by all environments.

## Next Steps

1. **Install common tools** in `/mnt/shared/tools`
2. **Setup git credentials** in workspace
3. **Install VS Code extensions** you frequently use
4. **Configure dotfiles** (.bashrc, .vimrc, etc.)
5. **Create project environments** as needed
