## Context

Agentic began as the org-neutral agent workflow plane, but its current public surface already spans Devenv bootstrap, language profiles, generated project files, MCP, agents, knowledge, templates, and Home Manager adapters. The surrounding project mechanics are still repeated in the Terraform, Kubernetes, and Ansible standalone devenv modules of the environment repository, finance's `flake-parts/devenv.nix`, and real-estate-search's `flake.nix`.

These consumers expose two different pressures. Infrastructure repositories repeat bootstrap and delivery code but own important domain commands. Finance needs a polyglot shell and stateful per-worktree database lifecycle. Real-estate-search needs a small Python/uv shell while retaining its own uv2nix build and package overrides. The shared abstraction therefore has to be composable project mechanics, not a catalog of entire project shells.

The existing core/env/repo layering and the completed `unify-project-mcp-delivery` change are load-bearing. The design changes the umbrella identity and expands the project-environment contract without adding another registry, renderer, secret plane, or file writer.

Affected repositories are:

- this core repository / its GitHub mirror, renamed to the Workbench identity after compatibility outputs exist.
- the environment repository, which supplies the private environment layer and pins the public core.
- finance and real-estate-search as standalone consumer archetypes.
- the Kubernetes, Terraform, and Ansible repositories for standalone environment migration; their own agents/issues own edits.

## Goals / Non-Goals

**Goals:**

- Establish one public, org-neutral project-mechanics core with agents as one feature family.
- Make shared Devenv profiles additive and safe to compose with project services, packaging, and processes.
- Express repository differences through typed traits and explicit extension points.
- Keep environment policy private and independently consumable from the environment repository.
- Migrate existing consumers without a flag day or a period with two authorities for generated artifacts.
- Prove the API with minimal, Python, polyglot/stateful, and infrastructure fixtures.

**Non-Goals:**

- Centralizing complete application or infrastructure-domain shells.
- Replacing repository package outputs, build systems, CI, or runtime services.
- Reimplementing upstream Devenv, mcp-servers-nix, treefmt, hooks or Serena.
- Combining the environment repository's fleet/operator reorganization into this change.

## Public surface baseline (2026-09-19)

The checkout is still Agentic-only. The public core is pinned at `e4bc0d5`;
`v0.2.0` predates that commit. The compatibility release does not exist yet.
These declaration pointers are the inventory for task 1.1; migration status is
**legacy** for every row until a Workbench alias is added and verified.

| Surface | Current declaration and consumers |
| --- | --- |
| Flake-parts options | `modules/registry/_*.nix`, `modules/instructions.nix`, and `modules/adapters/project.nix` declare `agentic.{agents,agentsLib,knowledge,knowledgeLib,fragmentSizeBound,mcp,secrets,forges,serena,memoryPlane,knowledgeSearch,devenvLib,ciCache,instructions}`. The nested options remain under those declaration files. The private environment layer configures them. |
| Home Manager options | `modules/adapters/user.nix` declares `agentic.mcp.{userServers,sharedUserConfig.enable}`. The environment repository and its user-tier configuration consume the user-tier delivery. |
| Conventional and dendritic modules | `modules/exports.nix` publishes `flakeModules.{default,agentic}`, `devenvModules.{default,agentic,rust,python,polyglot,embedded-rust}`, and `homeModules.{default,agentic}`. Their sources are `flake.modules.{flake,homeManager,devenv}.agentic` plus the four profile names (`modules/profiles.nix`). The environment repository and its Kubernetes, Terraform, and Ansible flakes import `flakeModules.default`; templates also import it. |
| Other flake outputs | `modules/templates.nix` publishes `templates.{default,rust,python,polyglot,embedded,adopt,agentic}`. `modules/ci-cache.nix`, `modules/packages/pi-mcp-adapter.nix`, `modules/adapters/{pi,agents}.nix`, and `modules/instructions.nix` publish `ci-cache`, `pi-mcp-adapter`, `pi-agent-roles`, and write apps. Consumers include the environment's CI and user-tier configuration and template adopters. |
| Generated project files | `modules/registry/_bootstrap.nix` and `modules/adapters/project.nix` use mcp-servers-nix as the MCP file writer for Claude, Codex, OpenCode, and optional VS Code flavors. The bootstrap places agent roles and Serena configuration/read-only knowledge; `modules/instructions.nix` renders committed `AGENTS.md` and `CLAUDE.md`. The private environment layer exposes comparison packages for these outputs. |
| Repository identities | The environment repository mounts this core as a submodule of the private forge primary; the public mirror is on GitHub (`README.md` and all six templates). The user-tier configuration and the parent-owned Kubernetes/Terraform/Ansible flakes refer to the private forge URL; the environment repository imports its submodule checkout. The finance and real-estate migrations are tracked in BPH-17 and BPH-18; pico-embassy is BPH-19. |

