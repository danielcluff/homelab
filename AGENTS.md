# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

Homelab Kubernetes cluster running on Talos Linux v1.11.6 with Kubernetes v1.34.1. Three-node cluster (1 control plane + 2 workers) with MetalLB for load balancing, Traefik for ingress, Longhorn for storage, Pi-hole for DNS, and cert-manager with Let's Encrypt for TLS.

All services are accessible under the `*.elate.me` wildcard domain with valid Let's Encrypt certificates via Cloudflare DNS-01 validation.

## Common Commands

```bash
# Cluster connection
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 health
kubectl get nodes -o wide
kubectl get pods -A

# Service status
kubectl get svc -A | grep LoadBalancer
kubectl get ingress -A

# Helm operations
helm list -A
helm upgrade <release> <chart> -n <namespace> -f helm/<chart>/values.yaml

# Talos operations
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 version
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 service
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 logs

# Debugging
kubectl logs -n <namespace> <pod>
kubectl describe pod -n <namespace> <pod>
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

## Infrastructure

### Cluster Nodes

| Node            | IP             | Role          | Disk          |
|-----------------|----------------|---------------|---------------|
| Control Plane   | 192.168.1.41   | control plane | /dev/nvme0n1  |
| Worker 1        | 192.168.1.42   | worker        | /dev/nvme0n1  |
| Worker 2        | 192.168.1.43   | worker        | /dev/nvme0n1  |

All nodes use interface `enp2s0` with static IPs, gateway `192.168.1.1`, and DNS `192.168.1.1`.

### Network Layout

| Resource         | IP/Range          | Purpose                        |
|------------------|-------------------|--------------------------------|
| Gateway          | 192.168.1.1       | Router                         |
| Debian Box       | 192.168.1.40      | Management server              |
| Control Plane    | 192.168.1.41      | Kubernetes API (port 6443)     |
| Worker 1         | 192.168.1.42      | Kubernetes worker              |
| Worker 2         | 192.168.1.43      | Kubernetes worker              |
| Traefik          | 192.168.1.50      | Ingress controller (*.elate.me)|
| Pi-hole          | 192.168.1.51      | DNS + ad blocking              |
| Registry         | 192.168.1.53      | Docker registry (port 5000)    |
| MetalLB Pool     | 192.168.1.50-99   | LoadBalancer IPs               |

### Deployed Services

| Service       | Namespace        | URL                            | Type         |
|---------------|------------------|--------------------------------|--------------|
| Heimdall      | heimdall         | https://dashboard.elate.me     | Helm         |
| Traefik       | traefik          | https://traefik.elate.me       | Helm         |
| Pi-hole       | pihole           | https://pihole.elate.me/admin  | Helm         |
| Longhorn      | longhorn-system  | https://longhorn.elate.me      | Helm         |
| Grafana       | monitoring       | https://grafana.elate.me       | Helm         |
| Prometheus    | monitoring       | (internal only)                | Helm         |
| Uptime Kuma   | uptime-kuma      | https://uptime.elate.me        | Manifest     |
| Code Server   | devenv           | https://dev.elate.me           | Manifest     |
| Code Server   | devenv           | https://homelab.elate.me       | Manifest     |
| Registry      | registry         | https://registry.elate.me      | Manifest     |
| Moseca (audio)| moseca           | https://audio.elate.me         | Manifest (on-demand) |
| Tailscale     | tailscale        | (subnet router, no UI)         | Manifest     |

### Pi-hole Custom DNS Entries

All `*.elate.me` subdomains resolve via Pi-hole (`helm/pihole/values.yaml`):

| Domain                | IP             |
|-----------------------|----------------|
| dashboard.elate.me    | 192.168.1.50   |
| traefik.elate.me      | 192.168.1.50   |
| longhorn.elate.me     | 192.168.1.50   |
| pihole.elate.me       | 192.168.1.51   |
| dev.elate.me          | 192.168.1.50   |
| homelab.elate.me      | 192.168.1.50   |
| grafana.elate.me      | 192.168.1.50   |
| uptime.elate.me       | 192.168.1.50   |
| audio.elate.me        | 192.168.1.50   |

## Repository Structure

```
homelab/
├── helm/                              # Helm value files by service
│   ├── metallb/                       # MetalLB config + IP pool
│   │   ├── values.yaml
│   │   ├── config.yaml
│   │   └── ipaddresspool.yaml
│   ├── traefik/values.yaml            # Ingress controller
│   ├── longhorn/values.yaml           # Storage
│   ├── pihole/values.yaml             # DNS + ad blocking
│   ├── heimdall/values.yaml           # Dashboard
│   ├── code-server/                   # Main and homelab dev environments
│       ├── values-main.yaml           # dev.elate.me
│       ├── values-homelab.yaml        # homelab.elate.me
│       └── values-project1.yaml       # Template for new projects
│   ├── cert-manager/                  # Official chart values (v1.16.2)
│   ├── sealed-secrets/                # Vendored official chart (2.19.1)
│   ├── grafana/                       # Grafana, datasource, and ingress
│   ├── moseca/                        # On-demand audio service
│   ├── openvpn/                       # TAP OpenVPN server
│   ├── registry/                      # Local Docker registry
│   ├── tailscale/                     # Tailscale subnet router
│   └── uptime-kuma/                   # Uptime monitoring
├── manifests/                         # Raw Kubernetes manifests
│   ├── cluster-issuer.yaml            # Self-signed issuer (fallback)
│   ├── letsencrypt-cloudflare-issuer.yaml  # Let's Encrypt ClusterIssuer
│   ├── wildcard-cert-letsencrypt.yaml # *.elate.me certificate
│   ├── https-redirect-middleware.yaml # HTTP→HTTPS redirect
│   ├── devpod-rbac.yaml               # DevPod workspace RBAC
│   ├── longhorn-ingress.yaml          # longhorn.elate.me ingress
│   ├── pihole-ingress.yaml            # pihole.elate.me ingress
│   └── metallb-*.yaml                 # MetalLB pod security policies
├── talos-patches/                     # Talos machine config patches
│   ├── fix-nodeip-controlplane.yaml   # Forces kubelet to use 192.168.1.0/24
│   ├── fix-kernel-modules.yaml        # Loads nbd, iscsi_tcp, configfs for Longhorn
│   ├── worker-192.168.1.42.yaml       # Worker 1 patch
│   ├── worker-192.168.1.42-final.yaml # Worker 1 full config
│   └── worker-192.168.1.43-final.yaml # Worker 2 full config
├── scripts/                           # Utility scripts
│   ├── setup-uptime-kuma.sh           # Configure Uptime Kuma monitors (bash)
│   ├── setup-uptime-kuma-socketio.js  # Configure Uptime Kuma monitors (Socket.IO)
│   ├── cleanup-uptime-kuma-duplicates.js  # Remove duplicate monitors
│   └── package.json                   # Node deps (socket.io-client)
├── secrets/                           # Unencrypted secrets (gitignored)
├── devpod/                            # DevPod configuration
│   ├── provider.yaml                  # Kubernetes provider config
│   └── README.md
├── .devcontainer/                     # Dev container configs for DevPod
│   ├── devcontainer.json              # Basic (Node.js + Python)
│   └── devcontainer-with-docker.json  # With Docker-in-Docker
├── .Codex/                           # Codex settings
│   ├── commands/add-node.md           # Custom command: add a Talos node
├── generate-talos-config.sh           # Generate Talos node configs with patches
├── MONITORING_SETUP.md                # Grafana + Prometheus + Uptime Kuma guide
└── QUICK_START_MONITORING.md          # Quick monitoring setup reference
```

## Key Patterns

### Adding a New Service

1. Create Helm values file in `helm/<service>/values.yaml` or manifest in `manifests/<service>.yaml`
2. Create ingress (either in Helm values or as separate manifest)
3. Add DNS entry to `helm/pihole/values.yaml` under `customDnsEntries` pointing to `192.168.1.50`
4. Deploy and verify via `kubectl get ingress -A`

### TLS Certificates

All services use a wildcard certificate for `*.elate.me` managed by cert-manager with Let's Encrypt (Cloudflare DNS-01 validation):

- **ClusterIssuer**: `letsencrypt-cloudflare` (defined in `manifests/letsencrypt-cloudflare-issuer.yaml`)
- **Certificate**: `elate-me-tls` in cert-manager namespace (defined in `manifests/wildcard-cert-letsencrypt.yaml`)
- **Secret name**: `elate.me-tls` (referenced by all ingresses)
- **Email**: daniel@elate.me
- **Renewal**: 90 days validity, renews 15 days before expiry

Ingresses reference the cert with these annotations:
```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-cloudflare
  traefik.ingress.kubernetes.io/router.tls: "true"
