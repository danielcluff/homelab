# Argo CD application bootstrap

Creates a restricted `AppProject` and an `Application` for the public
`homelab-apps` GitOps repository. The project permits only the namespaced kinds
rendered by that chart and only in `public-sites`; all cluster-scoped resources
are denied.

Install this chart only after the Argo CD CRDs and controllers are healthy:

```bash
helm upgrade --install argocd-bootstrap helm/argocd-bootstrap \
  --namespace argocd
```

Both applications currently remain disabled in `homelab-apps`, so the first
sync is intentionally empty. Argo CD will not adopt or prune the existing
Helm-managed public site resources.
