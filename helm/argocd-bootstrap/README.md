# Argo CD application bootstrap

Creates a restricted `AppProject` and an `Application` for the public
`homelab-apps` GitOps repository. The project permits only the namespaced kinds
rendered by that chart and only in `public-sites`; all cluster-scoped resources
are denied.

Install this chart only after the Argo CD CRDs and controllers are healthy:

```bash
helm upgrade --install argocd-bootstrap helm/argocd-bootstrap \
  --namespace argocd \
  --server-side=false
```

`elate.biz` is managed by this Application. `elate.me` remains disabled in
`homelab-apps` until its separate migration is completed.

Orphan warnings are disabled during this coexistence period. Enable them after
the legacy `public-sites` Helm release has been retired and Argo CD owns every
resource in the namespace.
