# Cloudflare Tunnel connector

This chart runs two replicas of a remotely managed Cloudflare Tunnel. The
connector is outbound-only and has no Kubernetes API credentials. Its Cilium
policy initially permits Cloudflare connectivity and DNS but no application
backends, so installing the connector cannot expose an internal service.
Transport mode is `auto`: cloudflared prefers QUIC over UDP/7844 and falls back
to HTTP/2 over TCP/7844 if a node's UDP path is unavailable.
The replicas are restricted to worker nodes and prefer different hosts, keeping
the public edge connector off the Kubernetes control plane.

## Cloudflare setup

1. In Cloudflare, create a remotely managed tunnel named `homelab-k8s`.
2. Give it a catch-all route with service `http_status:404`. Do not add an
   internal hostname or service.
3. Copy only the tunnel token from the Docker installation command.
4. Create `cloudflare-tunnel/cloudflared-tunnel-token` through the Sealed
   Secrets workflow documented in `SEALED_SECRETS.md`. The token is stored
   under the `api-token` key to match the repository's Cloudflare secret
   convention; it remains a separate credential from the DNS token.
5. Install the chart:

```bash
helm upgrade --install cloudflared helm/cloudflared \
  --namespace cloudflare-tunnel \
  --wait --timeout 5m
```

Verify both replicas report Ready and that Cloudflare shows two healthy
connectors:

```bash
kubectl get pods -n cloudflare-tunnel
kubectl logs -n cloudflare-tunnel deployment/cloudflared
```

The `cloudflared-metrics` Service is annotated for Prometheus discovery on
TCP/2000. The monitoring and cloudflared Cilium policies allow only this exact
scrape path.

## Publishing an application

Do not point a tunnel route at the internal Traefik controller or directly at
an application Service. Public applications must have a dedicated namespace
labeled `public`, a ClusterIP Service, and an Ingress using the
`traefik-public` IngressClass. Before adding the Cloudflare route, add exact
reciprocal backend rules to the public Traefik and application policies. Every
published hostname targets
`http://traefik-public.traefik-public.svc.cluster.local:80`; keep a final
`http_status:404` catch-all rule.

Only then add the published hostname in Cloudflare with a service such as:

```text
http://example.example-public.svc.cluster.local:8080
```

Keep the final catch-all route set to `http_status:404`. Apply Cloudflare Access
to administrative or authenticated applications; do not rely on an
application login page as the only protection for a management interface.
