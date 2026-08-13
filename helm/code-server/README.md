# Code-server environments

This repository-owned Helm chart deploys two internal VS Code environments in
the `devenv` namespace:

| Deployment | URL | Purpose | Image |
|---|---|---|---|
| `code-server-main` | `https://dev.elate.me` | General development | Pinned upstream code-server image |
| `code-server-homelab` | `https://homelab.elate.me` | Cluster management | Repository-built management image |

Both environments have dedicated Longhorn workspace PVCs and mount the shared
`devenv-shared` PVC at `/mnt/shared`. The chart uses `Recreate` deployments and
pod affinity so the ReadWriteOnce shared volume is not attached to multiple
nodes during a rollout.

## Deploy

```bash
helm upgrade --install code-server helm/code-server \
  --namespace devenv \
  --create-namespace \
  --wait --timeout 10m
```

Validate the release:

```bash
kubectl rollout status deployment/code-server-main -n devenv
kubectl rollout status deployment/code-server-homelab -n devenv
kubectl get pods,pvc,ingress,certificate -n devenv
curl --resolve dev.elate.me:443:192.168.1.50 https://dev.elate.me/
curl --resolve homelab.elate.me:443:192.168.1.50 https://homelab.elate.me/
```

## Management image

`images/code-server-homelab/Dockerfile` extends the pinned upstream code-server
image with checksum-verified Node.js, kubectl, and Helm binaries plus pinned
Codex, Claude Code, and OpenCode packages. Package installation must happen at
image-build time, never in `postStart` or another lifecycle hook.

Build and push an amd64 image to the LAN registry:

```bash
./scripts/build-code-server-homelab.sh YYYYMMDD
```

The script prints the registry digest. Update `values.yaml`, render the chart,
and pass CI before deploying it. Kubernetes must pull the image by digest.

The local registry is plain HTTP on `192.168.1.53:5000`. The build script uses
the narrowly scoped BuildKit configuration committed beside the Dockerfile;
do not route image pushes through Cloudflare or the registry Ingress.

## TLS and ingress

The two Ingresses use separate secrets:

- `dev-elate-me-tls`
- `homelab-elate-me-tls`

cert-manager ingress-shim creates and renews both certificates with the
`letsencrypt-cloudflare` ClusterIssuer. Never reuse one TLS Secret for different
host lists, and never route either development environment through public
Traefik or Cloudflare Tunnel.

Traefik reaches these Services only through the exact selectors and ports in
`helm/network-policies/templates/traefik.yaml`. Update that policy whenever a
new environment is added.

## Adding an environment

`values-project1.yaml` is a reference, not a separately installed release. To
add an environment:

1. Add its Deployment, Service, PVC, and Ingress templates to this chart.
2. Use a unique hostname and TLS Secret name.
3. Add the exact Traefik-to-backend rule to the network-policy chart.
4. Add its internal hostname to Pi-hole.
5. Render and scan both charts before upgrading their existing Helm releases.

## Operations

```bash
kubectl exec -it -n devenv deployment/code-server-main -- bash
kubectl exec -it -n devenv deployment/code-server-homelab -- bash
kubectl logs -n devenv deployment/code-server-homelab
kubectl port-forward -n devenv service/code-server-main 8080:8080
```

Workspace PVCs carry `helm.sh/resource-policy: keep`; uninstalling the release
does not delete development data. Verify retained PVCs before any manual
storage cleanup.
