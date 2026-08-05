# Flannel to Cilium migration

This runbook replaces Talos-managed Flannel with Cilium while retaining
`kube-proxy` and MetalLB. Expect a maintenance window: existing pod network
connections will be interrupted and workloads must be recreated on Cilium.

## Fixed inputs

| Setting | Value |
|---|---|
| Talos current | 1.13.0 |
| Talos target | 1.13.8 |
| Image Factory schematic | `613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245` |
| Cilium | 1.19.6 |
| Pod CIDR | `10.244.0.0/16` |
| Service CIDR | `10.96.0.0/12` |
| API endpoint | `192.168.1.41:6443` |

The schematic preserves `iscsi-tools` and `util-linux-tools`; Cilium requires
no additional Talos system extension or custom kernel build.

## 1. Talos patch upgrade

The OS upgrade is independent of the CNI migration. Upgrade and validate one
node at a time, workers first and the single control plane last:

First apply the kubelet node-address patch to every node:

```bash
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41,192.168.1.42,192.168.1.43 \
  patch machineconfig --patch @talos-patches/fix-nodeip-controlplane.yaml
```

```bash
talosctl --talosconfig=./talosconfig --nodes 192.168.1.42 upgrade \
  --image factory.talos.dev/installer/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245:v1.13.8 \
  --wait
talosctl --talosconfig=./talosconfig --nodes 192.168.1.43 upgrade \
  --image factory.talos.dev/installer/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245:v1.13.8 \
  --wait
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 upgrade \
  --image factory.talos.dev/installer/613e1592b2da41ae5e265e8789429f22e121aab91cb4deb6bc3c0b6262961245:v1.13.8 \
  --wait
```

After each node, verify node readiness, Longhorn state, and extension versions.
Do not upgrade Kubernetes as part of this operation.

## 2. CNI preflight

Before the maintenance window:

```bash
talosctl --talosconfig=./talosconfig --nodes 192.168.1.41 health
kubectl get nodes -o wide
kubectl get pods -A
kubectl get volumes.longhorn.io -n longhorn-system
helm template cilium cilium/cilium --version 1.19.6 \
  --namespace kube-system --values helm/cilium/values.yaml >/tmp/cilium.yaml
```

Take an etcd snapshot and confirm application backups before changing CNI.
Keep console access to all three nodes available in case cluster networking is
unavailable during rollback.

### Current preflight findings

The 2026-08-05 preflight created an etcd snapshot successfully. Follow-up
remediation completed these items:

- Longhorn defaults and all existing volumes now use two replicas. All attached
  volumes rebuilt healthy across separate nodes. Replica auto-balance is
  `best-effort` and the protective drain policy remains enabled.
- Prometheus node-exporter runs on all nodes under a Helm-managed namespace
  Pod Security exception.
- Code-server's RWO topology, rollout strategy and blocking startup hook were
  corrected; both instances are healthy on the same node.
- The cert-manager Helm release is deployed and healthy.
- The two stale terminal DevPod pods were removed.

The Cloudflare DNS token and Tailscale subnet-router identity were rotated and
validated before the maintenance window. Their one-time enrollment keys were
revoked after successful registration.

## 3. Cutover

The exact live commands are intentionally performed interactively during the
maintenance window. The operation order is:

1. Scale nonessential workloads down and pause changes to the cluster.
2. Apply `talos-patches/cilium-cni.yaml` to all nodes, leaving kube-proxy enabled.
3. Remove any orphaned Flannel DaemonSet, ConfigMap, ServiceAccount,
   ClusterRole, and ClusterRoleBinding. Setting Talos CNI to `none` does not
   necessarily delete existing Kubernetes resources created by Flannel.
4. Install the pinned upstream Cilium chart:

   ```bash
   helm upgrade --install cilium cilium/cilium \
     --version 1.19.6 \
     --namespace kube-system \
     --values helm/cilium/values.yaml \
     --wait --timeout 10m
   ```

5. Wait for one healthy Cilium agent per node and healthy operators.
6. Recreate CoreDNS, then recreate ordinary workload pods so they receive
   Cilium-managed interfaces.
7. Scale PVC-backed applications down. Recreate each Longhorn instance-manager
   pod one node at a time, verify its `InstanceManager.status.ip` is a Cilium
   address, then restart the Longhorn manager DaemonSet to refresh cached
   clients. Wait until inactive volumes are fully detached before restoring
   workloads.
8. Restore Tailscale and OpenVPN first, then application workloads. Restore the
   homelab code-server before the main instance because the main deployment has
   a required affinity to it.
9. If kubelet reports a CSI staging path as no longer valid after the storage
   restart, recreate the affected pod. If stale runtime state persists, restart
   only kubelet on that node and wait for reconciliation.
10. Run Cilium connectivity tests and application-specific checks.

Do not apply default-deny policies until all expected traffic has been observed
with Hubble and explicit allow policies have been prepared.

## 4. Required validation

```bash
cilium status --wait
cilium connectivity test
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
```

Additionally verify:

- CoreDNS resolution from a new pod
- all MetalLB addresses `192.168.1.50-99`
- Traefik HTTP and HTTPS from the LAN
- Longhorn volume attach, read and write
- Pi-hole TCP and UDP DNS
- registry pull and push
- Tailscale subnet routing
- OpenVPN UDP connectivity
- Prometheus scraping and Grafana access

## 5. Rollback

Rollback is disruptive and requires console access:

1. Uninstall Cilium with the pinned chart tooling.
2. Revert the `cluster.network.cni.name` patch to `flannel` on all nodes.
3. Reboot nodes if stale CNI state prevents Flannel initialization.
4. Recreate all workload pods after Flannel is healthy.
5. Validate DNS, storage, MetalLB and ingress before ending maintenance.

Talos uses an A/B OS image scheme. If the separate Talos upgrade fails, use
`talosctl rollback` for the affected node; that is distinct from CNI rollback.
