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

Pi MCP delivery is available as `packages.<system>.pi-mcp-adapter`, a pinned
local Pi package with its runtime dependencies. Opt into shared user MCP
delivery with HM `agentic.mcp.sharedUserConfig.enable = true`; project delivery
reuses `.mcp.json`. Consuming flakes also expose `pi-agent-roles`, a package of
specialist prompt templates compiled from the agent registry. See
[Pi delivery](docs/pi.md) for the trust boundary, mutable-file ownership,
package contract, and targeted runtime check.

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

#### The cache client: `agentic-ci-cache`

Core also ships the consumer-side implementation of that contract. It is
one CLI, delivered two ways:

- **Standalone** — `packages.<system>.ci-cache` / `apps.<system>.ci-cache`
  (`nix run github:bryandph/agentic#ci-cache -- …`). No flake-module import
  is needed: the contract JSON is handed over at runtime through
  `AGENTIC_CI_CACHE_CONTRACT` (a file path, or inline JSON). This is the path
  for hand-written workflows and runner images.
- **Pre-wired** — `config.agentic.ciCache.lib.tools pkgs` returns the same
  binary with the resolved contract baked in (`lib.contractFile pkgs` is
  the JSON itself). Endpoints and variable *names* are public metadata; no
  secret value can enter the contract or the store.

Subcommands: `identity`; `nix config` (substituter lines for `NIX_CONFIG`,
never the quarantine); `nix publish <path>…` (bounded completed-closure
publication to the tier's endpoint); `sccache env` / `sccache run -- <cmd>`
/ `sccache stats`; `uv env` / `uv restore` / `uv publish`. Every cache
action exits 0 and prints one JSON report line (`outcome`, `detail`,
backend, repository, tier, identity) so failures are visible without
becoming build failures; `sccache run` execs the command and propagates
its exit status, degrading to an uncached build (`RUSTC_WRAPPER=""`, which
also overrides `.cargo/config.toml`) when configuration, credentials, or
the backend are unavailable.

Trust tier comes from Woodpecker's `CI_PIPELINE_EVENT` /
`CI_COMMIT_BRANCH` / `CI_REPO_DEFAULT_BRANCH` (or `AGENTIC_CI_TRUST_TIER`).
Credentials are read **only** from tier-prefixed variables,
`CI_CACHE_PROTECTED_<NAME>` and `CI_CACHE_PULL_REQUEST_<NAME>` (each with a
`_FILE` variant); a workflow mounts only its own tier, un-prefixed legacy
names are ignored, and a value found identical in both tiers is refused.
Cache keys carry the tier (`<keyPrefix>/<repo>/<tier>/…`) so backend
policies can scope each credential to its namespace.

What the Nix quarantine does and does not isolate: pull-request closures
are published only to the quarantine endpoint, the quarantine is never a
substituter for any tier, and promotion is rebuild-based (a protected
pipeline builds and publishes its own closures). It does **not** isolate a
pull request's builds from a shared lane store or daemon on the worker
itself — that boundary is the worker platform's, not this contract's.

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
