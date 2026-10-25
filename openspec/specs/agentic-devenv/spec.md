# agentic-devenv Specification

## Purpose
Project shell bootstrap of workflow artifacts (MCP config, agent dirs, memory plane, generated .workmux.yaml) that is worktree-aware and consumable through both the flake-parts and devenv-native transports.
## Requirements

### Requirement: Shell bootstrap of workflow artifacts
The Devenv module SHALL place the project workflow artifacts: MCP config (`.mcp.json`, OpenCode configuration, and `.codex/config.toml`), agent directories (`.claude/agents`, `.opencode/agents`), the generated `.serena/project.yml` and generated read-only memory namespace, and the generated `.workmux.yaml` — all sourced from the registries and idempotent when inputs are unchanged. Project MCP files SHALL be declared through Devenv's managed-file lifecycle rather than created or overwritten by shell-entry `ln` commands. Dynamic operations that cannot be expressed as managed files MAY remain in shell bootstrap. `AGENTS.md` and `CLAUDE.md` are committed artifacts governed by `agentic-agents`, not shell-entry placements.

#### Scenario: fresh clone becomes workflow-complete
- **WHEN** a consumer repo is cloned and its dev shell entered once
- **THEN** all three project MCP artifacts, agent dirs, and `.workmux.yaml` are present and consistent with the repo's declared configuration (`AGENTS.md` and `CLAUDE.md` were already present in the clone as committed files)

#### Scenario: managed project MCP files are stable
- **WHEN** the shell is re-entered with unchanged registry inputs
- **THEN** Devenv reports no conflicting ownership and the project MCP files continue to point to the same rendered store artifacts

#### Scenario: conflicting regular project file is preserved
- **WHEN** a Devenv-managed MCP target is occupied by an unrelated regular file
- **THEN** shell preparation fails with a diagnostic instead of silently overwriting the file

### Requirement: Generated workmux project config
`.workmux.yaml` SHALL be generated from module options rather than
hand-maintained, with defaults keyed on declared repo traits rather than
applied universally: submodule re-initialization in `post_create` when the
repo has submodules; dev-shell cache reuse via `.direnv` symlinking ONLY
when the repo declares no stateful devenv services (services keep
per-worktree state — databases, process dirs — and must not be shared);
secret-bearing dotfiles (e.g. a vault-resolved `.env`) copied per
worktree, never symlink-shared. Repos override via options, not by
editing the generated file. The generation SHALL preserve the operational
rationale currently documented in the hand-maintained files as header
comments.

#### Scenario: submodule repo gets mitigations by default
- **WHEN** a repo with submodules and no devenv services enables the
  module without overrides
- **THEN** the generated `.workmux.yaml` contains the submodule init hook
  and the `.direnv` symlink entry

#### Scenario: services repo does not share worktree state
- **WHEN** a repo declaring stateful devenv services and a secret-bearing
  `.env` (the finance shape) enables the module without overrides
- **THEN** the generated `.workmux.yaml` omits the `.direnv`/`.devenv`
  symlinks and lists `.env` under per-worktree copies

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
Worktree preparation SHALL live in a single setup script (submodule
re-init, `direnv allow`, devenv cache reuse) invoked by every worktree
creator: the generated `.workmux.yaml` `post_create` hook and a Claude
Code `WorktreeCreate` hook at minimum. Worktree creators MUST NOT carry
divergent copies of the setup logic.

#### Scenario: workmux and Claude Code worktrees are prepared identically
- **WHEN** a worktree is created via `workmux add` and another via Claude
  Code's native worktree mechanism
- **THEN** both invoke the same setup script and yield identically
  prepared worktrees (submodules initialized, direnv allowed)

### Requirement: Worktree-aware bootstrap
The bootstrap SHALL function under git worktree gitdir indirection: it MUST
NOT assume `.git` is a directory, and MUST resolve paths correctly when
`.git` is a gitlink file pointing into a `__worktrees` gitdir. In the known
failure mode (devenv cannot initialize inside a worktree of a submodule —
if re-testing under current devenv/Nix confirms it persists), the failure
SHALL surface loudly with a diagnostic that names the constraint and the
documented workaround — it MUST NOT leave a silently half-configured
shell. Because devenv fails to initialize in that mode, the diagnostic
MUST be emitted by a component that still executes when the shell never
starts (the generated `.envrc` wrapper or the worktree setup script), not
by enterShell.

#### Scenario: worktree of the parent repo works
- **WHEN** the shell is entered in a workmux-created worktree of a
  top-level repo
- **THEN** the bootstrap completes identically to the primary checkout

#### Scenario: known-broken environment degrades explicitly
- **WHEN** the shell is entered in a worktree of a submodule where devenv
  initialization fails (and thus enterShell never runs)
- **THEN** the `.envrc` wrapper or worktree setup script emits an explicit
  diagnostic describing the worktree×submodule constraint and the ad-hoc
  `nix shell` workaround, and no partial artifacts are left behind
