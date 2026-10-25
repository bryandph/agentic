Tracks BPH-7 (the authoritative work item; migrated from an earlier issue in the environment repository).

## Why

The public Agentic core already owns MCP delivery, agents, knowledge, templates, and part of the Devenv shell, while finance, real-estate-search, and the infrastructure subprojects independently rebuild the surrounding project environment. Generalizing that core into a shared Workbench gives those repositories one composable project-mechanics layer without moving their packaging, services, or domain workflows into a central junk drawer.

## What Changes

- Adopt **Workbench** as the public project/environment identity while retaining agent support as a first-class capability.
- Introduce composable base, Nix, Python/uv, Rust, polyglot, embedded, and infrastructure-oriented project profiles built from upstream Devenv, treefmt, and git-hooks modules.
- Make profile composition additive: shared profiles do not use `mkForce` to disable unrelated Devenv facilities and do not claim project packaging, services, processes, or domain commands.
- Retain one registry-driven delivery path for MCP, agents, skills, instructions, knowledge, Serena, and runtime secret references.
- Keep environment forge endpoints, Vault/OpenBao wiring, model endpoints, defaults, and organization knowledge in a private environment layer that configures public schemas rather than redefining them.
- Add repository traits for submodules, stateful services, per-worktree file handling, lifecycle hooks, project identity, and selected profiles, while leaving repository-specific commands and state ownership local.
- **BREAKING**: make `workbench.*` and Workbench-named flake outputs the canonical public API; provide deprecated `agentic.*` and Agentic-named aliases for a documented migration window.
- Validate the boundary using core-only fixtures plus real-estate-search, finance, and the Terraform/Kubernetes/Ansible standalone environments; track consumer edits through their existing repository issues.

## Capabilities

### New Capabilities

- `workbench-project-environment`: Composable shared project mechanics, profile boundaries, repository traits, archetype contracts, and validation consumers.

### Modified Capabilities

- `agentic-layering`: Rename the canonical public surface to Workbench, define the private environment capsule, and require compatibility aliases during migration.
- `agentic-devenv`: Expand the shell contract from workflow artifact bootstrap to additive project-profile composition without forcing unrelated Devenv options.
- `agentic-agents`: Move agent, skill, instruction, and knowledge declarations to the canonical Workbench namespace while preserving generated-artifact behavior.
- `agentic-mcp-registry`: Move the canonical registry namespace and rendered artifact ownership to Workbench without creating another server-definition plane.
- `agentic-project-template`: Generate Workbench-based archetypes and adoption scaffolds that compose shared mechanics with repository-owned packaging.

## Impact

- Public core (this repository), including its repository/mirror identity, option namespace, exported flake modules, templates, documentation, checks, and release tags.
- Private environment composition in the environment repository, which will become its Workbench policy layer without changing the public/private publication boundary.
- Generated project artifacts and committed instructions retain their current single-writer and drift-check contracts.
- Consumer migrations tracked by the finance and real-estate-search repositories' issues, and follow-up issues in the Terraform, Kubernetes, and Ansible repositories.
- The completed `unify-project-mcp-delivery` change remains the delivery foundation; a separate issue remains the Betterleaks capability rollout.

## Non-goals

- Moving uv2nix builds, Rust packaging, project packaging OCI images, databases, application processes, Terraform actions, Kubernetes reconciliation, or Ansible playbooks into Workbench.
  - Exception: shared dev-environment images (the `dev-base`/`dev-nix` builder) are a Workbench capability owned by change `distributable-dev-environments` (BPH-39). This non-goal covers only images that package a project.
- Publishing the environment repository, its operator data, or environment endpoint configuration.
- Replacing Devenv, mcp-servers-nix, treefmt-nix, git-hooks or Serena with locally reimplemented equivalents.
- Folding other private operator configuration into the environment repository or reorganizing fleet modules; that is a separate environment-repository change.