tls:
  - secretName: elate.me-tls
    hosts:
      - <service>.elate.me
```

### MetalLB on Talos

MetalLB requires `speaker.ignoreExcludeLB: true` because Talos labels control plane nodes with `exclude-from-external-load-balancers`. Configured in `helm/metallb/values.yaml`. The speaker also has explicit ARP settings for interface `enp2s0`.

### Longhorn Storage

Default storage class. All PVCs use `storageClassName: longhorn`. Replica count is set to 1. Kernel modules `nbd`, `iscsi_tcp`, and `configfs` must be loaded on all nodes (configured via talos-patches).

### Dev Environment Architecture

Three code-server instances in the `devenv` namespace share a 50Gi PVC (`devenv-shared`) mounted at `/mnt/shared`. Each has its own workspace PVC. The homelab instance (`homelab.elate.me`) has full cluster admin RBAC and auto-installs kubectl, helm, git, Codex, and Open Code on startup.

### Docker Registry

Local Docker registry at `192.168.1.53:5000` (also at `registry.elate.me`). Used by Moseca for container images. Images are pushed via `docker push registry.elate.me/<image>:<tag>`.

### On-Demand Services

Some services are resource-intensive and should only run when needed. They are scaled to zero by default.

| Service        | Alias  | Start                                                     | Stop                                                       |
|----------------|--------|-----------------------------------------------------------|-------------------------------------------------------------|
| Moseca (audio) | audio  | `kubectl scale deployment/moseca -n moseca --replicas=1`  | `kubectl scale deployment/moseca -n moseca --replicas=0`   |

### Tailscale Remote Access

Subnet router in `tailscale` namespace advertises `192.168.1.0/24` to Tailscale network. Requires auth key stored in `tailscale-auth` secret. Device name: `homelab-k8s-subnet-router`. Routes must be approved in Tailscale admin console.

## Important Notes

- **Domain**: All services use `*.elate.me` with valid Let's Encrypt certificates
- **Talos config**: Always use `--talosconfig=./talosconfig` flag
- **Pi-hole password**: Managed by `sealedsecrets/pihole-password-sealed.yaml`; plaintext input is gitignored
- **Grafana login**: Managed in Grafana; credentials are not stored in this repository
- **Kubelet nodeIP**: Every node uses `nodeIP.validSubnets: 192.168.1.0/24` to avoid Tailscale IP conflicts (see `talos-patches/fix-nodeip-controlplane.yaml`)
- **Cluster name**: `homelab` (Talos context: `homelab-007`)
- **Pod/Service networks**: Pods use `10.244.0.0/16`, services use `10.96.0.0/12`
- **All tolerations**: Services include control-plane tolerations for scheduling flexibility
- **Gitignored**: `talosconfig`, `controlplane.yaml`, `worker.yaml`, `secrets/`, `.env`, `*.key`, `*.pem`
