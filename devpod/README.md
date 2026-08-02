# DevPod Development Environments

DevPod provides remote development environments on your Kubernetes homelab cluster. Unlike code-server (web-based), DevPod runs client-side and creates dynamic workspaces with full IDE support.

## Overview

- **IDE**: VS Code Desktop (full-featured, local client)
- **Access**: SSH tunneling from local machine to Kubernetes pods
- **Storage**: Longhorn persistent volumes (20Gi per workspace)
- **Namespace**: `devpod`

## Architecture

```
Local Machine
    ↓
DevPod CLI
    ↓
Kubernetes Cluster (devpod namespace)
    ↓
Workspace Pod
    ├─ Workspace PVC (20Gi Longhorn)
    ├─ Development Tools (Docker, Node, Python)
    └─ VS Code Server
```

## Access Methods

### 1. VS Code Desktop (Primary)

**Setup:**
```bash
# Install VS Code (if not already installed)
# https://code.visualstudio.com/

# Install SSH extension
code --install-extension ms-vscode-remote.remote-ssh
```

**Usage:**
```bash
# Create new workspace from current directory (opens VS Code automatically)
devpod up --id devpod-primary . --ide vscode

# Create new workspace from specific directory
devpod up --id my-workspace /path/to/project --ide vscode

# Reconnect to existing workspace
devpod up devpod-primary
```

**VS Code automatically:**
- Connects to workspace pod
- Installs VS Code extensions from devcontainer.json
- Sets up SSH tunneling
- Provides full IDE experience (debugging, IntelliSense, Git integration)

### 2. SSH (Alternative)

**Setup:** SSH is automatically configured by DevPod. No manual setup required.

**Usage:**
```bash
# Direct SSH access
ssh devpod-primary.devpod

# Or use DevPod wrapper
devpod ssh devpod-primary
```

### 3. Port Forwarding

Forward local ports to workspace services:

```bash
# Forward single port
devpod ssh devpod-primary -L 3000:localhost:3000

# Forward multiple ports
devpod ssh devpod-primary -L 3000:localhost:3000 -L 8080:localhost:8080

# Then access services
# http://localhost:3000
# http://localhost:8080
```

### 4. kubectl exec (Debugging)

```bash
# List DevPod pods
kubectl get pods -n devpod

# Access pod directly
kubectl exec -it -n devpod <pod-name> -- bash

# View logs
kubectl logs -n devpod <pod-name> -f
```

## Prerequisites

### Cluster Setup (One-time)

1. **Create namespace:**
   ```bash
   kubectl create namespace devpod
   ```

2. **Configure pod security:**
   ```bash
   kubectl label namespace devpod pod-security.kubernetes.io/enforce=privileged
   kubectl label namespace devpod pod-security.kubernetes.io/audit=privileged
   kubectl label namespace devpod pod-security.kubernetes.io/warn=privileged
   ```

3. **Create RBAC permissions:**
   ```bash
   kubectl apply -f ../manifests/devpod-rbac.yaml
   ```

4. **Copy TLS certificate (optional, not required for DevPod):**
   ```bash
   kubectl get secret home.com-tls -n heimdall -o yaml | \
     sed 's/namespace: heimdall/namespace: devpod/' | \
     kubectl apply -f -
   ```

### Client Setup (Per Developer)

1. **Install DevPod CLI:**
   ```bash
   # macOS (Intel/Apple Silicon)
   brew install devpod

   # Or download directly
   curl -L -o devpod "https://github.com/loft-sh/devpod/releases/latest/download/devpod-darwin-arm64" && \
     chmod +x devpod && \
     sudo mv devpod /usr/local/bin/devpod
   ```

2. **Install VS Code + SSH extension:**
   ```bash
   # Install VS Code: https://code.visualstudio.com/
   
   # Install SSH extension
   code --install-extension ms-vscode-remote.remote-ssh
   ```

