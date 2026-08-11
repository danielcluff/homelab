# Disaster recovery

Replication keeps services available after a node failure, but it is not a
backup. Recovery uses three independent artifacts:

1. Talos `etcd` snapshots for Kubernetes control-plane state.
2. Longhorn remote volume and system backups for persistent data.
3. The Sealed Secrets controller recovery key for decrypting committed
   SealedSecrets after rebuilding the cluster.

## Current protection

- Every Longhorn volume receives a local snapshot daily at 03:15.
- Seven local snapshots per volume are retained.
- Detached volumes are temporarily attached for recurring jobs.
- **TODO (deferred):** Remote volume and system backups remain disabled until
  off-site backups become a priority and an off-cluster target is configured.
- **TODO (deferred):** Schedule Talos `etcd` snapshots to encrypted storage on
  the management host or another off-cluster destination.
- The Sealed Secrets recovery-key procedure is documented in
  `SEALED_SECRETS.md`; its external storage location is intentionally not
  recorded in Git.

## Talos etcd snapshots

`scripts/backup-etcd.sh` creates a consistent snapshot through the Talos API,
writes it atomically, records a SHA-256 checksum, and keeps the newest fourteen
snapshot/checksum pairs. The destination must be an absolute off-cluster mount
or synchronized directory.

```bash
./scripts/backup-etcd.sh /absolute/off-cluster/path/homelab/etcd
```

Schedule the command on the management host, not inside Kubernetes. Keeping
the Talos client credential outside the cluster avoids making recovery depend
on Kubernetes and avoids introducing a highly privileged credential into a
pod. A typical daily schedule is 02:15, before Longhorn's 03:15 snapshot job.

Never commit an etcd snapshot: it contains Kubernetes state, including Secret
objects. Restrict both the directory and files and encrypt the destination.

## Restore testing

Do not test an etcd restore against the running cluster. Use isolated hardware
or a disposable lab environment and follow the Talos disaster-recovery
procedure. For Longhorn, restore a backup to a new test volume and mount it in
a disposable namespace; never overwrite the source volume during a test.

Record the test date, snapshot age, restore duration, and any missing
dependencies outside this repository if they reveal private infrastructure.
