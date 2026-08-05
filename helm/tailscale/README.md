# Tailscale subnet router

The tailnet requires hardware attestation. The router therefore stores its
TPM-bound node state on the Longhorn PVC (`TS_KUBE_SECRET=""`) instead of in a
portable Kubernetes Secret.

Before the first rollout with PVC-backed state, create a new reusable,
pre-approved auth key with the `tag:subnet-router` tag and update the existing
`tailscale-auth` Secret through the repository's Sealed Secrets workflow. Never
commit the plaintext key.

Then reconcile the release:

```bash
helm upgrade tailscale helm/tailscale \
  --namespace tailscale \
  --force-conflicts \
  --wait --timeout 5m
```

After the first successful login, the node identity persists on
`tailscale-state` and routine restarts no longer depend on the auth key.

