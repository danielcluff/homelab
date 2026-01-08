# Homelab Kubernetes Cluster

Repository for managing a Kubernetes homelab cluster running on Talos Linux.

**⚠️ IMPORTANT NOTE**: Currently running single-node cluster with control plane node configured to host LoadBalancer services by removing `node.kubernetes.io/exclude-from-external-load-balancers` label. **When adding additional nodes, revert this change** to follow Kubernetes best practices and prevent control plane nodes from hosting external load balancers.

See [MetalLB Load Balancer section](#1-metallb-load-balancer) for details.

## Table of Contents

-   [Infrastructure Overview](#infrastructure-overview)
-   [Deployed Services](#deployed-services)
-   [Network Configuration](#network-configuration)
-   [Getting Started](#getting-started)
-   [Service Access](#service-access)
    -   [Importing Self-Signed CA Certificate](#importing-self-signed-ca-certificate)
-   [Useful Commands](#useful-commands)
-   [Adding New Services](#adding-new-services)
-   [Tailscale Integration](#tailscale-integration)
-   [Future Services](#future-services)
-   [Talos Configuration](#talos-configuration)

---

## Infrastructure Overview

### Hardware

-   **Debian Box**: 192.168.1.40 (management/utility server)
    78-55-36-04-92-B3

-   **Talos Node**: 192.168.1.41 (Kubernetes control plane + worker)
    -   Cluster name: `homelab-007`
    -   Disk: `/dev/nvme0n1`
    -   Static IP configuration
    -   iSCSI support enabled for Longhorn storage
        78-55-36-05-36-9B

### Network Details

-   **Gateway**: 192.168.1.1
-   **DNS (Router)**: 192.168.1.1
-   **DNS (Pi-hole)**: 192.168.1.51
-   **NTP Server**: 97.107.136.23
-   **MetalLB IP Pool**: 192.168.1.50-99 (50 addresses for LoadBalancer services)

---

## Deployed Services

### 0. Cert-Manager

**Purpose**: Certificate management for TLS/SSL

**Configuration**:

-   Namespace: `cert-manager`
-   Type: ClusterIssuer (self-signed)
-   Certificate: Wildcard `*.home.com`
-   Config files: `manifests/cluster-issuer.yaml`, `manifests/wildcard-cert.yaml`

**Status**: ✅ Running

**Features**:

-   Automatic certificate provisioning
-   Self-signed wildcard certificate for `*.home.com`
-   Certificate renewal every 90 days
-   TLS secrets distributed to all service namespaces
-   TLS secrets distributed to all namespaces (heimdall, pihole, longhorn-system)

### 1. MetalLB Load Balancer

**Purpose**: Provides LoadBalancer IP addresses for Kubernetes services

**Configuration**:

-   Namespace: `metallb-system`
-   IP Address Pool: `192.168.1.50-192.168.1.99`
-   Mode: Layer 2 (L2Advertisement)
-   Interface: `enp2s0` (physical network interface)
-   Config files: `helm/metallb/values.yaml`, `helm/metallb/ipaddresspool.yaml`

**Status**: ✅ Running

#### Critical Configuration for Talos Linux

**⚠️ REQUIRED FOR SINGLE-NODE CLUSTERS**: Talos Linux automatically applies the `node.kubernetes.io/exclude-from-external-load-balancers` label to control plane nodes (Kubernetes best practice for production multi-node clusters). For single-node homelabs where the control plane must host services, MetalLB must be configured to **ignore** this label.

**Correct Solution** (configured in `helm/metallb/values.yaml`):

```yaml
speaker:
  # Critical for Talos: ignore the exclude-from-external-load-balancers label
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
    - --arping-interface=enp2s0  # Must match your network interface
    - --arping-ip-address=192.168.1.41  # Node IP
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
# Should output: ignoreExcludeLB: true
```

**Verification**:

```bash
# Check MetalLB pods are running
kubectl get pods -n metallb-system
# Expected: controller (1/1 Running), speaker (4/4 Running)

# Check IP pool is configured
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system

# Check services have LoadBalancer IPs assigned
kubectl get svc -A | grep LoadBalancer
# Should show EXTERNAL-IP for Traefik (192.168.1.50) and Pi-hole (192.168.1.51)

# Test connectivity from external network
ping -c 3 192.168.1.50  # Should respond
curl http://192.168.1.50  # Should get 404 from Traefik (expected)
curl http://192.168.1.51  # Should get Pi-hole web interface

# Check announcement events
kubectl get events -n traefik --sort-by='.lastTimestamp' | grep nodeAssigned
# Should show: "announcing from node talos-fy9-w02 with protocol layer2"
```

#### Optional Talos Network Sysctls

For optimal MetalLB L2 performance, these sysctls can be applied (already configured on this cluster):

```bash
# Create sysctl patch file
cat > /tmp/metallb-sysctls-patch.yaml <<EOF
machine:
  sysctls:
    net.ipv4.conf.all.arp_announce: "0"
    net.ipv4.conf.all.arp_ignore: "0"
    net.ipv4.ip_forward: "1"
EOF

# Apply to Talos node (no reboot required)
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 patch machineconfig -p @/tmp/metallb-sysctls-patch.yaml
```

#### Troubleshooting MetalLB on Talos

**Problem**: LoadBalancer IPs assigned but not accessible from network

**Symptoms**:
- Services show EXTERNAL-IP in `kubectl get svc`
- Cannot ping or access LoadBalancer IPs from external network
- `arp -a` shows incomplete entries for LoadBalancer IPs
- No "announcing from node" events in service events

**Root Cause**: `speaker.ignoreExcludeLB` not set to `true`

**Solution**:

```bash
# Method 1: Upgrade existing installation
helm upgrade metallb metallb/metallb -n metallb-system --set speaker.ignoreExcludeLB=true --reuse-values

# Method 2: Edit values.yaml and reinstall
# Add "ignoreExcludeLB: true" under speaker section, then:
helm upgrade metallb metallb/metallb -n metallb-system -f helm/metallb/values.yaml

# Wait for speaker to restart
kubectl wait --for=condition=ready pod -n metallb-system -l app.kubernetes.io/component=speaker --timeout=60s

# Verify the fix
kubectl get events -n traefik --sort-by='.lastTimestamp' | grep -i announce
# Should show fresh "announcing from node" events

# Test connectivity
curl -I http://192.168.1.50  # Should return HTTP headers
```

**Why This Works**: The `ignoreExcludeLB: true` setting tells MetalLB speaker to announce services even on nodes with the `exclude-from-external-load-balancers` label. This is essential for single-node Talos clusters where the control plane must host workloads.

**⚠️ When Adding Worker Nodes**: Once you have dedicated worker nodes, you can remove `ignoreExcludeLB: true` to follow Kubernetes best practices and let only worker nodes announce LoadBalancer services.

### 2. Traefik Ingress Controller

**Purpose**: HTTPS ingress controller and reverse proxy for `*.home.com` domains

**Configuration**:

-   Namespace: `traefik`
-   External IP: `192.168.1.50` (from MetalLB)
-   Ports:
    -   HTTP: 80
    -   HTTPS: 443
-   Dashboard: `https://traefik.home.com`
-   Config files: `helm/traefik/values.yaml`
-   TLS: Self-signed wildcard certificate for `*.home.com`

**Status**: ✅ Running

**Features**:

-   Automatic routing for Kubernetes Ingress resources
-   Dashboard for monitoring routes
-   SSL/TLS enabled with self-signed certificates (cert-manager)
-   All services configured for HTTPS-only (HTTP blocked)

### 3. Longhorn Distributed Storage

**Purpose**: Persistent storage for Kubernetes volumes

**Configuration**:

-   Namespace: `longhorn-system`
-   Storage Class: `longhorn` (default)
-   Replica Count: 1 (single node)
-   Data Path: `/var/lib/longhorn`
-   Dashboard: `https://longhorn.home.com`
-   Config files: `helm/longhorn/values.yaml`, `manifests/longhorn-ingress.yaml`

**Status**: ⚠️ Initializing (completing in background)

**Features**:

-   Persistent volume provisioning
-   Web-based management UI
-   Snapshot and backup support
-   Will be fully operational once initialization completes
-   HTTPS-only access with self-signed certificate

### 4. Pi-hole DNS & Ad Blocker

**Purpose**: Network-wide ad blocking and local DNS management

**Configuration**:

-   Namespace: `pihole`
-   External IP: `192.168.1.51` (from MetalLB)
-   DNS Ports: 53/TCP, 53/UDP
-   Web UI: `https://pihole.home.com/admin` or `http://192.168.1.51/admin`
-   Admin Password: `password` ⚠️ **CHANGE THIS!**
-   Upstream DNS: 192.168.1.1 (router), 1.1.1.1 (Cloudflare)
-   Config files: `helm/pihole/values.yaml`, `manifests/pihole-ingress.yaml`

**Status**: ✅ Running (without persistence - will be added when Longhorn is ready)

**Features**:

-   Network-wide ad blocking
-   Local DNS resolution
-   HTTPS-only access with self-signed certificate

**Pre-configured DNS Records**:

-   `home.com` → 192.168.1.50
-   `dashboard.home.com` → 192.168.1.50
-   `traefik.home.com` → 192.168.1.50
-   `longhorn.home.com` → 192.168.1.50
-   `pihole.home.com` → 192.168.1.51
-   Default: `*.home.com` → 192.168.1.50 (routed via Traefik)

### 5. Heimdall Application Dashboard

**Purpose**: Central dashboard for organizing and accessing homelab services

**Configuration**:

-   Namespace: `heimdall`
-   URL: `https://home.com` and `https://dashboard.home.com`
-   Config files: `helm/heimdall/values.yaml`
-   TLS: Self-signed wildcard certificate for `*.home.com`

**Status**: ✅ Running

**Features**:

-   Centralized application launcher
-   Add/manage homelab services via web UI
-   HTTPS-only access with self-signed certificate
-   Customizable dashboards and themes

---

## Network Configuration

### IP Address Allocation

| Service      | IP Address      | Ports   | Purpose                    |
| ------------ | --------------- | ------- | -------------------------- |
| Talos Node   | 192.168.1.41    | 6443    | Kubernetes API Server      |
| Debian Box   | 192.168.1.87    | -       | Management/Utility Server  |
| Traefik      | 192.168.1.50    | 80, 443 | Ingress Controller         |
| Pi-hole      | 192.168.1.51    | 53, 80  | DNS & Web UI               |
| MetalLB Pool | 192.168.1.50-99 | -       | Available for new services |

### DNS Resolution Flow

```
Client Request (e.g., grafana.home.com)
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
# Copy talosconfig from Debian box (first time only)
scp daniel@192.168.1.87:~/talosconfig ~/dev/homelab/talosconfig

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
https://home.com
# or
https://dashboard.home.com

# Pi-hole Admin
https://pihole.home.com/admin

# Traefik Dashboard
https://traefik.home.com

# Longhorn UI
https://longhorn.home.com
```

**Note**: Services are now accessible via HTTPS with self-signed certificates. You will see browser warnings that can be safely dismissed since you control the certificate.

### Importing Self-Signed CA Certificate

To eliminate browser warnings for all `*.home.com` services, import the CA certificate into your browser's trusted store:

#### Step 1: Export CA Certificate

```bash
# Export CA certificate from any namespace (heimdall, pihole, or longhorn-system)
kubectl get secret home.com-tls -n heimdall -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
```

#### Step 2: Import into Browser

**Chrome/Edge/Brave (Chromium-based):**

1. Open `chrome://settings/certificates` or `edge://settings/certificates`
2. Go to "Authorities" tab
3. Click "Import"
4. Select the `ca.crt` file you exported
5. Check "Trust this certificate for identifying websites"
6. Click OK

**Firefox:**

1. Open `about:preferences#privacy` → Certificates → Authorities
2. Click "Import..."
3. Select the `ca.crt` file
4. Check "Trust this CA to identify websites"
5. Click OK

**Safari (macOS):**

1. Open Keychain Access (Applications → Utilities)
2. Drag `ca.crt` file into System keychain
3. Double-click the imported certificate
4. Set "Trust" → "When using this certificate" → "Always Trust"
5. Close windows (you may need to enter your password)

#### Verify Import

After importing, refresh any `*.home.com` page - the security warning should be gone and you'll see the secure lock icon.

### Test DNS Resolution

```bash
# Test from command line
nslookup traefik.home.com 192.168.1.51
nslookup longhorn.home.com 192.168.1.51

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

# Reset Pi-hole password (two methods)
# Method 1: Direct command (if password not set by environment variable)
kubectl exec -n pihole $(kubectl get pod -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}') -- pihole setpassword YOUR_NEW_PASSWORD

# Method 2: Update Helm values (recommended - persistent)
# Edit helm/pihole/values.yaml and change admin.password, then:
helm upgrade pihole mojo2600/pihole -n pihole -f helm/pihole/values.yaml

# Access Pi-hole API via kubectl exec
kubectl exec -n pihole $(kubectl get pod -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}') -- pihole status
kubectl exec -n pihole $(kubectl get pod -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}') -- pihole -q google.com
kubectl exec -n pihole $(kubectl get pod -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}') -- pihole -t
kubectl exec -n pihole $(kubectl get pod -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}') -- pihole -up --check-only
kubectl exec -n pihole $(kubectl get pod -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}') -- pihole disable
kubectl exec -n pihole $(kubectl get pod -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}') -- pihole enable
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

1. **Deploy your application**

    ```bash
    kubectl apply -f your-app.yaml
    ```

2. **Create an Ingress** (for HTTP/HTTPS access)

    ```yaml
    apiVersion: networking.k8s.io/v1
    kind: Ingress
    metadata:
        name: myapp
        namespace: default
        annotations:
            kubernetes.io/ingress.class: traefik
    spec:
        rules:
            - host: myapp.homelab.local
              http:
                  paths:
                      - path: /
                        pathType: Prefix
                        backend:
                            service:
                                name: myapp-service
                                port:
                                    number: 80
    ```

3. **Add DNS record in Pi-hole**

    - Access Pi-hole admin: `http://192.168.1.51/admin`
    - Go to: Local DNS → DNS Records
    - Add record: `myapp.homelab.local` → `192.168.1.50`

4. **Access your service**
    - Browse to: `http://myapp.homelab.local`

### Using Persistent Storage

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

### Why Tailscale?

Tailscale provides secure remote access to your homelab without exposing services to the internet or needing external-dns.

### How It Works

```
Remote Location
    ↓
Connect to Tailscale VPN
    ↓
Virtually on your home network (can access 192.168.1.x)
    ↓
Access services via homelab.local domains
```

### Setup Steps (When Ready)

1. **Install Tailscale on Talos node or as a Kubernetes pod**
2. **Configure Tailscale to use Pi-hole for DNS**
    - This allows `*.homelab.local` to resolve when connected remotely
3. **Connect from anywhere**
    - Access services as if you were at home
    - Example: `http://traefik.homelab.local` works from anywhere

**No external-dns needed. No public domain needed. No cloud DNS needed.**

---

## Future Services

Services to consider deploying:

-   **Twingate** - Alternative to Tailscale for zero-trust access
-   **Grafana** - Monitoring and visualization
-   **Prometheus** - Metrics collection
-   **PostgreSQL** - Database
-   **Uptime Kuma** - Uptime monitoring
-   **Argo CD** - GitOps continuous deployment
-   **Passbolt** - Password manager
-   **GitLab** - Git repository and CI/CD

---

## Talos Configuration

### Current Configuration

The Talos node is configured with:

-   **Static IP**: 192.168.1.41
-   **Network Interface**: enp2s0
-   **iSCSI Extension**: v0.2.0 (for Longhorn support)
-   **Control Plane Endpoint**: https://192.168.1.41:6443

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

The node uses a custom Talos image with iSCSI support:

```bash
# Schematic ID: c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac
# Image: factory.talos.dev/installer/c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac:v1.11.6

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

When adding more Talos nodes in the future:

```bash
# For each new worker node
WORKER_IP=("192.168.1.41" "192.168.1.42" "192.168.1.43")

for ip in "${WORKER_IP[@]}"; do
    echo "Applying config to worker node: $ip"
    talosctl apply-config --insecure --nodes "$ip" --file worker.yaml
done

# Update Longhorn replica count when you have multiple nodes
kubectl patch -n longhorn-system settings.longhorn.io default-replica-count \
  -p '{"value":"3"}' --type=merge
```

---

## Repository Structure

```
homelab/
 ├── README.md                      # This file
 ├── SEALED_SECRETS.md             # Sealed Secrets setup guide
 ├── talosconfig                    # Talos cluster configuration
 ├── talos-patch.yaml              # Talos patch for iSCSI + static IP
 ├── helm/                         # Helm chart configurations
 │   ├── metallb/
 │   │   ├── values.yaml           # MetalLB configuration
 │   │   └── ipaddresspool.yaml    # IP pool definition
 │   ├── traefik/
 │   │   └── values.yaml           # Traefik configuration
 │   ├── longhorn/
 │   │   └── values.yaml           # Longhorn configuration
 │   ├── pihole/
 │   │   └── values.yaml           # Pi-hole configuration
 │   └── heimdall/
 │       └── values.yaml           # Heimdall configuration
 ├── secrets/                      # Unencrypted secrets (NEVER commit)
 │   └── pihole-password.yaml   # Example secret template
 ├── sealedsecrets/                # Encrypted secrets (SAFE to commit)
 └── manifests/                    # Kubernetes manifests
      ├── cluster-issuer.yaml       # Cert-manager issuer
      ├── wildcard-cert.yaml        # Wildcard certificate
      ├── pihole-ingress.yaml     # Pi-hole ingress
      └── longhorn-ingress.yaml   # Longhorn ingress
```

---

## Important Notes

### Security

⚠️ **USE SEALED SECRETS FOR PRODUCTION**

-   See [SEALED_SECRETS.md](SEALED_SECRETS.md) for complete guide on encrypting secrets
-   Sealed Secrets allows you to safely commit encrypted secrets to public GitHub
-   Only your cluster can decrypt the secrets (no private keys in repository!)
-   Currently using temporary passwords - migrate to Sealed Secrets for production

⚠️ **CHANGE DEFAULT PASSWORDS**

-   Pi-hole admin password is currently `newpassword`
-   Use Sealed Secrets workflow to set a secure password (see SEALED_SECRETS.md)

### Limitations

-   **Single node cluster**: No high availability yet
-   **Longhorn**: Still completing initialization (normal for first deployment)
-   **Pi-hole**: Running without persistence (will be added when Longhorn is ready)
-   **Self-signed certificates**: HTTPS uses self-signed certificates (browsers will show warnings). See [Importing CA Certificate](#importing-self-signed-ca-certificate) to eliminate warnings.

### Maintenance

-   **Backups**: Set up regular backups of Pi-hole configuration and Longhorn volumes
-   **Updates**: Keep Kubernetes, Talos, and applications updated
-   **Monitoring**: Consider deploying Prometheus + Grafana for metrics

---

## Troubleshooting

### MetalLB LoadBalancer Services Not Responding

**Symptom**: Services have EXTERNAL-IP assigned but cannot access them from external network

**Common Signs**:
- `kubectl get svc` shows EXTERNAL-IP but services don't respond
- `ping 192.168.1.50` times out or shows "Host is down"
- `arp -a | grep 192.168.1.50` shows "incomplete" or null MAC (00:00:00:00:00:00)
- No "announcing from node" events in service events

**Root Cause**: Talos Linux automatically adds `node.kubernetes.io/exclude-from-external-load-balancers` label to control plane nodes (Kubernetes best practice for multi-node production clusters). MetalLB respects this label by default and won't announce services from excluded nodes. In single-node clusters where the control plane must host services, MetalLB needs to be configured to **ignore** this label.

**❌ INCORRECT Solution** (temporary fix that gets reset):
```bash
# DON'T DO THIS - label gets reapplied by Talos
kubectl label node <node-name> node.kubernetes.io/exclude-from-external-load-balancers-
```

**✅ CORRECT Solution** (permanent fix via Helm configuration):

```bash
# Configure MetalLB to ignore the exclusion label
helm upgrade metallb metallb/metallb -n metallb-system --set speaker.ignoreExcludeLB=true --reuse-values

# Wait for speaker to restart and pick up new configuration
kubectl wait --for=condition=ready pod -n metallb-system -l app.kubernetes.io/component=speaker --timeout=60s

# Verify the setting was applied
helm get values metallb -n metallb-system | grep ignoreExcludeLB
# Should output: ignoreExcludeLB: true
```

**Verification Steps**:

```bash
# 1. Check for new announcement events (should be recent)
kubectl get events -n traefik --sort-by='.lastTimestamp' | grep -i announce
# Expected: "announcing from node talos-fy9-w02 with protocol layer2" (recent timestamp)

# 2. Test connectivity
ping -c 3 192.168.1.50  # Traefik - should respond
ping -c 3 192.168.1.51  # Pi-hole - should respond

# 3. Test HTTP access
curl -I http://192.168.1.50/      # Should return HTTP 404 (expected from Traefik)
curl -I http://192.168.1.51/      # Should return HTTP 403 (expected from Pi-hole)

# 4. Check ARP resolution
arp -a | grep "192.168.1.5"
# Should show proper MAC addresses, not (incomplete) or 00:00:00:00:00:00

# 5. Verify MetalLB speaker is announcing
kubectl logs -n metallb-system -l app.kubernetes.io/component=speaker --tail=50 | grep -i announce
# Should see "created ARP responder for interface enp2s0"
```

**Additional Debugging**:

If the above solution doesn't work, check these additional items:

```bash
# Verify L2Advertisement configuration has correct interface
kubectl get l2advertisement -n metallb-system homelab-l2 -o yaml
# Should show: interfaces: [enp2s0]

# Check that speaker pods are running
kubectl get pods -n metallb-system
# Expected: speaker pods should be 4/4 Running

# Verify IP pool exists
kubectl get ipaddresspool -n metallb-system
# Should show: homelab-pool with addresses 192.168.1.50-192.168.1.99

# Check for network sysctls (optional optimization)
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 read /proc/sys/net/ipv4/ip_forward
# Should output: 1
```

**Why This Works**: The `speaker.ignoreExcludeLB: true` setting is a permanent configuration that tells MetalLB to announce LoadBalancer services even on nodes with the `exclude-from-external-load-balancers` label. This survives node reboots and cluster restarts, unlike manually removing the label which gets reapplied by Talos.

**Reference**: See [MetalLB Load Balancer section](#1-metallb-load-balancer) for complete configuration details.

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

# Common issues:
# - Image pull errors
# - Resource constraints
# - PersistentVolumeClaim pending (Longhorn still initializing)
```

### DNS Not Resolving

```bash
# Test Pi-hole DNS
nslookup traefik.homelab.local 192.168.1.51

# Check Pi-hole is running
kubectl get pods -n pihole

# Check Pi-hole service has IP
kubectl get svc -n pihole

# Verify custom DNS entries in Pi-hole admin UI
```

### Can't Access Services via homelab.local

1. Ensure your device is using Pi-hole for DNS (192.168.1.51)
2. Check DNS resolution works: `nslookup service.homelab.local 192.168.1.51`
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