3. **Configure Kubernetes provider:**
    ```bash
    # Copy provider config to ~/.devpod/provider/kubernetes.yaml
    # See provider config section below
    cp ./devpod/provider.yaml ~/.devpod/provider/kubernetes.yaml
    
    # Add provider
    devpod provider add kubernetes
    ```

⚠️ **Important**: 
- Use Ubuntu 22.04 or earlier in devcontainer.json
- DevPod doesn't support Ubuntu 24.04 (Noble) or newer
- Docker-in-Docker feature causes build failures - use pre-configured image instead
- Two configurations available:
  - `devcontainer.json` - Basic setup (Node.js, Python) ✅ Reliable
  - `devcontainer-with-docker.json` - Includes Docker ⚠️ May fail
- See `.devcontainer/README.md` for detailed configuration options

## Provider Configuration

Create `~/.devpod/provider/kubernetes.yaml`:

```yaml
name: kubernetes
executable: devpod
version: v0.5.0
description: "Kubernetes provider for homelab cluster"

agent:
  driver: kubernetes
  kubernetes:
    namespace: devpod
    context: homelab-007
    serviceAccount: devpod-workspace
    persistentVolumeSize: 20Gi
    storageClass: longhorn
```

**Verify configuration:**
```bash
# List providers
devpod list providers

# Check status
devpod status
```

## Creating Workspaces

### Choose Configuration

Two devcontainer configurations are available:

| Configuration | Includes | Docker | Reliability | Use Case |
|--------------|---------|--------|--------------|-----------|
| `devcontainer.json` | Node.js, Python | ❌ No | ✅ High | Basic development |
| `devcontainer-with-docker.json` | Node.js, Python, Docker | ✅ Yes | ⚠️ Medium | Containerized development |

**Recommendation:** Start with `devcontainer.json` for reliable setup. Use Docker-in-Docker config only if you specifically need Docker inside your workspace.

### Basic Workspace (No Docker)

**Create with default configuration:**
```bash
# Uses .devcontainer/devcontainer.json
devpod up --id devpod-primary . --ide vscode
```

```bash
# Create from current directory (uses directory name as workspace name)
devpod up . --ide vscode

# Create with custom workspace name
devpod up --id my-workspace . --ide vscode

# Create with custom devcontainer
devpod up --id my-workspace . --ide vscode --devcontainer-path .devcontainer/devcontainer.json

# Create from different directory
devpod up --id project-workspace /path/to/project --ide vscode
```

### Workspace With Docker

**If you need Docker inside your workspace**, use the Docker-in-Docker configuration:

```bash
# Uses .devcontainer/devcontainer-with-docker.json
devpod up --id devpod-docker . --ide vscode --devcontainer-path .devcontainer/devcontainer-with-docker.json
```

⚠️ **Note:** Docker-in-Docker may still fail due to network issues. If it fails, install Docker manually after workspace creation:

```bash
# Access workspace
devpod ssh devpod-docker

# Install Docker manually
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
```

### Default Configuration (Recommended)

**For most reliable experience**, use the basic configuration without Docker:

```bash
# Uses .devcontainer/devcontainer.json (no Docker)
devpod up --id devpod-primary . --ide vscode
```

### Workspace Configuration

Edit `.devcontainer/devcontainer.json` to customize:

```json
{
  "name": "my-workspace",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  
  "customizations": {
    "vscode": {
      "extensions": [
        "eamodio.gitlens",
        "ms-python.python"
      ]
    },
    "devpod": {
      "persistentVolumeSize": "20Gi",
      "storageClass": "longhorn"
    }
  },
  
  "features": {
    "ghcr.io/devcontainers/features/node:1": {},
    "ghcr.io/devcontainers/features/python:1": {}
  },
  
  "forwardPorts": [3000, 8080]
}
```

## Workspace Management

### List Workspaces

```bash
devpod list
```