Baseline comparison must include both module publication channels, exact
generated files, and independently pinned entry points. The public mirror's
current reachability must be checked before any remote rename; the README's
2026-07-15 verification is historical evidence only.

## Decisions

### Current implementation slice: flake shells and scoped credentials

The operator selected consistent shell/MCP composition and scoped credential
delivery, including Terraform, in the active conversation. Native devenv is
excluded from this slice; the existing flake-parts transport remains supported.
The Workbench rename and unrelated consumer migrations remain separate.

Use standalone SecretSpec >= 0.20, generating declaration-only manifests from
command scopes and MCP references. OpenBao remains the store. HTTP MCPs with
token references use an upstream mcp-proxy stdio bridge with headers supplied
in process memory, while other HTTP servers retain direct client authentication.
Terraform's provider credentials stay in ephemeral Vault references; scoped
delivery supplies backend credentials only for commands that need the backend.
Backendless validation/locking must not request credentials.

The parent and standalone platform shells import shared private server and
runtime-policy modules. The platform directories are now parent-owned;
only the public agentic core needs an independently pushed submodule commit.
Their local flakes retain compatibility entry points and select project MCP
subsets from the shared registry. Acceptance evidence is tracked on BPH-24
and BPH-7 rather than treating this slice as completion of the wider rename.

### D1: One Workbench core, not separate devshell and agent repositories

We chose one public Workbench core over splitting generic development tooling from Agentic because project identity, generated files, knowledge, MCP, hooks, and shell lifecycle share the same traits and evaluation. A split would make every consumer reconcile two pins, two option graphs, and overlapping file ownership before a second independent use case proves that boundary.

The internal module tree SHALL still separate profiles, workflow registries, adapters, templates, and checks. Repository count is not the modularity boundary.

### D2: Keep the core/env/repo contract and rename its umbrella

We chose to preserve the existing three-layer module composition because it already prevents environment identity from leaking into the public mirror:

```text
Workbench core        reusable schemas, profiles, renderers, adapters
private env capsule   forge/secret/model/knowledge/default policy
repository layer      domain packages, services, processes, scripts, traits
```

We rejected moving environment defaults into the public core for convenience. Private Gitea visibility is not internet publication, but public GitHub mirrors must remain usable without lab access or environment values.

### D3: Profiles provide additive defaults, never policy-forcing overrides

We chose importable profile modules over shell-builder functions because module composition matches Devenv and the dendritic flake-parts model. Profiles SHALL set ordinary defaults for packages, languages, formatters, and hooks. They MUST NOT use `lib.mkForce` to erase containers or other unrelated facilities, and they MUST NOT enable stateful services or project processes.

The initial profile families are base, Nix, Python/uv, Rust, polyglot, embedded Rust, and infrastructure support. A consumer may override Python/Rust versions and tool selections using upstream options.

### D4: Repository traits describe mechanics; repositories retain behavior

We chose a small typed trait schema over inspecting repository contents or embedding per-repo modules in core. Traits include project identity, submodule presence, stateful-service presence, secret-bearing worktree copies, cache-sharing eligibility, selected profiles, and lifecycle hook references.

Traits drive generated bootstrap, worktree setup, and check behavior. Custom lifecycle commands remain repository declarations because finance's database provisioning and infrastructure commands are meaningful domain behavior. Core provides the hook slots and ordering, not the scripts.

### D5: Workbench owns shared adapters and pins; builds remain consumer-owned

We chose to let Workbench carry the inputs needed by its own adapters/profiles while consumers retain packaging-specific inputs such as uv2nix, pyproject overlays, Rust overlays, OCI tooling, and provider SDKs. Consumers use `follows` where compatible, but Workbench does not require one package-construction strategy.

This keeps real-estate-search's virtual environment and overrides local, and finance's PostgreSQL bundle/images local, while deleting their hand-written MCP, Serena, secret-wrapper, and generic worktree setup code.

### D6: Canonical Workbench API with staged Agentic compatibility

The operator approved **Workbench** as the public repository and option
namespace in the 2026-09-19 conversation. This resolves the naming decision;
the compatibility and migration sequence below remains the planned contract.

