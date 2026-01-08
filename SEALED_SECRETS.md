# Sealed Secrets Setup and Usage Guide

This guide shows how to use Bitnami Sealed Secrets to encrypt Kubernetes secrets that can be safely committed to your public GitHub repository.

## How It Works

1. You create a standard Kubernetes secret manifest
2. `kubeseal` encrypts it using the cluster's public key
3. You commit the encrypted `SealedSecret` to git
4. The Sealed Secrets controller in your cluster decrypts it automatically
5. Only your cluster can decrypt the secrets (no private keys in git!)

## Installation

### 1. Install the Controller (Already Done)

The Sealed Secrets controller is installed in your cluster and has generated a public/private key pair automatically.

```bash
# Verify installation
kubectl get pods -n kube-system -l name=sealed-secrets-controller
```

### 2. Install kubeseal CLI

```bash
# On macOS
brew install kubeseal

# Or download binary
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.26.0/kubeseal-0.26.0-darwin-amd64.tar.gz
tar -xvzf kubeseal-0.26.0-darwin-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Workflow

### Step 1: Create a Secret Manifest

Create a file with your secret (normal Kubernetes secret format):

```yaml
# secrets/pihole-password.yaml
apiVersion: v1
kind: Secret
metadata:
  name: pihole-password
  namespace: pihole
type: Opaque
stringData:
  password: "your_secure_password_here"
```

### Step 2: Encrypt It

Use `kubeseal` to encrypt the secret. This uses your cluster's public key to encrypt it:

```bash
kubeseal -f secrets/pihole-password.yaml -o sealedsecrets/pihole-password-sealed.yaml --format yaml
```

The output (`pihole-password-sealed.yaml`) contains an encrypted `SealedSecret` that can be safely committed to git.

### Step 3: Apply to Cluster

Apply the sealed secret to your cluster:

```bash
kubectl apply -f sealedsecrets/pihole-password-sealed.yaml
```

The Sealed Secrets controller will automatically decrypt it and create a regular `Secret` named `pihole-password` in the `pihole` namespace.

### Step 4: Use in Helm Charts

Update your Helm values to reference the secret:

```yaml
# helm/pihole/values.yaml
admin:
  password: ""
  # Use secret instead
  existingSecret: "pihole-password"
  existingSecretKey: "password"
```

## Complete Example Workflow

### Example: Encrypt Pi-hole Password

```bash
# 1. Create secret manifest
cat > secrets/pihole-password.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: pihole-password
  namespace: pihole
type: Opaque
stringData:
  password: "super_secure_password_here"
EOF

# 2. Encrypt it
kubeseal -f secrets/pihole-password.yaml -o sealedsecrets/pihole-password-sealed.yaml

# 3. Verify the encrypted file
cat sealedsecrets/pihole-password-sealed.yaml

# 4. Commit to git
git add sealedsecrets/pihole-password-sealed.yaml
git commit -m "Add sealed secret for Pi-hole"
git push

# 5. Apply to cluster
kubectl apply -f sealedsecrets/pihole-password-sealed.yaml

# 6. Verify the secret was created
kubectl get secret pihole-password -n pihole
```

### Example: Encrypt Certificate Keys

```bash
# Create TLS cert secret
cat > secrets/tls-cert.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: tls-cert
  namespace: traefik
type: kubernetes.io/tls
data:
  tls.crt: $(base64 < cert.pem)
  tls.key: $(base64 < key.pem)
EOF

# Encrypt it
kubeseal -f secrets/tls-cert.yaml -o sealedsecrets/tls-cert-sealed.yaml

# Apply
kubectl apply -f sealedsecrets/tls-cert-sealed.yaml
```

## Advanced Usage

### Scope Options

Control where the sealed secret can be decrypted:

```bash
# Strict scope: Only works in exact namespace/metadata as specified
kubeseal --scope strict -f secret.yaml

# Namespace-wide: Works in same namespace
kubeseal --scope namespace-wide -f secret.yaml

# Cluster-wide: Works in any namespace
kubeseal --scope cluster-wide -f secret.yaml
```

### Offline Encryption

Export the public key for offline encryption:

```bash
# Export public key
kubeseal --fetch-cert > my-public-key.pem

# Encrypt offline (can be done on any machine, even without kubectl access)
kubeseal --cert my-public-key.pem -f secret.yaml -o sealed-secret.yaml
```

### Encrypting from stdin

```bash
echo -n "my_secret_password" | kubectl create secret generic my-secret --dry-run=client --from-file=password=/dev/stdin -o yaml | kubeseal -o sealed-secret.yaml
```

## Repository Structure

Recommended structure for your homelab:

```
homelab/
├── secrets/                 # UNENCRYPTED secrets (NEVER commit this!)
│   ├── pihole-password.yaml
│   └── tls-cert.yaml
├── sealedsecrets/           # ENCRYPTED secrets (SAFE to commit)
│   ├── pihole-password-sealed.yaml
│   └── tls-cert-sealed.yaml
├── helm/                   # Helm charts
│   ├── pihole/
│   └── traefik/
├── manifests/
└── README.md
```

### .gitignore

```gitignore
# Never commit unencrypted secrets
secrets/
*.key
*.pem
!sealedsecrets/
```

## Verification

Check that sealed secrets are working:

```bash
# List sealed secrets
kubectl get sealedsecrets -A

# List regular secrets (these are created by the controller)
kubectl get secrets -A

# View a sealed secret (it's encrypted, safe to view)
kubectl get sealedsecrets pihole-password -n pihole -o yaml

# View the actual secret (only visible to those with cluster access)
kubectl get secret pihole-password -n pihole -o yaml
```

## Backup and Recovery

### Backup Public Key

```bash
kubeseal --fetch-cert > sealed-secrets-public-key.pem
```

Keep `sealed-secrets-public-key.pem` in a safe place. If you lose your cluster, you'll need to recreate the controller with the same key or re-seal all secrets.

### Disaster Recovery

If you lose the Sealed Secrets controller private key:

1. Restore from backup (if you backed up the private key)
2. Or reinstall the controller and re-seal all your secrets

```bash
# To re-seal all secrets after controller reinstall
for file in secrets/*.yaml; do
  kubeseal -f "$file" -o "sealedsecrets/$(basename $file .yaml)-sealed.yaml"
done
```

## Common Issues

### "Certificate not found"

```bash
# Wait for controller to be ready and generate certificate
kubectl wait --for=condition=ready pod -n kube-system -l name=sealed-secrets-controller
```

### "Forbidden: sealedsecrets.bitnami.com is forbidden"

Make sure you're applying a `SealedSecret` (encrypted), not a regular `Secret` (unencrypted).

### Updates to Sealed Secrets

When you update a secret:

```bash
# 1. Update the original secret file
# 2. Re-encrypt it
kubeseal -f secrets/pihole-password.yaml -o sealedsecrets/pihole-password-sealed.yaml

# 3. Apply the updated sealed secret
kubectl apply -f sealedsecrets/pihole-password-sealed.yaml

# The controller will automatically update the underlying Secret
```

## Security Benefits

✅ No private keys in git
✅ Encrypted secrets can be safely committed
✅ Only your cluster can decrypt secrets
✅ Audit trail in git of secret changes
✅ No need for external secret management services

## Next Steps

1. Install `kubeseal` CLI
2. Create a `secrets/` directory for unencrypted secrets (add to .gitignore)
3. Create a `sealedsecrets/` directory for encrypted secrets (commit to git)
4. Encrypt your Pi-hole password and other secrets
5. Update your Helm charts to use sealed secrets
6. Commit and push to GitHub safely!
