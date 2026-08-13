#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
render_dir="${1:-${repo_dir}/.trivy-rendered}"

case "${render_dir}" in
  "${repo_dir}/.trivy-rendered"|.trivy-rendered)
    ;;
  *)
    echo "destination must be ${repo_dir}/.trivy-rendered" >&2
    exit 1
    ;;
esac

if [[ "${render_dir}" == ".trivy-rendered" ]]; then
  render_dir="${repo_dir}/.trivy-rendered"
fi

rm -rf -- "${render_dir}"
mkdir -p "${render_dir}"

render_chart() {
  local release="$1"
  local chart="$2"
  local namespace="$3"
  local chart_dir="${repo_dir}/${chart}"

  # Dependency archives are intentionally gitignored. Rebuild them from the
  # committed lock file so this script also works from a clean CI checkout.
  if [[ -f "${chart_dir}/Chart.lock" ]]; then
    if [[ "${chart}" == "helm/traefik" || \
          "${chart}" == "helm/traefik-public" ]]; then
      helm repo add traefik https://traefik.github.io/charts \
        --force-update >/dev/null
    fi
    if [[ "${chart}" == "helm/argocd" ]]; then
      helm repo add argo https://argoproj.github.io/argo-helm \
        --force-update >/dev/null
    fi
    helm dependency build --skip-refresh "${chart_dir}" >/dev/null
  fi

  helm template "${release}" "${chart_dir}" \
    --namespace "${namespace}" \
    --include-crds \
    --output-dir "${render_dir}" >/dev/null
}

render_chart cloudflared helm/cloudflared cloudflare-tunnel
render_chart application-registry helm/application-registry application-registry
render_chart argocd helm/argocd argocd
render_chart argocd-bootstrap helm/argocd-bootstrap argocd
render_chart code-server helm/code-server devenv
render_chart grafana helm/grafana monitoring
render_chart longhorn-protection helm/longhorn-protection longhorn-system
render_chart monitoring-baseline helm/monitoring-baseline monitoring
render_chart network-policies helm/network-policies kube-system
render_chart openvpn helm/openvpn openvpn
render_chart public-sites helm/public-sites public-sites
render_chart registry helm/registry registry
render_chart tailscale helm/tailscale tailscale
render_chart traefik helm/traefik traefik
render_chart traefik-public helm/traefik-public traefik-public
render_chart uptime-kuma helm/uptime-kuma uptime-kuma

# Preserve repository-relative paths for standalone resources and scoped
# Trivy exceptions. Plaintext secrets are gitignored and are never copied.
mkdir -p "${render_dir}/manifests" "${render_dir}/sealedsecrets"
cp -R "${repo_dir}/manifests/." "${render_dir}/manifests/"
cp -R "${repo_dir}/sealedsecrets/." "${render_dir}/sealedsecrets/"

mkdir -p "${render_dir}/helm/public-sites/elate-me"
cp "${repo_dir}/helm/public-sites/elate-me/Dockerfile" \
  "${render_dir}/helm/public-sites/elate-me/Dockerfile"

mkdir -p "${render_dir}/images/code-server-homelab"
cp "${repo_dir}/images/code-server-homelab/Dockerfile" \
  "${render_dir}/images/code-server-homelab/Dockerfile"

echo "Rendered scan inputs to ${render_dir}"
