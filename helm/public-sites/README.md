# Public Elate landing pages

This chart runs two independent, non-root NGINX containers:

- `elate-me.public-sites.svc.cluster.local` for `elate.me`
  - `/` serves `Elate`
  - `/hosting/` serves the hosting-at-home slides image
- `elate-biz.public-sites.svc.cluster.local` for `elate.biz` (inline `Elate.`)

The Services are ClusterIP-only and the site pods have no egress. Both domains
are routed through the isolated `traefik-public` controller using standard
Kubernetes Ingress resources. Neither site has a MetalLB address, local DNS
entry, or origin certificate.

```bash
# Rebuild/push elate.me image (slides from ~/dev/hosting-at-home/dist)
./scripts/deploy-elate-me-hosting.sh

# Or chart-only upgrade after the image already exists
helm upgrade --install public-sites helm/public-sites \
  --namespace public-sites \
  --wait --timeout 5m
```

Build the slides with `base: '/hosting'` before copying `dist/` into
`helm/public-sites/elate-me/hosting/`.

Cloudflare published routes:

| Public hostname | Tunnel service |
| --- | --- |
| `elate.me` | `http://traefik-public.traefik-public.svc.cluster.local:80` |
| `elate.biz` | `http://traefik-public.traefik-public.svc.cluster.local:80` |

Keep the final tunnel rule set to `http_status:404`.
