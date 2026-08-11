# Public Traefik controller

This chart installs a second Traefik controller for public applications. It is
separate from the LAN-facing `traefik` release and has these boundaries:

- upstream chart 41.2.0 runs Traefik 3.7.10 from an immutable image digest;

- `ClusterIP` only; it receives no MetalLB address and opens no node port.
- only `Ingress` objects with the `kubernetes.io/ingress.class:
  traefik-public` annotation are handled; hardened cluster-scope discovery is
  incompatible with `spec.ingressClassName` lookup;
- only namespaces listed under `providers.kubernetesIngress.namespaces` are
  watched;
- cluster-scope discovery is disabled and RBAC is scoped to those public
  namespaces; the controller cannot read Nodes or internal Services,
  Ingresses, Pods, EndpointSlices, or Secrets;
- the dashboard and Kubernetes CRD provider are disabled;
- Cloudflare performs public TLS termination and forwards HTTP to the `web`
  entrypoint;
- Cilium permits no application backends until each selector and port is
  explicitly added.
- two resource-bounded replicas use preferred cross-node spreading and a
  PodDisruptionBudget requiring one available controller;
- the namespace enforces the Kubernetes Restricted Pod Security standard.

## Install

```bash
helm dependency update helm/traefik-public
helm upgrade --install traefik-public helm/traefik-public \
  --namespace traefik-public --create-namespace --skip-crds
kubectl rollout status deployment/traefik-public -n traefik-public --timeout=5m
```

`--skip-crds` is required because the internal Traefik release already owns the
cluster-wide Traefik and Hub CRDs. This controller uses only standard
Kubernetes `Ingress` resources and does not need those CRDs.

Installing this release does not itself change any Cloudflare route. The
current `elate.me` and `elate.biz` routes both target this controller.

After an upgrade, verify both routes externally and confirm that Cilium did not
deny expected `cloudflared` to Traefik or Traefik to backend flows. Roll back to
the prior Helm revision if either route fails:

```bash
helm history traefik-public -n traefik-public
helm rollback traefik-public <previous-revision> -n traefik-public --wait
```

## Adding a public application

1. Add its namespace to the provider namespace list in `values.yaml`.
2. Add a narrow Traefik-to-workload egress rule and reciprocal workload ingress
   rule to the network-policy chart.
3. Create an `Ingress` using the `kubernetes.io/ingress.class:
   traefik-public` annotation.
4. Test from inside the cloudflared pod against
   `http://traefik-public.traefik-public.svc.cluster.local` with the intended
   `Host` header.
5. Change the Cloudflare route only after Hubble confirms there are no denied
   or unexpected flows.
6. After public verification, remove the application's old direct cloudflared
   egress and ingress permissions. Rollback requires restoring those two rules
   before changing the Tunnel route back to the application Service.

Never add the internal Traefik namespace, internal application namespaces, LAN
CIDRs, or a namespace-wide/cluster-wide backend allow rule to this controller.