The first additive API step publishes `workbench.*` as an alias into the
existing `agentic.*` option graph and publishes Workbench-named conventional
and dendritic modules from the same module values. This avoids a second
registry or file writer while consumers begin using the approved name.
Internal implementation paths move during the later registry migration;
deprecation warnings wait for an explicitly chosen release.

We chose a staged namespace/repository rename over an immediate breaking rename:

1. Publish a tagged release from the existing repository that adds canonical `workbench.*`, `flakeModules.workbench`, `devenvModules.workbench`, and corresponding conventional aliases while preserving `agentic.*` aliases.
2. Update the environment repository and standalone consumers to the canonical names and verify generated artifacts are unchanged unless intentionally improved.
3. Rename the primary Gitea repository, GitHub mirror, local submodule path, docs, and package identity only after the compatibility release is reachable.
4. Retain compatibility aliases for at least one subsequent tagged release and until every known consumer issue is complete; remove them only in an explicitly breaking release/change.

We rejected keeping `agentic` as the umbrella because Python/uv and general project mechanics would remain semantically misplaced. We also rejected naming the core `devenv` or `workspace` because those names collide with established upstream/editor concepts.

### D7: The private environment is a narrow capsule owned by its environment repository

We chose a conventional private flake/module surface owned in the environment repository over making consumers import internal parent paths. The capsule SHALL configure public Workbench options and expose no fleet/host outputs. Its final physical placement may be completed by a separate environment-repository change, but its consumer contract must not require the environment repository's complete module graph.

### D8: Validation uses archetypes, not snapshots of real repositories

We chose core-owned fixtures that model real consumer shapes over tests that reach into sibling checkouts. Fixtures cover minimal core-only, Python/uv, polyglot plus stateful services, submodule infrastructure, and private-env composition. The real repositories remain acceptance migrations tracked by their own issues.

Each fixture checks evaluation, additive option merging, generated-file ownership, absence of environment identity in core-only output, and the absence of forced unrelated Devenv options.

### D9: Cross-repository migration is serialized by dependency

The public Workbench compatibility release lands and is pushed first. The environment repository then pins it and publishes the private capsule. Finance and real-estate-search migrate independently. Kubernetes, Terraform, and Ansible changes are committed and pushed inside their submodules before the environment repository updates pointers and removes legacy standalone declarations. No parent commit may reference an unpushed child SHA.

## Risks / Trade-offs

- [Workbench becomes a miscellaneous Nix utilities repository] → Enforce the placement test in specs and require every core module to serve at least two archetypes without carrying domain behavior.
- [The rename breaks remote URLs or flake output consumers] → Land and tag compatibility outputs before renaming remotes; update locked revisions and retain aliases through a documented window.
- [Profiles conflict with stateful services or packaging] → Ban `mkForce` for unrelated facilities, test additive composition, and keep services/builds consumer-owned.
- [The environment capsule accidentally pulls in the full fleet graph] → Give it an isolated conventional flake/module entrypoint and a focused evaluation check.
- [Generated files gain multiple writers during migration] → Switch each artifact atomically from the old declaration to the Workbench registry and retain the existing conflict/drift checks.
- [Cross-repo work stalls on unrelated migrations] → Treat real consumers as independent acceptance issues; core readiness depends on archetype fixtures, not completing every migration.

## Migration Plan

1. Add canonical Workbench modules, outputs, namespaces, documentation, compatibility aliases, and archetype fixtures in the public core; tag and push the compatibility release.
2. Add/publish the narrow private Workbench environment capsule from the environment repository and pin the tagged core revision.
3. Migrate real-estate-search and finance, deleting duplicated project mechanics while preserving their package, service, and lifecycle behavior.
4. Migrate Kubernetes, Terraform, and Ansible standalone shells in their own repositories; commit and push each before parent pointer updates.
5. Update the environment repository's composition, generated instructions, docs, and input/submodule identity to Workbench; compare generated artifacts and checks.
6. Rename remotes/mirror/local path after all canonical outputs are available; publish a second tag that documents compatibility status.
7. Remove compatibility aliases only through a later explicit breaking change after all known consumers are canonical.

Rollback keeps the compatibility tag and old aliases usable. A consumer can restore its prior lock and declarations without changing application state. Remote rename rollback restores the old repository name or mirror target while the pinned commits remain reachable.

## Open Questions

- Decide whether the isolated environment capsule is a nested flake in the environment repository or a conventional root export after a separate environment-repository change establishes its final layout.
- Determine the exact deprecation release at which compatibility warnings begin; alias removal is explicitly outside this change.
