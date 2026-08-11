#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUTPUT="${ROOT}/sealedsecrets/alertmanager-discord-config-sealed.yaml"
NAMESPACE=monitoring
SECRET_NAME=alertmanager-discord-config

for command in jq kubectl kubeseal; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "required command not found: ${command}" >&2
    exit 1
  fi
done

read -r -s -p "Discord webhook URL: " DISCORD_WEBHOOK
echo

if [[ ! "${DISCORD_WEBHOOK}" =~ ^https://(discord\.com|discordapp\.com)/api/webhooks/[0-9]+/[A-Za-z0-9._-]+$ ]]; then
  echo "the value does not look like a Discord webhook URL" >&2
  unset DISCORD_WEBHOOK
  exit 1
fi

CONFIG_FILE=$(mktemp)
chmod 600 "${CONFIG_FILE}"
cleanup() {
  rm -f "${CONFIG_FILE}"
  unset DISCORD_WEBHOOK
}
trap cleanup EXIT

jq -n --arg webhook "${DISCORD_WEBHOOK}" '{
  global: {
    resolve_timeout: "5m"
  },
  route: {
    receiver: "discord",
    group_by: ["alertname", "namespace", "deployment"],
    group_wait: "30s",
    group_interval: "5m",
    repeat_interval: "3h"
  },
  receivers: [
    {
      name: "discord",
      discord_configs: [
        {
          webhook_url: $webhook,
          send_resolved: true
        }
      ]
    }
  ]
}' > "${CONFIG_FILE}"

kubectl create secret generic "${SECRET_NAME}" \
  --namespace "${NAMESPACE}" \
  --from-file=alertmanager.yml="${CONFIG_FILE}" \
  --dry-run=client \
  --output=yaml | \
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  --sealed-secret-file "${OUTPUT}"

echo "wrote ${OUTPUT}"
echo "apply it, then upgrade Prometheus:"
echo "  kubectl apply -f sealedsecrets/alertmanager-discord-config-sealed.yaml"
echo "  helm upgrade prometheus prometheus-community/prometheus --version 28.2.1 -n monitoring -f helm/prometheus/values.yaml --wait --timeout 10m"
