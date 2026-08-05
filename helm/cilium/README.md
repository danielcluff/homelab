# Cilium

Cilium replaces Talos-managed Flannel as the cluster CNI and enforces
Kubernetes `NetworkPolicy`. The initial deployment deliberately retains
`kube-proxy` and MetalLB.

## Versions

- Cilium chart/app: `1.19.6`
- Talos target: `1.13.8`
- Kubernetes: the currently installed `1.34.1` (upgrade separately)

## Helm repository

```bash
helm repo add cilium https://helm.cilium.io/
helm repo update
```

## Render

```bash
helm template cilium cilium/cilium \
  --version 1.19.6 \
  --namespace kube-system \
  --values helm/cilium/values.yaml
```

Do not install this release alongside the Talos-managed Flannel CNI without
following `CILIUM_MIGRATION.md`.

