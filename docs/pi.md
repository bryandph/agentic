# Pi delivery

## Native MCP contract

Pi 1.1 and newer ship an MCP client. Consumers should use it instead of the
legacy `pi-mcp-adapter` extension:

- User-tier registry servers are serialized with the existing Home Manager
  `programs.mcp` schema and reconciled into Pi's writable
  `~/.pi/agent/mcp.json` by the environment that owns Pi. The reconciler should
  own registry server definitions while preserving foreign servers, unrelated
  top-level settings, and Pi's mutable `enabled`, `exposure`, and
  `toolExposure` fields.
- Project-tier delivery links `.pi/mcp.json` to the same generated Claude-schema
  artifact used for `.mcp.json`. Pi loads it only after its native project trust
  decision.
- Runtime `${VAR}` references remain literal in generated JSON. Stdio wrappers
  resolve scoped secrets before exec; the launching environment supplies HTTP
  variables. No resolved credential belongs in the Nix store or a rendered
  file.
- Pi owns MCP OAuth credentials in `~/.pi/agent/mcp-auth.json`. Core does not
  read or render that file.

Core's `agentic.mcp.sharedUserConfig.enable` remains available for compatibility
clients that read `~/.config/mcp/mcp.json`; native Pi does not use that path.
The environment still owns Pi settings, authentication, trust, sessions, MCP
overrides, and reconciliation policy. Upstream honors `PI_CODING_AGENT_DIR` for
a custom agent directory.

## Native behavior

Pi reads user servers from `~/.pi/agent/mcp.json` and project servers from
`.pi/mcp.json`. A project entry replaces the user entry of the same name;
control-only project entries can override `enabled`, `exposure`, and
`toolExposure` while retaining the user connection definition.

The built-in client provides:

- stdio and streamable HTTP transports;
- environment and command interpolation for environment/header values;
- built-in OAuth storage and refresh;
- direct, deferred, codemode, and hidden exposure;
- MCP resources and extension permission-pipeline integration;
- `pi mcp` shell commands and `/mcp` interactive management.

Project trust, config parsing, reconnect, cancellation, shutdown, OAuth, and
tool exposure are upstream Pi behavior. Agentic does not replace those controls.
Use `pi mcp list` for connection diagnostics and `/mcp` for interactive state.

## Roles and workflow resources

Consumers importing `flakeModules.default` get
`packages.<system>.pi-agent-roles`, a local Pi package with
`/role-<registry-name>` prompt templates. Transport-neutral helpers are
`config.agentic.agentsLib.piPackage pkgs`, `renderPi name agent`, and
`compileBody name agent`. Register the role package through the environment's
writable package reconciliation when wanted; shell entry does not auto-install
it.

Role templates reuse the exact compiled body from the other renderers and add
capability instructions plus `$ARGUMENTS`. They are ordinary prompts in the
current session, not an enforced tool sandbox or native subagents. Coordinators
start separate workers in Herdr worktrees (`herdr worktree create`); no `.pi/agents` registry or orchestration extension is added.

## Coordinator worktrees

The repository shell supplies creator-neutral setup and verified teardown for
Pi as well as the other harnesses. The coordinator runs:

```text
herdr worktree create --cwd <repo> --branch <branch> --base <base> --no-focus
workbench-worktree-setup --worktree <returned-path>
workbench-worktree-setup --check <returned-path>
<launch the selected worker in the returned pane>
<review results and reconcile repository-owned resources>
workbench-worktree-teardown --worktree <returned-path>
herdr worktree remove --workspace <returned-workspace-id>
```

Wait for setup before launching. Check exits 0 for current success, 1 for
failure, 2 for a missing result and 3 for a stale setup executable. A nonzero
check emits one actionable warning, **never a launcher block**. Act on the
warning; do not mistake process launch for setup success or assignment
acceptance. Trust projection is also warning-only; an actual Pi trust or
authentication prompt still needs operator attention. Core never grants trust.

Setup runs declared recursive submodule initialization, file copies, state and
Git-hook isolation, shell warm-up, then ordered `workbench.worktree.setupHooks`.
Its JSON result lives in the worktree's own gitdir, not a shared checkout file.
Warm-up failure is recorded as failure. `agentic-worktree-setup` remains an
alias for the canonical creator-neutral command.

Each `workbench.worktree.teardownHooks` command must exit zero and print a
stdout line starting `verified:`, without printing `skipped`. Any failure
stops cleanup and vetoes removal; no hooks succeeds with a note. Only the
coordinator removes a reviewed, safe worktree after verified cleanup; the
runner never removes it or uses force. Stock Git refuses removal of a
worktree with initialized submodules even after deinit; after verified teardown
and clean `git status`, its owning coordinator may choose
`herdr worktree remove --workspace <returned-workspace-id> --force`. Never force
dirty or ambiguously owned trees. A `submodule-stub` setup failure instead
requires the manual, data-preserving backup repair described in the README;
setup does not auto-repair or delete submodule state. See the
[setup options, result schema and exit codes](../README.md#worktree-setup-and-verified-teardown).

## Legacy adapter compatibility

`packages.<system>.pi-mcp-adapter` remains exported temporarily for consumers
pinned to Pi releases without built-in MCP. Installing an extension that owns
`/mcp` disables Pi's built-in MCP session support, so current consumers MUST NOT
register the adapter alongside native MCP. The compatibility package retains
its pinned closure and historical tests until a separately reviewed removal.

## Validation

Core compatibility checks remain available:

```sh
nix build .#pi-mcp-adapter \
  .#checks.aarch64-darwin.pi-mcp \
  .#checks.aarch64-darwin.pi-mcp-hm
```

Current consumer validation should additionally:

1. build the Home Manager files and assertion checks;
2. verify package reconciliation retires the adapter without touching foreign
   package entries;
3. verify native MCP reconciliation preserves foreign servers and mutable
   exposure controls;
4. run `pi mcp list` against an isolated local stdio fixture without model/API
   calls; and
5. verify `.pi/mcp.json` is generated for a trusted project.

Authoritative upstream behavior is documented by the Pi release installed by
the consumer (`docs/mcp.md`, `docs/packages.md`, and `docs/security.md`).
