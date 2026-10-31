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

## Workspace

A workspace is one tree of independently versioned repositories under a
single root, declared once in Nix instead of chained together with
submodules. Core ships the declaration and the tools around it; the
environment's own workspace repository supplies the remotes, the
repositories and the folder layout.

### Declaration

`devenvModules.workspace` (also in `flake.modules.devenv.workspace` for
flake-parts consumers) adds `workbench.workspace` (alias
`agentic.workspace`) to a devenv shell:

```nix
workbench.workspace = {
  remotes.team = {
    url = "git@forge.example:team";              # scp-style, ssh:// or HTTPS, any forge
    aliases = [ "https://mirror.example/team" ]; # mirrors serving the same repositories
  };
  repos = {
    tool.remote = "team";                        # git@forge.example:team/tool.git
    site = { remote = "team"; name = "website"; groups = [ "apps" ]; };
    lib = { url = "https://code.example/upstream/lib.git"; path = "third-party/lib"; };
  };
};
```

A repository sets exactly one of `remote` or `url`. With `remote`, the
clone URL is the remote's `url`, a `/`, the repository's `name` (default:
its key) and the remote's `suffix` (default `.git`). `aliases`, on a
remote or a repository, lists further URLs that identify the same
repository. `path` defaults to `defaultPath { key, name, remote, groups }`,
which returns `name`: a flat list under the root. `groups` are selection
labels; they render as mani tags and select repositories for tasks and
overrides. Paths must be relative and normalised, unique, and not inside
another declared path; evaluation fails and names the entries otherwise.
The first release's `tags` still works as a deprecated synonym of
`groups`.

A folder layout is configuration, and an area is a group. To keep the
workspace's own repositories at the root and each area's repositories in
a folder named after the area:

```nix
workbench.workspace.defaultPath = r: let
  area = lib.findFirst (g: lib.elem g [ "infra" "apps" ]) null r.groups;
in if area == null then r.name else "${area}/${r.name}";
```

With that, `site` above is checked out at `apps/website` and `tool` at
`tool`.

The declaration resolves to `workbench.workspace.resolved`, a list of
`{ key, url, aliases, path, groups }` with remotes joined and paths
computed. The shell exports it as JSON at `$WORKBENCH_WORKSPACE_MANIFEST`;
the renderer, the audit and the override helper read only that, and so
can your scripts.

### Rendering

With any repository declared, the shell puts `mani` on the path and
writes `mani.yaml` (`renderers.mani.enable = false` turns that off).
Rendering writes the manifest and nothing else: entering the shell never
clones, fetches or moves anything. `mani sync` clones what is missing and
leaves existing checkouts alone, and `status` and `fetch` are the default
tasks for `mani run` (`tasks` replaces them), as in
`mani run status --all` or `mani run fetch --tags apps`.

The manifest sets `sync_gitignore`, `sync_remotes` and
`remove_orphaned_worktrees` to false. `extraConfig` is merged over the
generated manifest, but evaluation refuses it when it enables any of
those three or adds per-project `worktrees` or `remotes`: worktrees belong
to the worktree tool and remotes to git. Changing a path does not move a
checkout; the next `mani sync` clones at the new path and the audit
reports the old one as undeclared.

### Audit

`workspace-audit` compares the declaration with the tree and changes
nothing. It reports declared paths that are missing, declared paths that
are not the top of a git repository, checkouts whose `origin` matches
neither the declared URL nor an alias, and top-level directories nobody
declared. Dot-directories and parents of declared paths are never
reported; list other names in `audit.ignore` or pass `--ignore`. The root
is `$DEVENV_ROOT` inside the workspace shell and the current directory
outside it; `--root` sets it. `--json` prints the findings as JSON, and
`--strict` exits 1 when there are any, so the audit can serve as a check.
Run it before and after changing the declaration to see what moved.

### Local overrides

`workspace-overrides` lets another flake evaluate against your local
checkouts without bumping its pins. It reads that flake's `flake.lock`
(the current directory, or `--flake DIR`), matches each input's locked and
original URL against the declared URLs and aliases across spellings
(scp-style, `ssh://`, `git+ssh://`, HTTPS, `github:`), and prints
`--override-input <input> git+file://<checkout>` for each match, followed
by `--no-write-lock-file`. That is the whole interface, an argument list
or a command run with it:

