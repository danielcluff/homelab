#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-${HOME}/dev/hosting-at-home}"
TAG="${2:-hosting-$(date +%Y%m%d%H%M%S)}"
REGISTRY="${REGISTRY:-192.168.1.53:5000}"
IMAGE="${REGISTRY}/elate-me:${TAG}"
SITE_DIR="${ROOT}/helm/public-sites/elate-me"

if [[ ! -d "${SRC}/dist" ]]; then
  echo "missing ${SRC}/dist — build hosting-at-home first (base: /hosting)" >&2
  exit 1
fi

rm -rf "${SITE_DIR}/hosting"
cp -R "${SRC}/dist" "${SITE_DIR}/hosting"

docker buildx build --platform linux/amd64 -t "${IMAGE}" --load "${SITE_DIR}"
# Local registry is plain HTTP; skopeo avoids Docker's HTTPS client requirement.
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  quay.io/skopeo/stable:latest copy --dest-tls-verify=false \
  "docker-daemon:${IMAGE}" "docker://${IMAGE}"

# Keep values.yaml tag in sync for the next helm upgrade.
python3 - <<PY
from pathlib import Path
import re
path = Path("${ROOT}/helm/public-sites/values.yaml")
text = path.read_text()
text, n = re.subn(
    r'(repository: 192\.168\.1\.53:5000/elate-me\n\s+tag: )"[^"]*"',
    r'\1"${TAG}"',
    text,
    count=1,
)
if n != 1:
    raise SystemExit("failed to update elate-me image tag in values.yaml")
path.write_text(text)
PY

helm upgrade --install public-sites "${ROOT}/helm/public-sites" \
  --namespace public-sites \
  --wait --timeout 5m

echo "deployed ${IMAGE}"
echo "public: https://elate.me/hosting/"
