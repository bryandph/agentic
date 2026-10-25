## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: Generated workmux project config
**Reason**: Workmux retires for every harness. A generated Workmux configuration
must no longer be part of the workflow contract.

**Migration**: Keep the existing setup script and trait-driven safeguards.
Expose them without a Workmux dependency and invoke them through every supported
creator. Preserve submodule setup, per-worktree copies, isolated state and hook
checks. Migrate consumers and templates before removing compatibility options
and the generator. The all-harness qualification and final approval gates in
`worktree-worker-migration` apply. Do not restore the obsolete shared-cache
symlink behavior described by the removed requirement.
