# Homelab Kubernetes Cluster

Repository for managing a Kubernetes homelab cluster running on Talos Linux.

**Cluster**: 3 nodes (1 control plane + 2 workers) running Talos v1.13.8 / Kubernetes v1.34.1 with Cilium v1.19.6

See [MetalLB Load Balancer section](#1-metallb-load-balancer) for details on LoadBalancer configuration.

## Table of Contents

-   [Infrastructure Overview](#infrastructure-overview)
-   [Deployed Services](#deployed-services)
-   [Monitoring Stack](#monitoring-stack)
-   [Development Environments](#development-environments)
-   [Network Configuration](#network-configuration)
-   [Getting Started](#getting-started)
-   [Service Access](#service-access)
-   [Useful Commands](#useful-commands)
-   [Adding New Services](#adding-new-services)
-   [Tailscale Integration](#tailscale-integration)
-   [Future Services](#future-services)
-   [Talos Configuration](#talos-configuration)

---

## Infrastructure Overview

### Hardware

-   **Talos Control Plane**: 192.168.1.41
    -   Cluster name: `homelab-007`
    -   Disk: `/dev/nvme0n1`
    -   Static IP configuration
    -   Kernel modules: nbd, iscsi_tcp, configfs (for Longhorn)

-   **Talos Worker 1**: 192.168.1.42
    -   Disk: `/dev/nvme0n1`
    -   Static IP configuration

-   **Talos Worker 2**: 192.168.1.43
    -   Disk: `/dev/nvme0n1`
    -   Static IP configuration

All nodes use network interface `enp2s0` with gateway `192.168.1.1`.

### Network Details

-   **Gateway**: 192.168.1.1
-   **DNS (Router)**: 192.168.1.1
-   **DNS (Pi-hole)**: 192.168.1.51
-   **MetalLB IP Pool**: 192.168.1.50-99 (50 addresses for LoadBalancer services)
-   **Pod Network**: 10.244.0.0/16
-   **Service Network**: 10.96.0.0/12
-   **CNI**: Cilium 1.19.6 with Hubble; kube-proxy retained

### Network Policy Rollout

Namespace classifications and policies are managed by the
`helm/network-policies/` chart. The current `observe` stage installs an
explicit allow-all policy in each managed namespace, so Cilium policy handling
is active without restricting traffic. Replace the staged policy with verified
DNS, ingress, monitoring, and application allow rules before enabling default
deny for a namespace.

Infrastructure and system namespaces must not be the first enforcement target.
See `helm/network-policies/README.md` for the rollout procedure.

---

## Deployed Services

### 0. Cert-Manager

**Purpose**: Certificate management for TLS/SSL

**Configuration**:

-   Namespace: `cert-manager`
-   ClusterIssuers: `letsencrypt-cloudflare` (primary), `selfsigned-issuer` (fallback)
-   Certificates: Let's Encrypt certificates via Cloudflare DNS-01 validation
-   Config files: `manifests/letsencrypt-cloudflare-issuer.yaml`, `manifests/wildcard-cert-letsencrypt.yaml`, `manifests/cluster-issuer.yaml`

**Status**: Running

**Features**:

-   Automatic certificate provisioning via Let's Encrypt
-   Wildcard certificate available for `*.elate.me` and `elate.me`
-   Namespace-local certificates created by ingress-shim or explicit chart-managed `Certificate` resources
-   Certificate renewal every 90 days (renews 15 days before expiry)
-   Cloudflare DNS-01 challenge solver
-   Unique TLS Secret names for distinct Ingress host lists; Secrets are never shared across namespaces

### 1. MetalLB Load Balancer

**Purpose**: Provides LoadBalancer IP addresses for Kubernetes services

**Configuration**:

-   Namespace: `metallb-system`
-   IP Address Pool: `192.168.1.50-192.168.1.99`
-   Mode: Layer 2 (L2Advertisement)
-   Interface: `enp2s0` (physical network interface)
-   Config files: `helm/metallb/values.yaml`, `helm/metallb/ipaddresspool.yaml`

**Status**: Running

#### Configuration for Talos Linux

Talos Linux automatically applies the `node.kubernetes.io/exclude-from-external-load-balancers` label to control plane nodes. MetalLB is configured to ignore this label so services can be announced from all nodes.

**Configuration** (in `helm/metallb/values.yaml`):

```yaml
speaker:
  ignoreExcludeLB: true
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
  extraArgs:
    - --protocol=layer2
    - --arping-interval=10
    - --arping-interface=enp2s0
    - --arping-ip-address=192.168.1.41
```

**Deployment**:

```bash
# Add MetalLB Helm repository
helm repo add metallb https://metallb.github.io/metallb
helm repo update

# Install MetalLB with proper configuration
helm install metallb metallb/metallb -n metallb-system --create-namespace -f helm/metallb/values.yaml

# Apply IP pool and L2Advertisement
kubectl apply -f helm/metallb/ipaddresspool.yaml

# Verify speaker is running with ignoreExcludeLB enabled
helm get values metallb -n metallb-system | grep ignoreExcludeLB
```

**Verification**:

```bash
# Check MetalLB pods are running
kubectl get pods -n metallb-system

# Check IP pool is configured
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Check services have LoadBalancer IPs assigned
kubectl get svc -A | grep LoadBalancer

# Test connectivity
ping -c 3 192.168.1.50
curl -I http://192.168.1.50
```

#### Optional Talos Network Sysctls

For optimal MetalLB L2 performance, these sysctls are applied on all nodes:

```yaml
machine:
  sysctls:
    net.ipv4.conf.all.arp_announce: "0"
    net.ipv4.conf.all.arp_ignore: "0"
    net.ipv4.ip_forward: "1"
```

#### Troubleshooting MetalLB on Talos

**Problem**: LoadBalancer IPs assigned but not accessible from network

**Root Cause**: `speaker.ignoreExcludeLB` not set to `true`

**Solution**:

```bash
helm upgrade metallb metallb/metallb -n metallb-system --set speaker.ignoreExcludeLB=true --reuse-values
kubectl wait --for=condition=ready pod -n metallb-system -l app.kubernetes.io/component=speaker --timeout=60s
```

### 2. Traefik Ingress Controller

**Purpose**: HTTPS ingress controller and reverse proxy for `*.elate.me` domains

**Configuration**:

-   Namespace: `traefik`
-   External IP: `192.168.1.50` (from MetalLB)
-   Ports: HTTP 80, HTTPS 443
-   Dashboard: `https://traefik.elate.me`
-   Locked Helm chart: `helm/traefik/` (upstream chart 41.2.0)
-   Image: Traefik 3.7.10 pinned by multi-architecture digest
-   TLS: Let's Encrypt wildcard certificate for `*.elate.me`

**Status**: Running

**Features**:

-   Automatic routing for Kubernetes Ingress resources
-   Dashboard for monitoring routes
-   TLS with Let's Encrypt certificates via cert-manager
-   Access and general logging enabled

### 2a. Public Traefik Ingress Controller

**Purpose**: Isolated ingress tier for applications published through
Cloudflare Tunnel

**Configuration**:

-   Namespace and release: `traefik-public`
-   Service: ClusterIP-only on TCP/80; no MetalLB or node exposure
-   IngressClass: `traefik-public` (non-default)
-   Watches only explicitly listed public namespaces
-   Dashboard and Traefik CRD provider disabled
-   Namespace-scoped application RBAC and fail-closed Cilium policy
-   Config files: `helm/traefik-public/` and
    `helm/network-policies/templates/traefik-public.yaml`

**Status**: Running; both `elate.me` and `elate.biz` are routed through it

The complete public path uses two cloudflared connectors, two public Traefik
replicas, and two replicas per public site. Public-path namespaces enforce the
Restricted Pod Security standard, and disruption budgets preserve one replica
of each public component during voluntary maintenance.

### 3. Longhorn Distributed Storage

**Purpose**: Persistent storage for Kubernetes volumes

**Configuration**:

-   Namespace: `longhorn-system`
-   Storage Class: `longhorn` (default)
-   Replica Count: 1
-   Data Path: `/var/lib/longhorn`
-   Dashboard: `https://longhorn.elate.me`
-   Config files: `helm/longhorn/values.yaml`, `manifests/longhorn-ingress.yaml`

**Status**: Running

**Features**:

-   Default persistent volume provisioner
-   Web-based management UI
-   Snapshot and backup support
-   Requires kernel modules: nbd, iscsi_tcp, configfs (configured in Talos patches)

### 4. Pi-hole DNS & Ad Blocker

**Purpose**: Network-wide ad blocking and local DNS management

**Configuration**:

-   Namespace: `pihole`
-   External IP: `192.168.1.51` (from MetalLB)
-   DNS Ports: 53/TCP, 53/UDP
-   Web UI: `https://pihole.elate.me/admin`
-   Upstream DNS: 1.1.1.1 (Cloudflare), 8.8.8.8 (Google)
-   Config files: `helm/pihole/values.yaml`, `manifests/pihole-ingress.yaml`
-   Storage: 5Gi Longhorn PVC

**Status**: Running

**Features**:

-   Network-wide ad blocking
-   Local DNS resolution for all `*.elate.me` services
-   Persistent storage via Longhorn

**Custom DNS Entries** (configured in `helm/pihole/values.yaml`):

-   `dashboard.elate.me` → 192.168.1.50
-   `traefik.elate.me` → 192.168.1.50
-   `longhorn.elate.me` → 192.168.1.50
-   `pihole.elate.me` → 192.168.1.51
-   `dev.elate.me` → 192.168.1.50
-   `homelab.elate.me` → 192.168.1.50
-   `grafana.elate.me` → 192.168.1.50
-   `uptime.elate.me` → 192.168.1.50

### 5. Heimdall Application Dashboard

**Purpose**: Central dashboard for organizing and accessing homelab services

**Configuration**:

-   Namespace: `heimdall`
-   URL: `https://dashboard.elate.me`
-   Config files: `helm/heimdall/values.yaml`
-   Storage: 1Gi Longhorn PVC

**Status**: Running

**Features**:

-   Centralized application launcher
-   Add/manage homelab services via web UI
-   Customizable dashboards and themes

### 6. Docker Registry

**Purpose**: Local container image registry for cluster workloads

**Configuration**:

-   Namespace: `registry`
-   External IP: `192.168.1.53` (from MetalLB, port 5000)
-   URL: `https://registry.elate.me`
-   Storage: 50Gi Longhorn PVC
-   Helm chart: `helm/registry/`

**Status**: Running

**Features**:

-   CNCF Distribution Registry 3.1.1, pinned by multi-architecture digest
-   Image deletion enabled
-   CORS configured for web access
-   Stores locally built workload images, including the custom `elate-me` site image
-   Prefer the private MetalLB endpoint from LAN build clients; use `registry.elate.me` only where local DNS resolves it to the internal ingress

**Registry 3 upgrade procedure**:

The Registry 3 deployment continues to use the existing filesystem data at
`/var/lib/registry`. Before upgrading, record the catalog and confirm that a
known image can be pulled:

```bash
curl -fsS http://192.168.1.53:5000/v2/_catalog
docker pull 192.168.1.53:5000/elate-me:hosting-20260806b
helm upgrade --install registry ./helm/registry -n registry --create-namespace
kubectl rollout status deployment/registry -n registry --timeout=5m
curl -fsS http://192.168.1.53:5000/v2/_catalog
docker pull 192.168.1.53:5000/elate-me:hosting-20260806b
```

The deployment uses the `Recreate` strategy because its Longhorn volume is
`ReadWriteOnce`, so expect a short registry outage during the rollout. If the
post-upgrade catalog or pull check fails, restore the previous image while
leaving the retained PVC untouched:

```bash
kubectl set image deployment/registry -n registry \
  registry=registry:2@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373
kubectl rollout status deployment/registry -n registry --timeout=5m
```

---

## Monitoring Stack

### Overview

Complete monitoring solution for observability, metrics, and uptime tracking.

**Configuration**:

-   Namespace: `monitoring` (Grafana, Prometheus), `uptime-kuma` (Uptime Kuma)
-   Grafana: `https://grafana.elate.me`
-   Uptime Kuma: `https://uptime.elate.me`
-   Prometheus: Internal only
-   Documentation: `MONITORING_SETUP.md`, `QUICK_START_MONITORING.md`

**Status**: Deployed and operational

### Components

#### Grafana - Metrics Visualization

-   **URL**: `https://grafana.elate.me`
-   **Authentication**: Use the current Grafana administrator account; credentials are not stored in this repository
-   **Namespace**: `monitoring`
-   **Storage**: 5Gi Longhorn PVC
-   **Datasources**: Automatically provisioned (Prometheus, Alertmanager)

**Features**:
-   Pre-configured Prometheus datasource
-   Import dashboards from https://grafana.com/grafana/dashboards/
-   Persistent storage for dashboards and settings

#### Prometheus - Metrics Collection

-   **URL**: Internal only (`http://prometheus-server.monitoring.svc.cluster.local`)
-   **Namespace**: `monitoring`
-   **Components**: Server, Alertmanager, Node Exporter, Kube State Metrics, Pushgateway

**Features**:
-   Kubernetes cluster metrics
-   Node-level metrics via Node Exporter
-   Alert management via Alertmanager
-   Automatic service discovery

#### Uptime Kuma - Uptime Monitoring

-   **URL**: `https://uptime.elate.me`
-   **Namespace**: `uptime-kuma`
-   **Storage**: 5Gi Longhorn PVC
-   **Monitors**: Programmatically configured

**Features**:
-   HTTP/HTTPS monitoring
-   Status pages
-   90+ notification integrations
-   2FA support

### Programmatic Setup

Both Grafana and Uptime Kuma support programmatic configuration:

#### Grafana Datasources

**Automatic**: Datasources are provisioned via ConfigMap on pod startup.

**Location**: `helm/grafana/templates/grafana-datasources.yaml`

**Configured Datasources**:
-   Prometheus (default)
-   Alertmanager

**Add more datasources**: Edit the ConfigMap and restart Grafana:
```bash
helm upgrade grafana helm/grafana -n monitoring
kubectl rollout restart deployment grafana -n monitoring
```

#### Uptime Kuma Monitors

**Setup**: Run after initial account creation at https://uptime.elate.me

```bash
cd scripts
npm install
node setup-uptime-kuma-socketio.js
```

This creates monitors for:
-   All `*.elate.me` services (Heimdall, Grafana, Longhorn, Pi-hole, Traefik, dev environments)
-   Internal services (Prometheus, Alertmanager)

**Customize**: Edit `scripts/setup-uptime-kuma-socketio.js` to add/remove monitors.

### Documentation

-   **Quick Start**: See `QUICK_START_MONITORING.md` for step-by-step setup
-   **Detailed Guide**: See `MONITORING_SETUP.md` for advanced configuration
-   **Scripts**: Located in `scripts/` directory

### Recommended Dashboards

Import these popular Grafana dashboards:

-   **Kubernetes Cluster Monitoring**: Dashboard ID 315
-   **Node Exporter Full**: Dashboard ID 1860
-   **Prometheus Stats**: Dashboard ID 3662

Import via Grafana UI: Configuration → Data sources → Import → Enter Dashboard ID

---

## Development Environments

### Overview

Development environments using **code-server** (VS Code in browser) for remote development with persistent storage.

**Configuration**:

-   Namespace: `devenv`
-   IDE: code-server (VS Code in browser)
-   Main Environment: `https://dev.elate.me`
-   Homelab Management: `https://homelab.elate.me`
-   Storage: Longhorn persistent volumes
-   Documentation: `helm/code-server/README.md`

### Architecture

```
Browser (https://dev.elate.me)
    ↓
Traefik Ingress (TLS via cert-manager)
    ↓
code-server Pod
    ├─ Workspace PVC (project-specific code)
    └─ Shared PVC (common tools, caches)
    ↓
Longhorn Storage
```

### Storage Layout

-   **Shared Storage** (50Gi): Common tools, package caches, shared files
    -   Mounted at `/mnt/shared` in all dev environments
    -   Created once, reused by all environments
-   **Workspace Storage** (10-20Gi per environment): Project-specific code
    -   Mounted at `/home/coder` in each environment
    -   Persists code, extensions, and configuration

### Deployment

Both environments are resources in the repository-owned
`helm/code-server` chart. Deploy or upgrade them together:

```bash
helm upgrade --install code-server helm/code-server \
  --namespace devenv \
  --create-namespace \
  --wait
```

The homelab management container uses the digest-pinned image built from
`images/code-server-homelab/Dockerfile`. Rebuild it with
`scripts/build-code-server-homelab.sh`, update `helm/code-server/values.yaml`
with the returned registry digest, pass CI, and then upgrade the chart.

### Access Methods

1. **Browser IDE**: `https://dev.elate.me`
2. **Terminal in browser**: Built-in terminal in VS Code
3. **kubectl exec**: `kubectl exec -it -n devenv deployment/code-server-main -- bash`
4. **Port-forward**: `kubectl port-forward -n devenv svc/code-server-main 8080:8080`

### Creating Project Environments

`values-project1.yaml` is a reference for a future environment, not an
independently deployable release. Add a new Deployment, Service, PVC, and
Ingress template to the local chart, give its host list a unique TLS Secret,
add the exact Traefik network-policy egress rule, and add internal Pi-hole DNS.
Deploy it through the same `code-server` Helm release.

### Management

See detailed documentation in `helm/code-server/README.md` for:

-   Creating and deleting environments
-   Installing additional tools
-   Configuring VS Code extensions
-   Troubleshooting

---

### DevPod (VS Code Desktop)

### Overview

Development environments using **DevPod** for remote development with full IDE support. Unlike code-server (web-based), DevPod runs client-side and creates dynamic workspaces in Kubernetes.

**Configuration**:

-   Namespace: `devpod`
-   IDE: VS Code Desktop (full-featured local IDE)
-   Access: SSH tunneling from local machine to Kubernetes pods
-   Storage: Longhorn persistent volumes (20Gi per workspace)
-   Documentation: `devpod/README.md`

**Status**: Ready to deploy (configuration files created)

### Architecture

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

### Access Methods

1.  **VS Code Desktop** (Primary): `devpod up --id my-workspace . --ide vscode`
2.  **SSH** (Alternative): `ssh my-workspace.devpod`
3.  **Port Forwarding**: `devpod ssh my-workspace -L 3000:localhost:3000`
4.  **kubectl exec** (Debugging): `kubectl exec -it -n devpod <pod-name> -- bash`

### Quick Start

**Cluster Setup (one-time):**

```bash
# Create namespace and RBAC
kubectl create namespace devpod
kubectl apply -f manifests/devpod-rbac.yaml

# Configure pod security
kubectl label namespace devpod pod-security.kubernetes.io/enforce=privileged
kubectl label namespace devpod pod-security.kubernetes.io/audit=privileged
kubectl label namespace devpod pod-security.kubernetes.io/warn=privileged
```

**Client Setup (per developer):**

```bash
# Install DevPod CLI
brew install devpod

# Install VS Code + SSH extension
code --install-extension ms-vscode-remote.remote-ssh

# Configure provider
cp devpod/provider.yaml ~/.devpod/provider/kubernetes.yaml
devpod provider add kubernetes
```

**Create workspace:**

```bash
devpod up --id devpod-primary . --ide vscode
```

### Comparison with code-server

| Feature | DevPod | code-server |
|----------|----------|-------------|
| **IDE** | VS Code Desktop | VS Code in Browser |
| **Access** | SSH + VS Code Client | Web URL (dev.elate.me) |
| **Performance** | Local IDE, remote workspace | Everything in browser |
| **Setup** | Install DevPod CLI | Kubernetes deployment |
| **Use Case** | Daily development | Quick access, testing |

**Documentation**: See `devpod/README.md` for complete DevPod setup and usage guide.

## Network Configuration

### IP Address Allocation

| Service      | IP Address      | Ports   | Purpose                    |
| ------------ | --------------- | ------- | -------------------------- |
| Control Plane| 192.168.1.41    | 6443    | Kubernetes API Server      |
| Worker 1     | 192.168.1.42    | -       | Kubernetes worker          |
| Worker 2     | 192.168.1.43    | -       | Kubernetes worker          |
| Traefik      | 192.168.1.50    | 80, 443 | Ingress Controller         |
| Pi-hole      | 192.168.1.51    | 53, 80  | DNS & Web UI               |
| Registry     | 192.168.1.53    | 5000    | Docker Registry            |
| MetalLB Pool | 192.168.1.50-99 | -       | Available for new services |

### DNS Resolution Flow

```
Client Request (e.g., grafana.elate.me)
    ↓
Pi-hole DNS (192.168.1.51)
    ↓
Returns: 192.168.1.50 (Traefik)
    ↓
Traefik routes based on hostname
    ↓
Backend service
```

---

## Getting Started

### Prerequisites

-   `kubectl` configured to connect to the cluster
-   `helm` installed
-   `talosctl` installed

### Connect to Cluster

```bash
# Configure talosctl
talosctl --talosconfig=./talosconfig config endpoints 192.168.1.41

# Get kubeconfig
talosctl --talosconfig=./talosconfig kubeconfig --nodes 192.168.1.41

# Verify connection
kubectl get nodes
```

### Check Cluster Health

```bash
# Talos health check
talosctl --nodes 192.168.1.41 --talosconfig=./talosconfig health

# Check all pods
kubectl get pods -A

# Check services with LoadBalancer IPs
kubectl get svc -A | grep LoadBalancer
```

---

## Service Access

### Configure DNS on Your Network

**Option 1: Router DHCP (Recommended)**

-   Configure your router's DHCP server to use `192.168.1.51` as the DNS server
-   All devices on the network will automatically use Pi-hole

**Option 2: Manual Device Configuration**

-   On each device, set DNS server to `192.168.1.51`
-   Keep `192.168.1.1` as secondary DNS (fallback)

### Access Service Dashboards

Once DNS is configured:

```bash
# Heimdall Dashboard
https://dashboard.elate.me

# Pi-hole Admin
https://pihole.elate.me/admin

# Traefik Dashboard
https://traefik.elate.me

# Longhorn UI
https://longhorn.elate.me

# Grafana
https://grafana.elate.me

# Uptime Kuma
https://uptime.elate.me
```

### Test DNS Resolution

```bash
# Test from command line
nslookup traefik.elate.me 192.168.1.51
nslookup longhorn.elate.me 192.168.1.51

# Expected response: 192.168.1.50 for Traefik-routed services
```

---

## Useful Commands

### Cluster Management

```bash
# View all namespaces
kubectl get namespaces

# Check node status
kubectl get nodes -o wide

# View all pods across all namespaces
kubectl get pods -A

# Check storage classes
kubectl get storageclass

# View persistent volumes
kubectl get pv
kubectl get pvc -A
```

### Service-Specific Commands

```bash
# MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system

# Traefik
kubectl get pods -n traefik
kubectl get svc -n traefik
kubectl get ingressroute -A

# Longhorn
kubectl get pods -n longhorn-system
kubectl get volumes.longhorn.io -n longhorn-system

# Pi-hole
kubectl get pods -n pihole
kubectl get svc -n pihole

# Rotate the Pi-hole password persistently:
# 1. Update the ignored secrets/pihole-password.yaml file.
# 2. Reseal, apply, and restart Pi-hole using SEALED_SECRETS.md.
```

### Logs and Debugging

```bash
# View pod logs
kubectl logs -n <namespace> <pod-name>

# Follow logs in real-time
kubectl logs -n <namespace> <pod-name> -f

# Describe a pod (see events and status)
kubectl describe pod -n <namespace> <pod-name>

# Get events in a namespace
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

---

## Adding New Services

### Deployment Workflow

1. Create a Helm chart under `helm/<service>/` containing the workload,
   ClusterIP Service, and any Ingress. Do not add standalone service manifests.
2. Classify the namespace in `helm/network-policies/values.yaml` and add exact,
   reciprocal gateway-to-backend rules before enforcing it.
3. For an internal service, use the default `traefik` IngressClass and add its
   Pi-hole record pointing to `192.168.1.50`.
4. For a public service, use a `public` namespace, the `traefik-public`
   IngressClass, and a Cloudflare Tunnel hostname route targeting only
   `traefik-public.traefik-public.svc.cluster.local:80`.
5. Install with `helm upgrade --install`, then verify the endpoint and inspect
   Hubble for unexpected denied flows.

### Using Persistent Storage

Add persistent storage to the service's Helm templates, for example:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
    name: myapp-data
spec:
    accessModes:
        - ReadWriteOnce
    storageClassName: longhorn
    resources:
        requests:
            storage: 5Gi
```

---

## Tailscale Integration

### Status
Deployed and operational

### Overview

Tailscale provides secure remote access to your entire homelab (192.168.1.0/24) without exposing services to the internet. A subnet router runs in Kubernetes to bridge your Tailscale network with your local network.

**Configuration**:
- **Namespace**: `tailscale`
- **Deployment**: StatefulSet (subnet router)
- **Device Name**: homelab-k8s-subnet-router
- **Subnet Routes**: 192.168.1.0/24
- **DNS**: Pi-hole (192.168.1.51) for `*.elate.me` resolution
- **Storage**: 1Gi Longhorn PVC for state persistence

### How It Works

```
Remote Device (anywhere)
    ↓
Tailscale VPN (100.x.x.x network)
    ↓
Subnet Router (Kubernetes pod)
    ↓
192.168.1.0/24 Network
    ├─ 192.168.1.50 (Traefik/All services)
    ├─ 192.168.1.51 (Pi-hole DNS)
    └─ All *.elate.me domains
```

### Next Steps to Complete Setup

After deployment, you need to:

1. **Approve Subnet Routes** (in Tailscale admin console):
   - Go to https://login.tailscale.com/admin/machines
   - Find device: "homelab-k8s-subnet-router"
   - Click "..." → "Edit route settings"
   - Enable: `192.168.1.0/24`
   - Click "Save"

2. **Configure DNS** (in Tailscale admin console):
   - Go to **DNS** settings
   - Click "Add nameserver" → "Custom..."
   - Enter: `192.168.1.51` (Pi-hole)
   - Enable "Override local DNS"
   - *Optional*: Add Split DNS for `elate.me` → `192.168.1.51`

3. **Connect from Remote Device**:
   ```bash
   # Install Tailscale
   # macOS: brew install tailscale
   # Linux: apt-get install tailscale

   # Connect with subnet routes enabled
   tailscale up --accept-routes

   # Verify connection
   tailscale status
   ping 192.168.1.50
   ```

4. **Test Access**:
   ```bash
   # Test DNS resolution
   nslookup dashboard.elate.me
   # Should return: 192.168.1.50

   # Test HTTPS access
   curl -k https://dashboard.elate.me

   # Open in browser
   https://dev.elate.me           # Code-server
   https://dashboard.elate.me     # Heimdall
   https://pihole.elate.me/admin  # Pi-hole
   https://longhorn.elate.me      # Longhorn
   ```

### Remote Access

Once configured, from anywhere with internet:
- **All Services**: Access any `*.elate.me` domain
- **Direct IPs**: Ping/access any `192.168.1.x` IP
- **DNS & Ad-blocking**: Pi-hole works remotely
- **Encryption**: End-to-end encrypted (zero-trust)

### Management Commands

```bash
# Check pod status
kubectl get pods -n tailscale

# View connection status
kubectl exec -n tailscale tailscale-subnet-router-0 -- tailscale status

# View logs
kubectl logs -n tailscale tailscale-subnet-router-0 -f

# Restart pod (if needed)
kubectl rollout restart statefulset/tailscale-subnet-router -n tailscale

# Update auth key (if needed)
kubectl create secret generic tailscale-auth \
  -n tailscale \
  --from-literal=TS_AUTHKEY='NEW-KEY-HERE' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart statefulset/tailscale-subnet-router -n tailscale
```

### Troubleshooting

**Can't access 192.168.1.x IPs:**
- Verify routes are approved in Tailscale admin console
- Ensure you used `--accept-routes` when connecting
- Check: `tailscale status` should show subnet routes

**DNS not resolving *.elate.me:**
- Verify Pi-hole (192.168.1.51) is set as nameserver in Tailscale DNS settings
- Enable "Override local DNS" in Tailscale admin console
- Flush DNS cache on your device

**Pod not running:**
- Check logs: `kubectl logs -n tailscale tailscale-subnet-router-0`
- Verify PVC is bound: `kubectl get pvc -n tailscale`
- Check auth key is valid (regenerate if expired)

### Cost

**Free** - Tailscale Personal plan (up to 3 users, 100 devices)

---

## Future Services

Services to consider deploying:

-   **PostgreSQL** - Database
-   **Argo CD** - GitOps continuous deployment
-   **Passbolt** - Password manager
-   **GitLab** - Git repository and CI/CD

---

## Talos Configuration

### Current Configuration

The cluster is configured with:

-   **Talos Version**: v1.13.8
-   **Kubernetes Version**: v1.34.1
-   **Nodes**: 3 (1 control plane + 2 workers)
-   **Network Interface**: enp2s0 (all nodes)
-   **Control Plane Endpoint**: https://192.168.1.41:6443
-   **Install Disk**: /dev/nvme0n1 (all nodes)
-   **Factory Image**: factory.talos.dev/installer/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245:v1.13.8

### Talos Patches

-   **fix-nodeip-controlplane.yaml**: Forces kubelet to use 192.168.1.0/24 subnet (prevents Tailscale IP conflicts)
-   **fix-kernel-modules.yaml**: Loads nbd, iscsi_tcp, configfs modules for Longhorn storage

### Talos Management Commands

```bash
# Check Talos version
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 version

# Get node status
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 get members

# View Talos logs
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 logs

# Check installed extensions
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 get extensions

# Service status
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 service

# Reboot node (use with caution!)
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 reboot
```

### Talos Upgrade (With Custom Image)

```bash
# Schematic ID: c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac
# To upgrade to a new version:
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 upgrade \
  --image factory.talos.dev/installer/c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac:v1.X.X \
  --preserve
```

### Initial Bootstrap Commands (Reference)

```bash
# Generate Talos config
talosctl gen config homelab https://192.168.1.41:6443 --install-disk /dev/nvme0n1

# Apply configuration
talosctl apply-config --insecure --nodes 192.168.1.41 --file controlplane.yaml

# Bootstrap cluster
talosctl --talosconfig=./talosconfig config endpoints 192.168.1.41
talosctl bootstrap --nodes 192.168.1.41 --talosconfig=./talosconfig
talosctl kubeconfig --nodes 192.168.1.41 --talosconfig=./talosconfig

# Health check
talosctl --nodes 192.168.1.41 --talosconfig=./talosconfig health
```

### Adding Additional Nodes

Use the `generate-talos-config.sh` script to create node configurations with all the necessary patches:

**Generate a new worker node config:**
```bash
./generate-talos-config.sh --type worker --ip 192.168.1.44

# Review and apply
cat worker.yaml
talosctl apply-config --insecure --nodes 192.168.1.44 --file worker.yaml

# Wait for node to join
kubectl get nodes -w
```

**Script options:**
```bash
./generate-talos-config.sh --help

# Example with custom gateway
./generate-talos-config.sh --type worker --ip 192.168.1.44 --gateway 192.168.1.254
```

---

## Repository Structure

```
homelab/
 ├── README.md                          # This file
 ├── AGENTS.md                          # Codex repository guidance
 ├── CLAUDE.md                          # Claude Code guidance
 ├── MONITORING_SETUP.md                # Monitoring setup guide
 ├── DISASTER_RECOVERY.md               # Backup architecture and restore testing
 ├── SUPPLY_CHAIN.md                    # Dependency update and CI trust policy
 ├── QUICK_START_MONITORING.md          # Quick monitoring reference
 ├── generate-talos-config.sh           # Script to generate node configurations
 ├── helm/                              # Helm charts and upstream values
 │   ├── cilium/                        # CNI and policy-engine values
 │   ├── cloudflared/                   # Cloudflare Tunnel connector
 │   ├── code-server/                   # Development environments
 │   ├── grafana/                       # Grafana workload and provisioning
 │   ├── network-policies/              # Cilium policies and classifications
 │   ├── longhorn-protection/            # Recurring snapshot and backup policy
 │   ├── openvpn/                       # Disabled TAP VPN for classic Mac OS
 │   ├── public-sites/                  # elate.me and elate.biz
 │   ├── registry/                      # Local image registry
 │   ├── sealed-secrets/                # Vendored controller chart
 │   ├── tailscale/                     # Subnet router
 │   ├── traefik/                       # Internal LAN ingress controller
 │   ├── traefik-public/                # Isolated public ingress
 │   └── uptime-kuma/                   # Uptime monitoring
 ├── images/                            # Repository-owned workload images
 │   └── code-server-homelab/           # Pinned management image and BuildKit config
 ├── manifests/                         # Supporting cluster-wide resources
 │   ├── letsencrypt-cloudflare-issuer.yaml  # Let's Encrypt ClusterIssuer
 │   ├── wildcard-cert-letsencrypt.yaml      # *.elate.me certificate
 │   ├── cluster-issuer.yaml            # Self-signed issuer (fallback)
 │   ├── https-redirect-middleware.yaml  # HTTP→HTTPS redirect
 │   ├── devpod-rbac.yaml               # DevPod RBAC
 │   ├── longhorn-ingress.yaml          # Longhorn ingress
 │   ├── pihole-ingress.yaml            # Pi-hole ingress
 │   └── metallb-*.yaml                 # MetalLB security policies
 ├── talos-patches/                     # Talos machine config patches
 │   ├── fix-nodeip-controlplane.yaml
 │   ├── fix-kernel-modules.yaml
 │   └── worker-*.yaml                  # Worker node configs
 ├── scripts/                           # Utility scripts
 │   ├── build-code-server-homelab.sh   # Build and push the management image
 │   ├── setup-uptime-kuma.sh           # Configure monitors (bash)
 │   ├── setup-uptime-kuma-socketio.js  # Configure monitors (Node.js)
 │   └── cleanup-uptime-kuma-duplicates.js
 ├── secrets/                           # Plaintext inputs (gitignored; never commit)
 ├── sealedsecrets/                     # Encrypted SealedSecrets (safe to commit)
 ├── devpod/                            # DevPod configuration
 └── .devcontainer/                     # Dev container configs
```

---

## Important Notes

### Security

-   TLS certificates are valid Let's Encrypt certificates (no browser warnings)
-   Kubernetes credentials are managed with Bitnami Sealed Secrets; see [SEALED_SECRETS.md](SEALED_SECRETS.md)
-   Plaintext manifests under `secrets/` and generated Talos credentials are gitignored
-   Encrypted manifests under `sealedsecrets/` are safe to commit and are decrypted only by this cluster
-   Pi-hole reads its admin password from the `pihole-password` Secret
-   Grafana credentials are managed in Grafana and are not stored in this repository

### Maintenance

-   **Local recovery**: Longhorn takes daily local snapshots and retains seven per volume; see [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md)
-   **TODO — off-site backups**: Configure a remote Longhorn backup target and schedule Talos `etcd` snapshots to encrypted off-cluster storage. This is intentionally deferred and local snapshots do not protect against loss of the cluster or its storage nodes.
-   **Updates**: Keep Kubernetes, Talos, and applications updated
-   **Update discovery**: Review-only Renovate configuration is available; see [SUPPLY_CHAIN.md](SUPPLY_CHAIN.md)
-   **Security scanning**: GitHub Actions blocks changes containing high/critical configuration findings or potential committed secrets
-   **Image scanning**: Public workload images receive report-only high/critical vulnerability scans; the LAN-only application image remains a documented coverage gap
-   **Monitoring**: Complete monitoring stack deployed - see [Monitoring Stack](#monitoring-stack) section

---

## Troubleshooting

### MetalLB LoadBalancer Services Not Responding

**Symptom**: Services have EXTERNAL-IP assigned but cannot access them from external network

**Root Cause**: `speaker.ignoreExcludeLB` not set to `true` in MetalLB config

**Solution**:

```bash
helm upgrade metallb metallb/metallb -n metallb-system --set speaker.ignoreExcludeLB=true --reuse-values
kubectl wait --for=condition=ready pod -n metallb-system -l app.kubernetes.io/component=speaker --timeout=60s
```

**Verification**:

```bash
kubectl get events -n traefik --sort-by='.lastTimestamp' | grep -i announce
ping -c 3 192.168.1.50
curl -I http://192.168.1.50
```

### Cluster Not Accessible

```bash
# Check if Talos node is reachable
ping 192.168.1.41

# Verify kubeconfig is set up
kubectl cluster-info

# Re-generate kubeconfig if needed
talosctl --talosconfig=./talosconfig kubeconfig --nodes 192.168.1.41 --force
```

### Pod Won't Start

```bash
# Check pod status
kubectl get pods -n <namespace>

# View detailed information
kubectl describe pod -n <namespace> <pod-name>

# Check logs
kubectl logs -n <namespace> <pod-name>
```

### DNS Not Resolving

```bash
# Test Pi-hole DNS
nslookup traefik.elate.me 192.168.1.51

# Check Pi-hole is running
kubectl get pods -n pihole

# Check Pi-hole service has IP
kubectl get svc -n pihole
```

### Can't Access Services via *.elate.me

1. Ensure your device is using Pi-hole for DNS (192.168.1.51)
2. Check DNS resolution works: `nslookup dashboard.elate.me 192.168.1.51`
3. Verify Traefik is running: `kubectl get pods -n traefik`
4. Check Ingress resources exist: `kubectl get ingress -A`

---

## Support & Resources

-   **Talos Documentation**: https://www.talos.dev/
-   **Kubernetes Documentation**: https://kubernetes.io/docs/
-   **MetalLB**: https://metallb.universe.tf/
-   **Traefik**: https://doc.traefik.io/traefik/
-   **Longhorn**: https://longhorn.io/docs/
-   **Pi-hole**: https://docs.pi-hole.net/
-   **Tailscale**: https://tailscale.com/kb/

---

**Last Updated**: January 2026
