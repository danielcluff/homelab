# Application registry

Authenticated CNCF Distribution Registry v3 for application build artifacts.
It is available only on the homelab LAN as `https://images.elate.me` through the
internal Traefik controller. It has no LoadBalancer Service, public DNS record,
public Traefik route, or Cloudflare Tunnel route.

## Security model

- TLS terminates at internal Traefik using a cert-manager DNS-01 certificate.
- Distribution validates bcrypt credentials from the
  `application-registry-auth` Secret.
- The registry pod cannot start if the auth Secret or `htpasswd` key is absent.
- The Service is ClusterIP-only and Cilium accepts registry traffic only from
  internal Traefik plus node-originated health probes.
- Application workloads reference the separate `application-registry-pull`
  image pull Secret in their namespace.
- The registry uses one filesystem-backed Longhorn volume and a `Recreate`
  rollout strategy to avoid concurrent writers to a ReadWriteOnce volume.

Distribution's native `htpasswd` backend authenticates users but does not offer
per-repository or pull-versus-push authorization. Network boundaries and scoped
credential placement provide the practical separation for this initial setup.

## Bootstrap

Do not install the chart until its SealedSecrets have been generated.

```bash
# Creates bcrypt registry auth and a Docker pull config, then seals both.
./scripts/seal-application-registry-secrets.sh

# Create/classify the namespace and install its fail-closed Cilium policy.
helm upgrade --install network-policies helm/network-policies \
  --namespace kube-system

kubectl apply -f sealedsecrets/application-registry-auth-sealed.yaml
kubectl apply -f sealedsecrets/application-registry-pull-sealed.yaml

# Add the split-DNS record before using the hostname from LAN clients.
helm upgrade pihole mojo2600/pihole \
  --namespace pihole \
  -f helm/pihole/values.yaml

helm upgrade --install application-registry helm/application-registry \
  --namespace application-registry \
  --wait --timeout 5m
```

Store the chosen username and password in the password manager. The same
credential can be added to the trusted CI runner later; never commit it to an
application repository or this repository.

## Verification

The unauthenticated v2 endpoint must return `401`, not `200`:

```bash
curl -i https://images.elate.me/v2/
docker login images.elate.me
curl -u '<username>' https://images.elate.me/v2/
```

After login, test a disposable image push and pull before enabling application
publishing workflows. Confirm that no Cloudflare Tunnel route exists for the
hostname.

## Storage and garbage collection

The retained PVC protects data from an accidental Helm uninstall but is not an
off-cluster backup. Add registry data to the off-cluster backup plan before it
becomes the only copy of important application images.

Distribution garbage collection is stop-the-world: stop the registry or switch
it to read-only before running `registry garbage-collect`. Never collect while a
pipeline can push because an in-progress layer can be removed as unreferenced.

