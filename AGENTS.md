# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

Homelab Kubernetes cluster running on Talos Linux v1.13.8 with Kubernetes v1.34.1. Three-node cluster (1 control plane + 2 workers) with Cilium for CNI and NetworkPolicy, MetalLB for load balancing, Traefik for ingress, Longhorn for storage, Pi-hole for DNS, and cert-manager with Let's Encrypt for TLS.

Internal web services use the `*.elate.me` wildcard certificate issued through Cloudflare DNS-01. Public apex sites (`elate.me` and `elate.biz`) enter through Cloudflare Tunnel and the isolated public Traefik controller.

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
| Public Traefik| traefik-public   | elate.me, elate.biz (ClusterIP)| Helm         |
| Pi-hole       | pihole           | https://pihole.elate.me/admin  | Helm         |
| Longhorn      | longhorn-system  | https://longhorn.elate.me      | Helm         |
| Grafana       | monitoring       | https://grafana.elate.me       | Helm         |
| Prometheus    | monitoring       | (internal only)                | Helm         |
| Uptime Kuma   | uptime-kuma      | https://uptime.elate.me        | Helm         |
| Code Server   | devenv           | https://dev.elate.me           | Helm         |
| Code Server   | devenv           | https://homelab.elate.me       | Helm         |
| Registry      | registry         | https://registry.elate.me      | Helm         |
| Tailscale     | tailscale        | (subnet router, no UI)         | Helm         |
| Cloudflared   | cloudflare-tunnel| (outbound tunnel connector)    | Helm         |
| Public sites  | public-sites     | https://elate.me, https://elate.biz | Helm    |
| OpenVPN       | openvpn          | vpn.elate.me (disabled)        | Helm         |

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
│   ├── cloudflared/                   # Cloudflare Tunnel connector
│   ├── network-policies/              # Cilium policy and namespace classification
│   ├── openvpn/                       # TAP OpenVPN server
│   ├── public-sites/                  # elate.me and elate.biz workloads
│   ├── registry/                      # Local Docker registry
│   ├── tailscale/                     # Tailscale subnet router
│   ├── traefik-public/                # Isolated public ingress controller
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

1. Define the service with a Helm chart and values under `helm/<service>/`; new services must not be deployed as standalone manifests.
2. Create the Ingress through the service's Helm chart.
3. Add the backend workload selector and destination port to Traefik's egress policy in `helm/network-policies/templates/traefik.yaml`. Without this rule, Cilium will block Traefik from reaching the service and the Ingress will return a gateway error.
4. Add a DNS entry to `helm/pihole/values.yaml` under `customDnsEntries` pointing to `192.168.1.50`.
5. Deploy the Helm releases and verify the Ingress, the public endpoint, and Cilium/Hubble for denied Traefik-to-backend flows.

Public services use a separate path: deploy them in a namespace classified
`public`, expose only a ClusterIP Service, and route them through the isolated
`traefik-public` controller. Add exact backend rules to
`templates/traefik-public.yaml` and the reciprocal application policy.
Cloudflared may reach only the public controller. Never point Cloudflare Tunnel
at the internal Traefik controller or grant either public gateway broad cluster
egress.

### TLS Certificates

Internal `*.elate.me` services use a wildcard certificate managed by cert-manager with Let's Encrypt (Cloudflare DNS-01 validation):

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

Three code-server instances in the `devenv` namespace share a 50Gi PVC (`devenv-shared`) mounted at `/mnt/shared`. Each has its own workspace PVC. The homelab instance (`homelab.elate.me`) has full cluster admin RBAC and uses the pinned management image built from `images/code-server-homelab/Dockerfile`; tools must not be installed from a lifecycle hook.

### Docker Registry

Local Docker registry at `192.168.1.53:5000` (also exposed internally as `registry.elate.me`). It stores locally built workloads such as the `elate-me` site image. Use the private MetalLB address from LAN clients unless local DNS resolves `registry.elate.me` to the internal Traefik address.

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
