# DevPod Provider Configuration

This directory contains the DevPod provider configuration for your Kubernetes homelab cluster.

## Setup

1. **Copy provider config:**
   ```bash
   cp provider.yaml ~/.devpod/provider/kubernetes.yaml
   ```

2. **Add provider:**
   ```bash
   devpod provider add kubernetes
   ```

3. **Verify:**
   ```bash
   devpod list providers
   devpod status
   ```

## Configuration

- **Namespace**: `devpod`
- **Context**: `homelab-007`
- **Service Account**: `devpod-workspace`
- **Storage Class**: `longhorn`
- **Storage Size**: 20Gi

## Customization

Edit `provider.yaml` to change defaults:

```yaml
agent:
  driver: kubernetes
  kubernetes:
    namespace: devpod              # Namespace for workspaces
    context: homelab-007           # K8s context to use
    serviceAccount: devpod-workspace # Service account to use
    persistentVolumeSize: 20Gi       # Default PVC size
    storageClass: longhorn          # Storage class to use
```

After editing, re-add provider:
```bash
devpod provider add kubernetes
```

## Documentation

See `../devpod/README.md` for complete DevPod setup and usage documentation.
