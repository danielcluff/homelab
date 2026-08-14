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

`elate.me` and `elate.biz` are managed by this Application.

Orphan warnings are enabled so unexpected workload resources in the managed
namespace are visible in Argo CD. Namespace infrastructure outside the
project's allowed kinds remains managed by the `homelab` repository.
