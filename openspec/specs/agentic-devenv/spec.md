# agentic-devenv Specification

## Purpose
Project shell bootstrap of workflow artifacts (MCP config, agent dirs, memory plane) plus creator-neutral worktree setup, teardown and per-worktree hook helpers. It is worktree-aware and consumable through both the flake-parts and devenv-native transports, and needs no generated worktree-manager configuration.
## Requirements
### Requirement: Shell bootstrap of workflow artifacts
The Devenv module SHALL place MCP config (`.mcp.json`, OpenCode configuration,
and `.codex/config.toml`), agent directories (`.claude/agents` and
`.opencode/agents`), the generated `.serena/project.yml`, and the generated
read-only memory namespace. Registries SHALL supply those artifacts. Bootstrap
SHALL be idempotent when its inputs are unchanged. Project MCP files SHALL use
Devenv's managed-file lifecycle rather than shell-entry `ln` commands. Dynamic
operations that cannot use managed files MAY remain in shell bootstrap.
`AGENTS.md` and `CLAUDE.md` SHALL remain committed artifacts governed by
`agentic-agents`, not shell-entry placements. Bootstrap MUST NOT generate or
require `.workmux.yaml` after retirement.

#### Scenario: fresh clone becomes workflow-complete
- **WHEN** a consumer repo is cloned and its dev shell entered once
- **THEN** all three project MCP artifacts, agent directories and memory artifacts are present and match the declared configuration
- **AND** committed instructions remain available from the clone without a generated Workmux configuration

#### Scenario: managed project MCP files are stable
- **WHEN** the shell is re-entered with unchanged registry inputs
- **THEN** Devenv reports no conflicting ownership and the project MCP files continue to point to the same rendered store artifacts

#### Scenario: conflicting regular project file is preserved
- **WHEN** a Devenv-managed MCP target is occupied by an unrelated regular file
- **THEN** shell preparation fails with a diagnostic instead of silently overwriting the file

### Requirement: Flake-first devenv module, native transport optional
The Devenv module SHALL be fully functional under flake consumption (the flake-parts `devenv.shells` path) — this is the primary contract and no capability may require the devenv-native transport. The module SHALL additionally be consumable devenv-natively (`devenv.yaml` imports / polyrepo `inputs.<name>.devenv.config`) as an opt-in for repos wanting the eval-cache/worktree benefits; a repo using the native transport alongside a flake MUST keep the two core pins coherent (`devenv.yaml` generated from or CI-checked against `flake.lock`, which remains the authoritative version statement). Both transports SHALL use the same Devenv managed-file declarations and project-tier renderer for Claude Code, OpenCode, and Codex. Where Devenv's first-party integrations already own a compatible artifact without creating another writer, the module SHALL build on them; otherwise the generic Devenv files layer SHALL provide transport-neutral placement.

#### Scenario: flake consumption is complete
- **WHEN** a consumer uses only the flake-parts transport
- **THEN** every module capability, including all three project MCP artifacts, is available with no devenv-native config present

#### Scenario: opt-in devenv-native consumption matches
- **WHEN** a repo opts into the devenv-native transport and enters the
  shell
- **THEN** the same workflow artifacts and project MCP server-name sets are produced as under flake-parts consumption, and the pinned core revision matches the `flake.lock` pin where a flake is present

#### Scenario: existing harness-owned settings retain one writer
- **WHEN** a repository has a regular harness settings file outside the MCP artifact targets
- **THEN** enabling project MCP delivery does not cause Devenv or mcp-servers-nix to take ownership of that settings file

### Requirement: One worktree setup path for all creators
Worktree preparation SHALL use one repository-owned setup script for every
supported creator, including coordinator-run Herdr creation and Claude Code's
`WorktreeCreate` hook. The script SHALL initialize declared submodules, prepare
the environment and isolate Git hooks and writable state per worktree. It MAY
reuse shared Nix store outputs. It MUST NOT share writable `.direnv` or `.devenv`
state. Creators SHALL await the setup result before launching a harness. A failed
setup SHALL remain visible and MUST NOT be reported as readiness. Creators MUST
NOT carry divergent copies of setup logic or require Workmux to invoke it.

#### Scenario: supported creators prepare worktrees identically
- **WHEN** a coordinator creates one worktree through Herdr and Claude Code creates another through its native worktree mechanism
- **THEN** both invoke the same setup script and yield equivalent preparation for the declared repository traits
- **AND** both preserve per-worktree hooks and writable state without Workmux

#### Scenario: setup fails before launch
- **WHEN** repository preparation fails
- **THEN** the creator exposes the setup failure before launching a worker and does not treat a workspace-created event as setup completion

#### Scenario: linked worktrees disable fsmonitor without changing the main checkout
- **WHEN** setup prepares a linked worktree whose main checkout inherits `core.fsmonitor=true`
- **THEN** it enables per-worktree configuration and pins `core.fsmonitor=false` directly in the linked worktree's own `config.worktree`, without changing the global setting, the main checkout's fsmonitor setting, or `core.untrackedCache`
- **AND** before Nix discovery or submodule initialization, the named `fsmonitor` step stops only that checkout's running daemon, tolerating a not-running stop race or an unavailable builtin, and waits at most five seconds before failing if status still reports running
- **AND** it probes only `fsmonitor--daemon.ipc` in that linked gitdir with a Unix-socket connection; connection refused or no such socket permits removal only of a socket file, while a listener, non-socket file, or uncertain probe fails at `fsmonitor` with the path without removing it
- **AND** stale socket removal logs `removed stale fsmonitor socket <path> (no listener)` to stderr and records the path in `workbench-setup.json` under `fsmonitor.staleSocketRemoved`; setup asserts the socket is gone and never touches `fsmonitor--daemon/`, the common gitdir's sockets, or another worktree's sockets
- **AND** repeating setup preserves the same configuration; the shell-entry hooks task shares only the config pin, not daemon handling

#### Scenario: fsmonitor setup does not apply to the main checkout
- **WHEN** setup runs in a main checkout rather than a linked worktree
- **THEN** it neither pins fsmonitor nor probes or stops that checkout's daemon

### Requirement: Worktree-aware bootstrap
Bootstrap SHALL handle Git worktree indirection. It MUST NOT assume `.git` is a
directory. It SHALL resolve a `.git` file that points into a linked-worktree
Git directory. If current Nix or Devenv cannot initialize a worktree of a
submodule, preparation SHALL emit a diagnostic that names the constraint and
the ad-hoc `nix shell` workaround. That diagnostic SHALL run before shell entry,
through the `.envrc` wrapper or setup script, so it still runs when the shell
cannot start. Preparation MUST NOT leave silent partial artifacts.

#### Scenario: worktree of the parent repo works
- **WHEN** the shell is entered in a Herdr-created worktree of a top-level repo
- **THEN** bootstrap completes as it does in the primary checkout without a Workmux dependency

#### Scenario: known-broken environment degrades explicitly
- **WHEN** the shell is entered in a worktree of a submodule where Devenv initialization fails before enterShell
- **THEN** the `.envrc` wrapper or setup script emits the constraint and ad-hoc `nix shell` workaround before placing partial artifacts
