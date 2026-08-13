#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
AUTH_OUTPUT="${ROOT}/sealedsecrets/application-registry-auth-sealed.yaml"
PULL_OUTPUT="${ROOT}/sealedsecrets/application-registry-pull-sealed.yaml"
REGISTRY_HOST=images.elate.me
AUTH_NAMESPACE=application-registry
AUTH_SECRET=application-registry-auth
PULL_NAMESPACE=public-sites
PULL_SECRET=application-registry-pull

for command in base64 htpasswd jq kubectl kubeseal; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "required command not found: ${command}" >&2
    exit 1
  fi
done

read -r -p "Registry username [ci-publisher]: " REGISTRY_USERNAME
REGISTRY_USERNAME=${REGISTRY_USERNAME:-ci-publisher}

if [[ ! "${REGISTRY_USERNAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{2,63}$ ]]; then
  echo "username must be 3-64 characters using letters, numbers, dot, underscore, or hyphen" >&2
  exit 1
fi

read -r -s -p "Registry password: " REGISTRY_PASSWORD
echo
read -r -s -p "Confirm registry password: " REGISTRY_PASSWORD_CONFIRM
echo

if [[ "${REGISTRY_PASSWORD}" != "${REGISTRY_PASSWORD_CONFIRM}" ]]; then
  echo "passwords do not match" >&2
  unset REGISTRY_PASSWORD REGISTRY_PASSWORD_CONFIRM
  exit 1
fi

if (( ${#REGISTRY_PASSWORD} < 20 )); then
  echo "password must be at least 20 characters" >&2
  unset REGISTRY_PASSWORD REGISTRY_PASSWORD_CONFIRM
  exit 1
fi

umask 077
HTPASSWD_FILE=$(mktemp)
DOCKER_CONFIG_FILE=$(mktemp)
cleanup() {
  rm -f "${HTPASSWD_FILE}" "${DOCKER_CONFIG_FILE}"
  unset REGISTRY_PASSWORD REGISTRY_PASSWORD_CONFIRM REGISTRY_AUTH
}
trap cleanup EXIT

# Distribution accepts bcrypt entries only. -i reads the password from stdin so
# it never appears in the process list.
printf '%s\n' "${REGISTRY_PASSWORD}" | \
  htpasswd -nBi -C 12 "${REGISTRY_USERNAME}" > "${HTPASSWD_FILE}"

REGISTRY_AUTH=$(printf '%s:%s' "${REGISTRY_USERNAME}" "${REGISTRY_PASSWORD}" | \
  base64 | tr -d '\n')

jq -n \
  --arg host "${REGISTRY_HOST}" \
  --arg username "${REGISTRY_USERNAME}" \
  --arg password "${REGISTRY_PASSWORD}" \
  --arg auth "${REGISTRY_AUTH}" \
  '{auths: {($host): {username: $username, password: $password, auth: $auth}}}' \
  > "${DOCKER_CONFIG_FILE}"

kubectl create secret generic "${AUTH_SECRET}" \
  --namespace "${AUTH_NAMESPACE}" \
  --from-file=htpasswd="${HTPASSWD_FILE}" \
  --dry-run=client \
  --output=yaml | \
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  --sealed-secret-file "${AUTH_OUTPUT}"

kubectl create secret generic "${PULL_SECRET}" \
  --namespace "${PULL_NAMESPACE}" \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson="${DOCKER_CONFIG_FILE}" \
  --dry-run=client \
  --output=yaml | \
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  --sealed-secret-file "${PULL_OUTPUT}"

echo "wrote ${AUTH_OUTPUT}"
echo "wrote ${PULL_OUTPUT}"
echo "store the username and password in the password manager before closing this shell"

