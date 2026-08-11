# Supply-chain and update policy

Updates are discovered automatically but are never merged or deployed
automatically. Every infrastructure update requires review, a successful
render/lint check, and an explicit Helm or Talos deployment.

## Renovate

`renovate.json` discovers updates for Helm dependencies, container images,
Kubernetes manifests, npm dependencies, and GitHub Actions. It runs on Monday
mornings, limits concurrent pull requests, and creates a Dependency Dashboard
issue for deferred updates.

To activate it, install the Renovate GitHub App for this repository. The app
will validate `renovate.json` and open an onboarding pull request. Review that
pull request rather than enabling its proposed configuration blindly; this
repository already contains the intended configuration.

Container digests remain pinned. A Renovate pull request may update a tag or
digest, but applying it is a separate manual operation after reviewing release
notes and testing the rendered chart.

Talos and Kubernetes updates are excluded from automated pull requests. Their
compatibility, machine configuration, and upgrade order require a deliberate
cluster upgrade plan.

## Pull-request review

For each dependency update:

1. Read the upstream release notes and check for breaking changes.
2. Confirm that the image or chart comes from the expected upstream project.
3. Run `helm lint` and `helm template` for every affected local chart.
4. For network-facing changes, review the corresponding Cilium policy and
   confirm that no broader egress or ingress is introduced.
5. Deploy one release at a time and verify pods, ingress, metrics, and Hubble
   denies before merging the next update.

Do not enable Renovate automerge for cluster workloads.

## CI and scanner policy

Any GitHub Action must be pinned to a full commit SHA, including checkout and
security-scanning actions. Version tags alone are mutable and are not an
acceptable trust boundary.

The `Security scan` GitHub Actions workflow runs on pull requests, pushes to
`main`, Monday mornings, and manual dispatches. It checks Kubernetes and
repository configuration for high/critical misconfigurations and scans
committed files for secrets.

The workflow uses the remediated Trivy Action 0.36.0 commit and the known-safe
Trivy 0.69.3 binary identified in GHSA-69fq-xp46-6x23. Checkout, Trivy, and
Trivy's transitive setup/cache Actions are referenced by full commit SHA and
use the Node.js 24 runtime. The vendored Sealed Secrets chart is skipped because
it is upstream code rather than a locally maintained workload; the committed
encrypted SealedSecret resources remain in scope.

Both scans use `exit-code: "1"`. A high/critical Kubernetes or repository
misconfiguration, or a high/critical potential secret in committed files, now
fails the workflow. Do not suppress a finding merely to make CI pass: fix it or
document why a narrowly scoped ignore is safe before adding that exception.
