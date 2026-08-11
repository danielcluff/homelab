# Longhorn protection policy

This Helm chart owns recurring Longhorn recovery jobs separately from the
upstream Longhorn installation.

The initial policy creates a daily local snapshot at 03:15 and retains seven
snapshots per volume. Membership in the Longhorn `default` recurring-job group
automatically covers volumes that do not have an explicit recurring-job
assignment. Longhorn is configured to temporarily attach detached volumes so
they are protected too.

Local snapshots are useful for accidental deletion and application rollback,
but they share the cluster's disks and are not disaster-recovery backups.
Remote volume and Longhorn system jobs remain disabled until an off-cluster
backup target is configured.

```bash
helm upgrade --install longhorn-protection helm/longhorn-protection \
  --namespace longhorn-system --take-ownership --wait --timeout 5m

kubectl get recurringjobs.longhorn.io -n longhorn-system
kubectl get snapshots.longhorn.io -n longhorn-system
```
