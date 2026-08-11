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

A repository and Kubernetes misconfiguration scanner is the next security
slice. Scanner binaries, databases, and Actions must be evaluated and pinned
before adding them. A scan should initially report findings without blocking
all pull requests; blocking should be enabled only after existing findings are
triaged and recorded.
