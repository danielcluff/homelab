# DevContainer Configuration Files

This directory contains DevPod development environment configurations.

## Available Configurations

### devcontainer.json (Default)
**Purpose:** Basic development environment with Node.js and Python
**Image:** Ubuntu 22.04
**Features:** Node.js, Python
**Docker:** Not included (to avoid build failures)

**Use when:**
- You need basic Node.js and Python development
- You want a simple, reliable workspace setup
- You don't need Docker inside the workspace

**Create workspace:**
```bash
devpod up --id devpod-primary . --ide vscode --devcontainer-path .devcontainer/devcontainer.json
```

---

### devcontainer-with-docker.json (Alternative)
**Purpose:** Development environment with Docker-in-Docker support
**Image:** Ubuntu 22.04 with Docker pre-installed
**Features:** Node.js, Python, Docker
**Docker:** Pre-installed in base image (no build required)

**Use when:**
- You need Docker inside the workspace (e.g., building containers)
- You're doing containerized development
- You need to test Docker images locally

**Create workspace:**
```bash
devpod up --id devpod-docker . --ide vscode --devcontainer-path .devcontainer/devcontainer-with-docker.json
```

⚠️ **Note:** This configuration uses a pre-built Docker image to avoid build failures. If you still see issues, use the basic `devcontainer.json` instead.

---

## Choosing a Configuration

| Configuration | Docker | Build Complexity | Reliability |
|--------------|--------|-------------------|-------------|
| devcontainer.json | No (manual install) | Low | ✅ High |
| devcontainer-with-docker.json | Yes (pre-installed) | Medium | ⚠️ Medium |

---

## Manual Docker Installation

If you chose the basic configuration but need Docker later, install it inside the workspace:

```bash
# After workspace is created
devpod ssh devpod-primary

# Inside workspace
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Verify installation
docker --version
```

---

## Customizing Configurations

You can copy and modify either file to fit your needs:

### Change Image
```json
{
  "image": "mcr.microsoft.com/devcontainers/base:debian-12",
  ...
}
```

Supported base images:
- Ubuntu: `ubuntu-22.04`, `ubuntu-20.04`, `ubuntu-18.04`
- Debian: `debian-12`, `debian-11`, `debian-10`

### Add Features
```json
{
  "features": {
    "ghcr.io/devcontainers/features/git:1": {},
    "ghcr.io/devcontainers/features/go:1": {},
    "ghcr.io/devcontainers/features/rust:1": {}
  }
}
```

Available features: https://containers.dev/features

### Add VS Code Extensions
```json
{
  "customizations": {
    "vscode": {
      "extensions": [
        "eamodio.gitlens",
        "ms-python.python",
        "ms-vscode.go",
        "rust-lang.rust-analyzer"
      ]
    }
  }
}
```

### Add Environment Variables
```json
{
  "remoteEnv": {
    "NODE_ENV": "development",
    "DATABASE_URL": "postgresql://...",
    "API_KEY": "your-key-here"
  }
}
```

---

## Troubleshooting

### Build Failures

If you see build failures:

1. **Use the basic configuration:**
   ```bash
   devpod up --id workspace-name . --ide vscode --devcontainer-path .devcontainer/devcontainer.json
   ```

2. **Disable features:**
   Remove complex features from `devcontainer.json` and add them manually after workspace creation.

3. **Use different base image:**
   Try Debian instead of Ubuntu:
   ```json
   {
     "image": "mcr.microsoft.com/devcontainers/base:debian-12"
   }
   ```

### Network Issues

If you see "Connection reset by peer" errors:

1. **Try with --debug flag:**
   ```bash
   devpod up --id workspace-name . --ide vscode --debug
   ```

2. **Check cluster connectivity:**
   ```bash
   kubectl get nodes
   kubectl get pods -n devpod
   ```

3. **Verify provider configuration:**
   ```bash
   devpod status
   devpod list providers
   ```

---

## Documentation

- [DevPod Documentation](https://devpod.sh/docs)
- [DevContainers Features](https://containers.dev/features)
- [DevPod Troubleshooting](https://devpod.sh/docs/developing-in-workspaces/troubleshooting)