Output:
```
NAME             UID                                PROVIDER     STATUS     CREATED
devpod-primary   550e8400-e29b-41d4-a716-446655440000  kubernetes  Running     2 days ago
my-project       660f9501-f39c-51e5-b827-557665551111  kubernetes  Stopped     1 week ago
```

### Stop Workspace

Stops the pod but keeps data (PVC retained):

```bash
devpod stop devpod-primary
```

### Delete Workspace

Deletes pod and PVC (data is lost):

```bash
# Interactive confirmation
devpod delete devpod-primary

# Force delete without confirmation
devpod delete devpod-primary --force
```

### Restart Workspace

```bash
# Stops and starts workspace
devpod stop devpod-primary
devpod up devpod-primary
```

## Storage

### Storage Class

DevPod uses the `longhorn` storage class, same as other services in your homelab:
- **Provisioner**: Longhorn distributed storage
- **Replicas**: 1 (single-node cluster)
- **Size**: 20Gi per workspace (configurable)
- **Expansion**: Supported (can increase size)

### Monitor Storage

```bash
# Check PVC usage in devpod namespace
kubectl get pvc -n devpod

# Check Longhorn volumes
kubectl get volumes.longhorn.io -n longhorn-system

# Check pod storage usage
kubectl exec -n devpod <pod-name> -- df -h

# Check workspace disk usage
kubectl exec -n devpod <pod-name> -- du -sh /workspace/*
```

### Expand PVC

If you need more storage:

```bash
# Edit PVC and increase size
kubectl edit pvc <pvc-name> -n devpod

# Change storage: 20Gi -> 40Gi
# Longhorn automatically expands
```

### Backup Workspace Data

```bash
# Sync workspace to local
rsync -avz --progress \
  kubectl exec -n devpod <pod-name> -- tar -czf - /workspace \
  | tar -xzf - -C ./backup

# Or copy specific directories
kubectl cp devpod/<pod-name>:/workspace/my-project ./my-project-backup
```

## Troubleshooting

### Workspace Won't Start

**Check pod status:**
```bash
kubectl get pods -n devpod
kubectl describe pod <pod-name> -n devpod
```

**Check PVC status:**
```bash
kubectl get pvc -n devpod
kubectl describe pvc <pvc-name> -n devpod
```

**Check Longhorn:**
```bash
kubectl get volumes.longhorn.io -n longhorn-system
# Visit: https://longhorn.home.com
```

### VS Code Can't Connect

**1. Verify workspace is running:**
```bash
devpod list
kubectl get pods -n devpod
```

**2. Reconnect:**
```bash
devpod up devpod-primary
```

**3. Check SSH:**
```bash
ssh devpod-primary.devpod
```

**4. Check VS Code extension:**
```bash
code --list-extensions | grep remote-ssh
```

### Permission Errors

DevPod needs privileged pods for some features. Verify namespace labels:

```bash
kubectl get namespace devpod -o yaml | grep -A 5 labels
```

Should show:
```yaml
labels:
  pod-security.kubernetes.io/enforce: privileged
  pod-security.kubernetes.io/audit: privileged
  pod-security.kubernetes.io/warn: privileged
```

### Out of Storage

**Check disk usage:**
```bash
kubectl exec -n devpod <pod-name> -- df -h
```

**Clean up:**
```bash
# Remove unused workspaces
devpod delete old-workspace

# Clean workspace caches
kubectl exec -n devpod <pod-name> -- rm -rf /tmp/*
kubectl exec -n devpod <pod-name> -- rm -rf ~/.cache/*
```

## Advanced Features

### Docker-in-Docker

Your devcontainer includes Docker-in-Docker for containerized development:

```bash
# Access workspace
devpod up devpod-primary

# Inside workspace, Docker is available
docker run hello-world
docker build -t myapp .
docker-compose up
```

### Multiple Workspaces

Create separate workspaces for different projects:

