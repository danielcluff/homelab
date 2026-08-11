#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TALOSCONFIG_PATH="${ROOT}/talosconfig"
CONTROL_PLANE=192.168.1.41
RETENTION_COUNT="${ETCD_SNAPSHOT_RETENTION_COUNT:-14}"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 /absolute/off-cluster/backup/directory" >&2
  exit 1
fi

BACKUP_DIR=$1
if [[ "${BACKUP_DIR}" != /* || "${BACKUP_DIR}" == "/" || "${BACKUP_DIR}" == "/Users" || "${BACKUP_DIR}" == "/var" ]]; then
  echo "refusing unsafe backup directory: ${BACKUP_DIR}" >&2
  exit 1
fi
if [[ ! "${RETENTION_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ETCD_SNAPSHOT_RETENTION_COUNT must be a positive integer" >&2
  exit 1
fi
if [[ ! -s "${TALOSCONFIG_PATH}" ]]; then
  echo "Talos config not found: ${TALOSCONFIG_PATH}" >&2
  exit 1
fi

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
FINAL_PATH="${BACKUP_DIR}/homelab-etcd-${TIMESTAMP}.snapshot"
TEMP_PATH="${FINAL_PATH}.partial"

cleanup() {
  rm -f "${TEMP_PATH}"
}
trap cleanup EXIT

talosctl --talosconfig="${TALOSCONFIG_PATH}" \
  --nodes "${CONTROL_PLANE}" \
  etcd status >/dev/null

talosctl --talosconfig="${TALOSCONFIG_PATH}" \
  --nodes "${CONTROL_PLANE}" \
  etcd snapshot "${TEMP_PATH}"

chmod 600 "${TEMP_PATH}"
mv "${TEMP_PATH}" "${FINAL_PATH}"
shasum -a 256 "${FINAL_PATH}" > "${FINAL_PATH}.sha256"
chmod 600 "${FINAL_PATH}.sha256"

# Keep the newest N snapshot/checksum pairs in this exact directory.
find "${BACKUP_DIR}" -maxdepth 1 -type f -name 'homelab-etcd-*.snapshot' -print \
  | sort -r \
  | tail -n "+$((RETENTION_COUNT + 1))" \
  | while IFS= read -r old_snapshot; do
      rm -f -- "${old_snapshot}" "${old_snapshot}.sha256"
    done

echo "snapshot: ${FINAL_PATH}"
echo "retained: ${RETENTION_COUNT}"
