Kubernetes work here is **GitOps-first**: the cluster state is a repo;
`kubectl apply` by hand is a break-glass action, not a workflow.

- Reconciliation via Flux (or the repo's declared operator); manifests
  organized as base + per-cluster overlays (kustomize), Helm via
  HelmRelease with **pinned chart versions** — a bot (renovate) bumps
  pins, humans never track `latest`.
- Every workload declares resource requests/limits and health probes;
  absence is a review finding, not a style preference.
- Secrets never live in manifests: external-secrets / SOPS-encrypted
  resources reference the secret store.
- Validate before pushing: build/diff the rendered manifests (the
  repo's `k8s-validate`-style checks) rather than trusting the
  reconciler to reject bad YAML.
- Prefer reading live state through the cluster MCP/CLI tooling over
  pasting manifests from memory — versions and CRD schemas drift.

Deeper sources: https://fluxcd.io/flux/, https://kustomize.io/.
