## 1. Contract and compatibility baseline

The bounded shell/credential slice authorized in the conversation is tracked
in section 8 and BPH-24. Earlier rename/publication tasks remain separate.

- [x] 1.1 Inventory the public Agentic option declarations, conventional/dendritic flake outputs, generated artifact owners, template names, remote URLs, and known consumers; record pointers and migration status in BPH-7.
- [x] 1.2 Resolve the Workbench repository/namespace name and compatibility-release window in BPH-7 before changing any remote or deleting any alias.
- [x] 1.3 Add core-only baseline checks that capture current MCP/agent/knowledge artifact behavior so the rename cannot create a second writer or registry.
- [x] 1.4 Run the public core formatter and `nix flake check --impure`, including its current minimal/template outputs, before beginning the additive API work.

## 2. Public Workbench core

- [x] 2.1 Add canonical `workbench.*` options and Workbench-named conventional/dendritic exports over the existing implementations, with legacy Agentic names resolving to the same option graph; warning timing remains a later release decision.
- [ ] 2.2 Split the public module layout into clear profile, workflow-registry, adapter, template, and check concerns without changing generated artifact ownership.
- [ ] 2.3 Implement additive base, Nix, Python/uv, Rust, polyglot, embedded Rust, and infrastructure-oriented profiles; remove force-priority disabling of unrelated Devenv facilities.
- [ ] 2.4 Implement typed repository traits and lifecycle extension points for project identity, submodules, stateful services, worktree cache/file handling, selected profiles, and ordered project hooks.
- [ ] 2.5 Move MCP, agents, skills, instructions, knowledge, Serena, secret interfaces, and user adapters to canonical Workbench namespaces while retaining one registry/renderer per artifact.
- [ ] 2.6 Update Workbench templates and workflow-only adoption paths to compose profiles without owning repository packaging, services, processes, or CI.
- [ ] 2.7 Add minimal, Python/uv, stateful polyglot, submodule infrastructure, and private-env fixtures; assert additive composition, alias equivalence, single writers, and core org-neutrality.
- [ ] 2.8 Run the core formatter, `nix flake check --impure`, and targeted builds of every archetype/template output; commit, push, and tag the reachable compatibility release before downstream canonicalization.

## 3. Private environment capsule

- [ ] 3.1 Implement a narrow private Workbench environment module/flake that configures forge, runtime secret backend, model, default, agent/skill, and knowledge options without importing host/fleet outputs.
- [ ] 3.2 Migrate the environment layer's composition to canonical Workbench names while preserving deprecated aliases and the existing core/env/repo layering contract.
- [ ] 3.3 Compare all generated Claude, OpenCode, Codex, Serena, AGENTS, and Home Manager artifacts before/after; remove old declarations only when the canonical authority is enabled.
- [ ] 3.4 Git-add new files, run `nix run --impure .#fmt`, build the Workbench rendered/configuration outputs, run `nix run --impure .#check`, and run `nix flake check --impure` before pushing the environment capsule/pin.

## 4. Standalone archetype migrations

- [ ] 4.1 Implement the tracked migration issue in real-estate-search: import the Python/uv and workflow modules, retain Python 3.13/uv2nix/app/package overrides locally, delete duplicated mechanics, and compare its shell/check/package outputs.
- [ ] 4.2 Run real-estate-search formatting plus `nix flake check --impure` and targeted default-package/app builds, then commit and push that repository independently.
- [ ] 4.3 Implement the tracked migration issue in finance: import polyglot/workflow modules, retain PostgreSQL/Playwright/process/script/database-hook behavior locally, and delete hand-written Vault/MCP/Serena/OpenCode mechanics.
- [ ] 4.4 Run finance formatting plus `nix flake check --impure` and targeted shell/package/image checks that do not start `devenv up`, then commit and push that repository independently.

## 5. Infrastructure subproject migrations

- [ ] 5.1 Create or link one Gitea issue in each Kubernetes, Terraform, and Ansible repository for its Workbench standalone-shell migration before editing that submodule.
- [ ] 5.2 Delegate the Kubernetes migration to its repository owner; retain validation/reconciliation/domain tools locally, run its formatter and targeted `nix flake check --impure`, then commit and push.
- [ ] 5.3 Delegate the Terraform migration to its repository owner; retain plan/apply/domain tools locally, run its formatter and targeted `nix flake check --impure`, then commit and push.
- [ ] 5.4 Delegate the Ansible migration to its repository owner; retain playbooks/inventory/domain scripts locally, run its formatter and targeted `nix flake check --impure`, then commit and push.
- [ ] 5.5 Update the environment repository's submodule pointers only to the pushed child commits, remove superseded parent/standalone mechanics, then run `nix run --impure .#fmt`, targeted composed-shell builds, `nix run --impure .#check`, and `nix flake check --impure`.

## 6. Repository and publication rename

- [ ] 6.1 Verify the compatibility tag and old locked revision are reachable from both the private Gitea primary and public GitHub mirror before changing repository identity.
- [ ] 6.2 Rename the primary/mirror/local submodule identity to the approved Workbench name and update documentation, flake URLs, locks, generated instructions, and package descriptions without removing compatibility outputs.
- [ ] 6.3 Verify a clean consumer can resolve the public GitHub mirror and evaluate core-only/Python fixtures without lab credentials; run the public core formatter and `nix flake check --impure`, then publish the post-rename tag.

## 7. Final integration and handoff

- [ ] 7.1 Run `openspec validate standardize-project-workbench` and verify every delta capability has an implementation/acceptance check.
- [ ] 7.2 Git-add all new files, run `nix run --impure .#fmt`, `nix run --impure .#check`, `nix flake check --impure`, and targeted builds of the Workbench artifacts plus at least one NixOS and one Darwin configuration that consume the environment.
- [ ] 7.3 Update human documentation and durable Serena decision pointers for the Workbench placement/compatibility contract, summarize pushed revisions and remaining consumer issues in the authoritative work item, and leave alias removal for a later explicit breaking issue/change.

## 8. Flake shell composition and scoped delivery (BPH-24)

- [x] 8.1 Add a standalone SecretSpec command-runner interface, shared declarations, fail-closed legacy wrappers, and a credential-isolated HTTP MCP bridge.
- [x] 8.2 Compose the agent workflow into all parent language shells and make shared language profiles additive.
- [x] 8.3 Configure Terraform backend/cloud CLI scopes while preserving ephemeral provider references, ADC, canonical roots, and saved-plan protections; verify backendless commands do not fetch credentials.
- [x] 8.4 Migrate Terraform, Kubernetes, and Ansible standalone shells to the shared registry/bootstrap and verify their locked entry points.
- [x] 8.5 Remove root/Terraform .envrc credential reads and shell-entry credential materialization; supply scoped tea, Renovate, Woodpecker, and cloud wrappers.
- [x] 8.6 Verify scoped injection/exclusion, missing-credential rejection, file cleanup, HTTP bridge behavior, MCP parity, and shell evaluation; publish the core review branch before pinning its commit.
- [x] 8.7 Document usage and boundaries and leave both existing tracker records with review evidence; do not merge, deploy, or close the wider Workbench change.