```bash
# Backend workspace
devpod up --id backend-api ./backend --ide vscode

# Frontend workspace
devpod up --id frontend-web ./frontend --ide vscode

# Database workspace
devpod up --id db-scripts ./db-scripts --ide vscode
```

### Git Integration

VS Code automatically configures Git in workspaces:

```bash
# Inside workspace
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
```

## Comparison with code-server

| Feature | DevPod | code-server |
|----------|----------|-------------|
| **IDE** | VS Code Desktop | VS Code in Browser |
| **Access** | SSH + VS Code Client | Web URL |
| **Performance** | Local IDE, remote workspace | Everything in browser |
| **Offline** | Limited (needs connection) | Limited (needs connection) |
| **Extensions** | Full VS Code marketplace | Some limitations |
| **Setup** | Install DevPod CLI | Kubernetes deployment |
| **Use Case** | Daily development | Quick access, testing |

## Quick Reference

### Common Commands

```bash
# Create workspace from current directory
devpod up . --ide vscode

# Create workspace from different directory
devpod up --id my-workspace /path/to/project --ide vscode

# List workspaces
devpod list

# Stop workspace
devpod stop my-workspace

# Delete workspace
devpod delete my-workspace

# SSH access
ssh my-workspace.devpod

# Port forwarding
devpod ssh my-workspace -L 3000:localhost:3000

# View logs
kubectl logs -n devpod <pod-name> -f

# Check storage
kubectl get pvc -n devpod
```

### Workspace Locations

| Resource | Location |
|----------|----------|
| Namespace | `devpod` |
| PVCs | `devpod` namespace |
| Pods | `devpod` namespace |
| Provider Config | `~/.devpod/provider/kubernetes.yaml` |
| Workspace Config | `.devcontainer/devcontainer.json` |

## Best Practices

1. **One workspace per project**: Keeps environments isolated and focused
2. **Commit .devcontainer.json**: Ensures reproducible development environments
3. **Use features**: Pre-built features (Node, Python, Docker) save setup time
4. **Stop unused workspaces**: Saves cluster resources
5. **Delete unused workspaces**: Free up storage
6. **Monitor storage**: Check Longhorn dashboard regularly
7. **Backup important data**: Sync critical code to git or backup locally

## Documentation

- [DevPod Official Docs](https://devpod.sh/docs)
- [DevPod CLI Reference](https://devpod.sh/docs/cli)
- [DevContainers Spec](https://containers.dev/)
- [Longhorn Storage Docs](https://longhorn.io/docs/latest/)

## Troubleshooting

### Unsupported Distribution Version Error

**Error:**
```
Unsupported distribution version 'noble'. To resolve, either: (1) set feature option '"moby": false', or (2) choose a compatible OS distribution
```

**Cause:** DevPod doesn't support Ubuntu 24.04 (Noble) or newer.

**Solutions:**

**Option 1: Use Ubuntu 22.04 (Recommended)**
```json
// In .devcontainer/devcontainer.json
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu-22.04",
  ...
}
```

**Option 2: Disable build system**
```json
// In .devcontainer/devcontainer.json
{
  "customizations": {
    "devpod": {
      "moby": false
    }
  },
  ...
}
```

**Option 3: Use Debian**
```json
{
  "image": "mcr.microsoft.com/devcontainers/base:debian-12",
  ...
}
```

**Supported distributions:** bookworm (Debian 12), buster (Debian 10), bullseye (Debian 11), bionic (Ubuntu 18.04), focal (Ubuntu 20.04), jammy (Ubuntu 22.04)

### Workspace Won't Start

1. Check DevPod status: `devpod status`
2. Check Kubernetes logs: `kubectl logs -n devpod <pod-name>`
3. Check Longhorn volume status: https://longhorn.home.com
4. Review DevPod troubleshooting: https://devpod.sh/docs/developing-in-workspaces/troubleshooting
