#!/usr/bin/env bash
set -euo pipefail

registry="${REGISTRY:-192.168.1.53:5000}"
tag="${1:-$(date -u +%Y%m%d)}"
image="${registry}/code-server-homelab:${tag}"
attestation_args=()
output_args=(--push --tag "${image}")
builder_args=()

if [[ "${ENABLE_ATTESTATIONS:-false}" == "true" ]]; then
  attestation_args+=(--provenance=true --sbom=true)
fi

if [[ "${INSECURE_REGISTRY:-true}" == "true" ]]; then
  builder="homelab-registry"
  if ! docker buildx inspect "${builder}" >/dev/null 2>&1; then
    docker buildx create \
      --name "${builder}" \
      --driver docker-container \
      --config images/code-server-homelab/buildkitd.toml
  fi
  docker buildx inspect --bootstrap "${builder}" >/dev/null
  builder_args=(--builder "${builder}")
  output_args=(--output "type=registry,name=${image},registry.insecure=true")
fi

docker buildx build \
  "${builder_args[@]}" \
  --file images/code-server-homelab/Dockerfile \
  --platform linux/amd64 \
  "${attestation_args[@]}" \
  "${output_args[@]}" \
  .

if [[ "${INSECURE_REGISTRY:-true}" == "true" ]]; then
  curl --fail --silent --show-error --head \
    --header 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
    "http://${registry}/v2/code-server-homelab/manifests/${tag}" \
    | tr -d '\r' \
    | grep -i '^docker-content-digest:'
else
  docker buildx imagetools inspect "${image}"
fi
