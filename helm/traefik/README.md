# Internal Traefik controller

This locked wrapper chart owns the LAN-facing Traefik release. It preserves the
MetalLB address `192.168.1.50`, the default `traefik` IngressClass, the Traefik
CRD provider, the dashboard, and the wildcard TLS certificate.

## Upgrade

Traefik 3.7 includes updated CRDs. Helm does not upgrade CRDs that are already
installed, so apply the CRDs from the locked dependency before upgrading the
controller:

```bash
helm dependency build helm/traefik
helm show crds helm/traefik/charts/traefik-41.2.0.tgz | \
  kubectl apply --server-side --force-conflicts -f -
helm upgrade --install traefik helm/traefik \
  --namespace traefik --create-namespace --skip-crds --wait --timeout 5m
kubectl rollout status deployment/traefik -n traefik --timeout=5m
```

Before and after the upgrade, verify that `service/traefik` remains a
`LoadBalancer` at `192.168.1.50` and test every internal ingress listed by
`kubectl get ingress -A`. If validation fails, preserve the upgraded CRDs and
roll the controller back to the previous Helm revision:

```bash
helm history traefik -n traefik
helm rollback traefik <previous-revision> -n traefik --wait --timeout 5m
```
