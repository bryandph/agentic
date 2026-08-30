# agentic

Org-neutral core for the agentic development environment: a declarative MCP
server registry, an agent + knowledge registry, a devenv shell bootstrap,
and project templates — consumable as a flake by any environment.

## Layering contract

Three layers, merged at consumption time (the `mandala` / `mandala-bph`
precedent):

| Layer | Lives in | Carries |
|---|---|---|
| **core** (this repo) | `git.bph/bryan/agentic`, mirrored to GitHub | Schemas, renderers, delivery adapters, org-neutral knowledge fragments, language profiles, templates |
| **env** (e.g. `agentic-bph`) | the environment's private aggregation point (a repo or a `modules/` subtree) | Forge instances, secret-backend config, model endpoints, org knowledge fragments |
| **repo** | each consuming repo | Repo traits (submodules, services, secret dotfiles), repo knowledge fragments, repo agents |

**Placement test** for any artifact: *"would this sentence be true at
work?"* — true → core; true only in one environment → env layer; true only
in one repo → repo.

Hard rules:

- Core contains **no environment identity**: no forge hostnames, secret
  mounts/addresses, model endpoints, host names, or org-specific knowledge.
  Every environment-specific value enters through a module option.
- Secrets are sourced at runtime by a CLI (modular backend; vault/OpenBao
  wired, others as presets). Raw values never land in rendered artifacts or
  the nix store.
- Core fragments may only reference deep sources that every consumer of
  core can see (e.g. memories core itself ships) — never a consuming repo's
  artifacts.

## Consuming

Internals are dendritic (every file under `modules/` is a flake-parts
module, auto-imported via import-tree; `_`-prefixed paths are skipped).
Consumers do **not** need any of that — the supported surfaces are:

- `flakeModules.default` (alias `flakeModules.agentic`) — flake-parts
  consumers.
- `devenvModules.default` — the project shell bootstrap.
- `homeModules.default` — user-tier (home-manager) delivery.
- `flake.modules.<class>.<name>` — dendritic consumers may merge the
  namespace directly; it carries the same modules as the aliases above.

### CI cache profile contract

Environment layers may define `agentic.ciCache.profiles.{nix,rust,python}`.
Repositories request the ecosystems they use through
`agentic.ciCache.requestedProfiles`; the resolved, JSON-serializable contract
is available as `flake.agenticCiCacheContract` and
`config.agentic.ciCache.lib.contract` for the repository's own workflow
renderer. Core never creates a workflow or supplies endpoints and credentials.

The language templates request matching profiles, but those requests are
inert unless an environment layer defines them. This keeps the same templates
usable outside any particular organization and leaves out-of-shell packaging
unchanged.

Nix publication endpoints are split by trust tier: protected workflows may
write the authoritative cache, while pull requests may write only their
quarantine endpoint. The contract explicitly forbids protected substitution
from pull-request entries and direct promotion between the two tiers.

Versioning: consumers pin a **tag or locked rev** (never an
implicitly-tracked branch). The API is 0.x until a second environment
consumes it; expect breaking changes between 0.x tags.

## Hosting

Primary: `git.bph/bryan/agentic` (Gitea). A GitHub push mirror is the
consumption channel for environments without access to the primary.
Verified 2026-07-15: the mirror is `github:bryandph/agentic` (public) —
`nix flake metadata github:bryandph/agentic` resolves and locks without
credentials, so a second environment consumes core exactly like any
public flake input (design Open Question 1 resolved: no work-side
mirror needed).
