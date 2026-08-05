# Sealed Secrets

This repository uses [Bitnami Sealed Secrets](https://github.com/bitnami/sealed-secrets) for Kubernetes credentials. A `SealedSecret` is encrypted with the cluster controller's public key. It is safe to commit, but only the controller holding the matching private key can decrypt it into a normal Kubernetes `Secret`.

## Repository layout

- `secrets/` contains plaintext input manifests. The entire directory is gitignored and must never be committed.
- `sealedsecrets/` contains encrypted `SealedSecret` manifests and is safe to commit.
- Generated Talos configs (`talosconfig`, `controlplane.yaml`, `worker.yaml`, and `talos-patches/*-final.yaml`) also contain credentials and are gitignored. They are not Kubernetes Secrets and should not be processed with `kubeseal`.

The managed secrets are:

| Plaintext input                   | Encrypted manifest                             | Resulting Secret                                  | Consumer                               |
| --------------------------------- | ---------------------------------------------- | ------------------------------------------------- | -------------------------------------- |
| `secrets/pihole-password.yaml`    | `sealedsecrets/pihole-password-sealed.yaml`    | `pihole/pihole-password` (`password`)             | Pi-hole Helm release                   |
| Cloudflare DNS token (entered interactively; no plaintext file required) | `sealedsecrets/cloudflare-dns-sealed.yaml` | `cert-manager/cloudflare-dns-homelab-cert-manager` (`api-token`) | `letsencrypt-cloudflare` ClusterIssuer |

## Controller installation

The controller runs in `kube-system`. This cluster was installed from the official v0.38.4 release manifest:

```bash
kubectl apply -f https://github.com/bitnami/sealed-secrets/releases/download/v0.38.4/controller.yaml
kubectl rollout status deployment/sealed-secrets-controller -n kube-system
```

Install the client on macOS with `brew install kubeseal`, then verify both sides:

```bash
kubeseal --version
kubectl get deployment sealed-secrets-controller -n kube-system
kubectl get crd sealedsecrets.bitnami.com
```

## Seal or update a secret

Strict scope is the default and binds ciphertext to the exact Secret name and namespace. Keep both stable unless you intend to reseal.

kubeseal --controller-name sealed-secrets-controller --format yaml < secret.yaml > sealed-secret.yaml
kubectl apply -f sealed-secret.yaml

verify decryption

# Check the SealedSecret status

kubectl get sealedsecret <secret-name> -n <namespace>

# Verify the actual Secret exists

kubectl get secret <secret-name> -n <namespace>

```bash
kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  --secret-file secrets/pihole-password.yaml \
  --sealed-secret-file sealedsecrets/pihole-password-sealed.yaml

kubeseal \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  --format yaml \
  --secret-file secrets/cloudflare-dns.yaml \
  --sealed-secret-file sealedsecrets/cloudflare-dns-sealed.yaml
```

Review only names, namespaces, and encrypted key names before applying; never print plaintext or decoded Kubernetes Secrets:

```bash
kubectl apply -f sealedsecrets/
kubectl get sealedsecrets -A
kubectl get secret pihole-password -n pihole
kubectl get secret cloudflare-dns-homelab-cert-manager -n cert-manager
```

After changing the Pi-hole secret, restart or upgrade Pi-hole so its environment is recreated:

```bash
helm upgrade pihole mojo2600/pihole -n pihole -f helm/pihole/values.yaml
```

## Key backup and recovery

The controller private key is the recovery key. Back it up to an encrypted password manager or offline encrypted storage; never commit it. The public certificate is safe to distribute but is not sufficient for recovery.

List the active recovery-key Secret without displaying its data:

```bash
kubectl get secrets -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp
```

Back it up to a local file and immediately restrict its permissions:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > main.key

chmod 600 main.key
```

The command prints nothing to the terminal because `>` redirects the YAML into `main.key`. Do not run `cat main.key`, and do not append `---`; the extra YAML separator is unnecessary.

Confirm the backup exists without displaying its contents:

```bash
test -s main.key && echo "Backup exists"
stat -f '%z bytes, permissions %Sp' main.key
```

The repository ignores `*.key`, but `main.key` should still be moved promptly to encrypted storage outside the repository. For example, write directly to its final secure location instead:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o yaml > /secure/offline/location/sealed-secrets-recovery-key.yaml

chmod 600 /secure/offline/location/sealed-secrets-recovery-key.yaml
```

Exporting the public certificate is separate; it supports offline sealing but cannot recover encrypted secrets:

```bash
kubeseal --fetch-cert > /secure/offline/location/sealed-secrets-public-cert.pem
```

If the controller key is lost, existing sealed ciphertext cannot be decrypted. Restore the key before the controller starts, or create new plaintext credentials and reseal every secret against the new controller key.

## Commit safety check

Before staging changes:

```bash
git check-ignore -v secrets/*.yaml talosconfig talos-patches/*-final.yaml
git status --short --ignored
```

Only `sealedsecrets/*.yaml` should appear as committable secret material. Rotate any credential immediately if its plaintext was previously committed or pushed; encrypting it now does not remove it from Git history.