```sh
eval "nix build $(workspace-overrides) .#thing"
workspace-overrides -- nix build .#thing
```

Nothing applies overrides implicitly, so every override is visible on the
command that uses it, and the lock file is never written. The `--` form
runs only nix commands that do not write a lock. Checkouts are found
relative to the workspace root, `$DEVENV_ROOT` inside the workspace shell
(`--root` sets it).

Inputs that no URL can match, such as a relative `path:` input backed by
a submodule, are mapped with `--map <input>=<key>` or, in the
declaration, `workbench.workspace.overrides.<input> = "<key>"`; nested
inputs are addressed as `a/b`. `--checkout <key>=<dir>` points one
repository at another checkout, such as a worktree, for one run, and
`--only <key or group>` limits the set. `git+file` sees uncommitted edits
to tracked files but not new files until they are added with `git add -N`;
the command reminds you when a checkout has untracked files, and
`--scheme path` uses `path:` instead.

### Worktrees and Herdr

The Home Manager half, `homeModules.workspace` (also part of
`homeModules.workbench`), takes `workbench.workspace.root`, the absolute
path of the workspace root. Setting it makes git record worktree links as
relative paths, so checkouts survive moving the tree, and points Herdr's
`worktrees.directory` at `worktreeDir`, by default `<root>/.worktrees`,
where Herdr creates `<repo>/<branch>` checkouts. Herdr is configured only
where a `programs.herdr` option exists.

`homeModules.herdr` is core's `programs.herdr`: `enable` (default false),
`package` (yours to supply; core pins no Herdr) and `extraConfig` in
Herdr's own key names, rendered to TOML. Herdr writes runtime state into
the same `config.toml`, so the file is not a store link; the wrapped
`herdr` reconciles the keys Nix owns into the live file at launch and
keeps the rest. It is part of `homeModules.workbench`. Flake-parts
consumers do not get it through `flake.modules.homeManager`, where it
could collide with a herdr module of their own; they import
`inputs.<core>.homeModules.herdr` explicitly. A consumer that already
carries its own `programs.herdr` module drops it in favour of core's, or
imports `homeModules.workspace` alone.

### Instance pattern

The workspace root is itself a small repository. It tracks the
declaration and a little scaffolding; the repositories beneath it are
ordinary checkouts with their own history, and worktrees live under
`<root>/.worktrees`. To create one:

```sh
mkdir ~/src && cd ~/src
nix flake init -t <core>#workspace
git init
```

This writes `flake.nix` with an empty declaration, an `.envrc` that loads
the dev shell, and an allowlist `.gitignore` that ignores everything
except those files and `flake.lock`, so checkouts, `.worktrees/`, the
rendered `mani.yaml` and shell state never show up in the workspace
repository's status. Set the core input in `flake.nix` to the flake you
consume, declare `remotes` and `repos`, enter the shell with
`direnv allow`, and run `mani sync`. Point Home Manager's
`workbench.workspace.root` at the same directory.

## Consuming

Internals are dendritic (every file under `modules/` is a flake-parts
module, auto-imported via import-tree; `_`-prefixed paths are skipped).
Consumers do **not** need any of that — the supported surfaces are:

- `flakeModules.workbench` (also `default` and legacy `agentic`) — flake-parts
  consumers.
- `devenvModules.workbench` (also `default` and legacy `agentic`) — the
  project shell bootstrap.
- `homeModules.workbench` (also `default` and legacy `agentic`) — user-tier
  (home-manager) delivery.
