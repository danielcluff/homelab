# Argo CD

Pinned installation of the official Argo CD chart. The initial deployment is
ClusterIP-only and is administered with `kubectl` and local port-forwarding;
no public or internal Ingress is created during bootstrap.

The upstream chart's cluster-wide controller and server roles are disabled.
This wrapper grants the application controller an explicit Role in
`public-sites` containing only the resource kinds allowed by the matching
`AppProject`.

```bash
helm dependency build helm/argocd
helm upgrade --install argocd helm/argocd \
  --namespace argocd \
  --create-namespace
```

Retrieve the generated bootstrap password without committing it:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 --decode
```

After confirming access, store the password in the password manager and remove
the initial Secret. A later hardening phase should configure SSO, disable the
built-in admin account, and replace observe-mode networking with exact Cilium
policy.