- `devenvModules.workspace`, `homeModules.workspace` and `homeModules.herdr`
  — the two [workspace](#workspace) halves and core's `programs.herdr`. The
  devenv half is imported on its own; the Home Manager half and `herdr` are
  also part of `homeModules.workbench`.
- `templates.<name>` — `nix flake init -t <core>#<name>`: `default`, the
  language variants, `adopt`, and `workspace`.
- `flake.modules.<class>.<name>` — dendritic consumers may merge the
  namespace directly; it carries the same modules as the aliases above.

`workbench.*` is the public option namespace for new consumers. Existing
`agentic.*` declarations remain valid and resolve to the same option graph;
the implementation still uses the Agentic paths during this compatibility
phase. Both names publish identical generated artifacts. Alias removal is a
separate breaking change after known consumers migrate.

Pi 1.1+ consumes the registry through its built-in MCP client: environments
reconcile user servers into writable `~/.pi/agent/mcp.json`, while project
bootstrap provides the trusted `.pi/mcp.json`. The legacy
`packages.<system>.pi-mcp-adapter` remains only for consumers pinned before
built-in MCP and must not be registered alongside it. Consuming flakes also
expose `pi-agent-roles`, a package of specialist prompt templates compiled from
the agent registry. See [Pi delivery](docs/pi.md) for ownership, native paths,
compatibility, and targeted checks.

### Worktree setup and verified teardown

Both shell transports include `workbench-worktree-setup` and
`workbench-worktree-teardown`. Run them from the main checkout's dev shell
against the path returned by the creator; do not infer it from the branch name.
The coordinator owns this sequence:

1. `herdr worktree create --cwd <repo> --branch <branch> --base <base> --no-focus`
   — record the returned checkout path, workspace ID and pane ID.
2. `workbench-worktree-setup --worktree <path>` — await its result.
3. Inspect `workbench-worktree-setup --check <path>`, then launch the selected
   worker in its exact pane. Failed, missing or stale setup is a **warning to
   act on, never a launcher block**; it is not evidence of readiness. Resolve
   the failure before claiming the assignment is ready or accepted.
4. After review and repository-specific resource reconciliation, run
   `workbench-worktree-teardown --worktree <path>`.
5. Only after teardown succeeds and the tree is safe to remove, the coordinator
   runs `herdr worktree remove --workspace <id>`. Stock Git refuses removal
   of worktrees containing initialized submodules, even after deinit: only for
   a coordinator-owned worktree, after successful teardown and a clean
   `git status`, the coordinator may choose
   `herdr worktree remove --workspace <id> --force`. Never force dirty or
   ambiguously owned trees. A failed cleanup vetoes removal. Teardown never
   deletes a checkout, forces Git removal or adopts resources of uncertain
   ownership.

Both runners default to the current directory. Setup preserves per-worktree
copies, isolated writable `.direnv`/`.devenv` state, and Git hooks. Declared
submodules initialize recursively, before shell warm-up. Warm-up failure is a
setup failure, not success with a warning. Rerunning setup is idempotent for
unchanged repository inputs; repository hooks must also be safe to repeat.

LAB-178: a recursive `git reset --hard` before submodule initialization can
leave a config-only submodule gitdir. Setup detects this and fails closed at
`submodule-stub`, naming the path without changing the stub or its checkout.
For manual, data-preserving repair, move **both** that gitdir and the submodule
working directory to backups outside the worktree, inspect and preserve their
contents, then run `git submodule update --init --recursive` and rerun setup.
Never delete a stub blindly or reset a fresh worktree before setup. Earlier
Git discovery commands use command-local `-c submodule.recurse=false`; setup
never changes the caller's recursion policy.

Configure `workbench.worktree` (or `agentic.worktree`):

- `traits.submodules`: recursively initialize submodules (default false).
- `traits.secretDotfiles`: files copied, never shared (default empty).
- `copyFiles`: copy absent files from the main checkout (default
  `[".envrc" ".claude"]`).
- `setupHooks` and `teardownHooks`: ordered lists of shell command strings.
  Each runs in a separate strict Bash process with the worktree as cwd; changes
  to environment or cwd do not carry into the next hook. Reference packages
  through their store paths for reproducible dependencies. Hook names in
  diagnostics are zero-based, for example `setupHooks[0]`. Setup hooks run
  after the built-in preparation and must exit zero. Every teardown hook must
  exit zero **and** print a stdout line beginning `verified:`; any stdout
  containing `skipped` (case-insensitive) fails, even alongside a verification
  line. Hooks must verify actual resource absence, not merely command dispatch.
  A failure stops the runner; no declared teardown hooks succeeds with a note.

`agentic.worktreeLib.{setupScript,hooksScript,teardownScript} pkgs` exposes the
same runners and the Git-hook isolation helper. During this additive stage,
`agentic.workmux.{traits,copyFiles}` and `agentic.workmuxLib.*` remain silent
compatibility aliases; `worktreeHooksScript` still names the Git helper.
`agentic-worktree-setup` remains an executable alias. Generated
`.workmux.yaml` and the Claude `WorktreeCreate` hook both call the canonical
setup command; no Workmux functionality is removed.

#### Setup result and check codes

Setup atomically writes `workbench-setup.json` inside the target's own
`git rev-parse --absolute-git-dir`, including on failure after Git discovery.
It contains `status` (`ok|failed`), `failedStep` (string or null),
`warmUp` (`{status, exitCode}`, with status `not-run|skipped|ok|failed`),
UTC `startedAt`/`finishedAt` timestamps, and `setupCommand` (the canonical
executable's store path). Failed setup exits nonzero; invalid arguments exit 64.
Check mode does not run setup or hooks:

| `--check [<path>]` exit | Meaning | Next action |
| --- | --- | --- |
| 0 | Current successful record | Continue observing actual harness readiness |
| 1 | Failed or malformed record | Investigate, then rerun setup |
| 2 | Missing record (or inaccessible checkout) | Run setup for the returned path |
| 3 | Record from a different setup store path | Rerun the current setup command |
| 4 | Not a linked worktree (a main checkout, or no repository) | Nothing; setup does not apply |

Every nonzero check prints one stderr line naming the worktree and its state;
codes 1–3 add the `workbench-worktree-setup --worktree <path>` action, and code
4 says setup does not apply, so a launcher can stay silent on it. A changed setup command
takes precedence over an older record's success/failure. These records do not
grant trust, prove mesh acceptance, replace native harness status or authorize
cleanup. Repository owners retain their safety flags and external-resource
lifecycle policy.

### Agent role projections

`agentic.agents.<name>` composes knowledge fragments, scope, capabilities, and
MCP requirements. Native model settings are optional: `claude.model` and
`claude.maxTurns`, `codex.model`, `codex.reasoningEffort`, and
`opencode.model`. Unset fields preserve harness defaults;
model/provider availability and authentication remain the operator's concern.

The project bootstrap places Claude and OpenCode Markdown agents and Codex
standalone TOML agents. `nix run .#write-agent-roles` refreshes those directories
without the rest of shell bootstrap. Nonempty unmanaged directories are refused
rather than overwritten. Rendered farms are also available through
`agentic.agentsLib.{claudeAgentsDir,codexAgentsDir,opencodeAgentsDir} pkgs`.
Pi consumes the shared body as a prompt in its current session, not as a native
subagent or automatic model switch. Codex roles inherit their parent's sandbox;
capabilities are not a universal security boundary. Codex's launch-time reader
rejects individual role symlinks, so its directory contains regular TOML files.

`platforms` selects where an agent is rendered (default: the four harnesses).
An agent that lists `cotal` and sets `cotal.role` becomes a Cotal persona
(`.cotal/agents/<name>.md`): mesh identity and channel ACLs
(`cotal.{role,agent,model,tags,subscribe,allowSubscribe,allowPublish}`) in the
frontmatter. Tags combine `cotal.tags` with enabled `edit`, `exec` and `web`
capabilities, without duplicates. The persona body starts with bare fragment
text, then plain scope, required MCP server and capability sentences, without
a description line or headings. MCP references are validated even for Cotal-only
agents: undefined servers fail rendering and external servers warn.
`scope.delegateTo` must name registered agents on every platform.
Optional `cotal.escalateTo` names a registered Cotal agent with a role; the body
directs decisions and escalations to that role through roster lookup, since
presence names change on restart. `packages.<system>.cotal-personas` is the link
farm; the environment places it at its space root, since a persona catalog
belongs to a mesh, not a project. Neither MCP requirements nor escalation targets
are frontmatter keys. No Cotal control-plane capability (`spawn`, `run`) is
rendered: starting agents is the environment's launcher concern.

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
