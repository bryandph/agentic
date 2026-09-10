# Pi delivery

## Public contract

- Core `packages.<system>.pi-mcp-adapter` is a **local Pi package root** with
  `package.json`, guarded `agentic.ts` entry, upstream sources and skill, and
  complete non-host runtime `node_modules`. Register its path in Pi's writable
  `settings.json` `packages` array, or pass `pi -e <path>`. Do not run `pi install`
  or put an npm/git source in the managed package entry.
- Core `homeModules.default` and the consumer's wired `homeModules.agentic` /
  `flake.modules.homeManager.agentic` expose
  `agentic.mcp.sharedUserConfig.enable` (default `false`). Enabled, it defaults
  `programs.mcp.enable` to `true` and reuses native HM delivery when its enabled
  XDG file targets `~/.config/mcp/mcp.json`. There is only one writer per target.
  With custom XDG placement or a disabled native writer, a fallback at Pi's
  literal shared path reuses upstream serialization of final `programs.mcp.servers`.
  The existing `agentic.mcp.userServers` bridge is unchanged; the option does not
  disable native MCP integration or change the consumer's XDG configuration.
- Project delivery reuses `.mcp.json` from the existing registry renderer and
  devenv bootstrap. No new flavor or server list.
- Consumers importing `flakeModules.default` get
  `packages.<system>.pi-agent-roles`, a local Pi package with
  `/role-<registry-name>` prompt templates. Transport-neutral helpers are
  `config.agentic.agentsLib.piPackage pkgs`, `renderPi name agent`, and
  `compileBody name agent`. Register the role package through the same local
  package mechanism when wanted; shell entry does not auto-install it.

The environment owns Pi itself and reconciliation of managed package entries
into writable settings. Core never owns Pi settings, auth, trust, sessions,
metadata cache, `~/.pi/agent/mcp.json`, or `.pi/mcp.json`. Pi overrides remain
mutable. Upstream honors `PI_CODING_AGENT_DIR` for a custom agent directory.

Role templates reuse the exact compiled body from the other renderers and add
capability instructions plus `$ARGUMENTS`. They are ordinary prompts in the
current session, not an enforced tool sandbox or native subagents. Workmux owns
separate workers; no `.pi/agents` registry or orchestration extension is added.

## Release and runtime closure

The npm `latest` release and package gallery were verified as **2.32.1**.
The npm tarball reports gitHead
`10a45367e033a32026987a75d6f401e37340c86f`; its manifest, config loader, extension
entry, transport manager, and interpolation source match that commit.
The derivation pins the tarball by SHA-512. The committed npm lock fixes every
dependency tarball/integrity; `buildNpmPackage` installs from a fixed-output npm
cache with lifecycle scripts disabled. Native keyring optional dependencies are
included for the target system; Linux receives ELF patching.

Pi supplies its documented host peers (`pi-ai`, `pi-tui`, `pi-coding-agent`, and
`typebox`), so they are not duplicated in `node_modules`. Integration is tested
with Pi **0.85.1**. Zod, the MCP SDK, and all other runtime dependencies are
packaged. The registry supplies absolute Nix-store stdio wrappers; managed
server delivery uses no npx, runtime npm fetch, or imperative installer.

The small committed patch adds a global-only config loader, makes early config
discovery follow session cwd, refreshes the trust-filtered snapshot on every
session start, disables load-time background initialization, and
suppresses resolved URL/header bytes in invalid-value errors. The Pi manifest
selects the trust wrapper; upstream entry/exports remain available to explicit
SDK consumers and are not themselves a project-trust boundary.

## Trust and merge behavior

Upstream reads project MCP automatically and can start eager servers during
extension load. A global extension does not inherit Pi's project-resource guard.
The packaged entry registers against a global-only snapshot. After stopping the
previous session runtime, every `session_start` reevaluates trust for the new
context cwd and replaces the snapshot before initializing servers. This also
covers SDK hosts that retain the extension instance across session switches;
previous project tools are deactivated before loading the next snapshot.

For native Pi trust resources it uses `ctx.isProjectTrusted()`, including
session-only and CLI decisions. Pi 0.85.1 treats a directory containing only
`.mcp.json` or `.pi/mcp.json` as implicitly trusted, before consulting saved
denials. In that case the wrapper additionally requires a positive decision
from Pi's public `ProjectTrustStore` (including parent-directory decisions), or
explicit `--approve`. `--no-approve` wins. A bare-MCP directory with only global
`defaultProjectTrust = "always"` still requires saved trust or `--approve`.
Use Pi `/trust` and restart to save a decision. Core implements no additional
trust store and never writes Pi's trust file.

Without project trust, the wrapper supplies an isolated snapshot of shared
global tiers and Pi global overrides. Project configs, compatibility imports,
plugin/package MCP discovery, and `--mcp-config` are excluded. User-tier servers
remain available, including user-declared commands running in the session cwd.
Both trusted and untrusted sessions use upstream isolated-config mode, which
disables setup/config-edit panels and enable/disable commands. Edit the mutable
Pi override files and restart/reload instead. This prevents ambient project
access through configuration commands and keeps trust selection session scoped.
This is an input-loading guard, not an OS sandbox for user-approved global
servers or Pi tools.

Trusted sessions keep upstream field-wise merge order (later wins):

1. `~/.config/mcp/mcp.json`
2. `~/.agents/mcp.json`
3. `~/.agents/mcp/mcp.json`
4. `<Pi agent dir>/mcp.json`
5. `<session cwd>/.mcp.json`
6. `<session cwd>/.pi/mcp.json`

Project discovery uses exact session cwd, without searching ancestor `.mcp.json`
files. Changing an HTTP URL strips inherited auth fields; changing transport
strips incompatible inherited fields. Mutable Pi overrides preserve shared
files; set server `disabled` in the mutable override file when needed. Explicit compatibility imports
retain upstream behavior in trusted sessions.

## Interpolation, lifecycle, and discovery

Registry HTTP headers remain literal `${VAR}` / `Bearer ${VAR}` references;
the existing shell bootstrap supplies environment values at runtime. Stdio
wrappers resolve secrets through the backend before exec. The adapter expands
HTTP headers at connection without mutating source configuration. Missing
header variables follow upstream empty-string substitution; missing URL
variables fail before a request. Never place secret literals in registry data.

Resolved headers are not written to configs, metadata, or traces. Upstream
metadata invalidation hashes resolved connection identity (including credentials)
with SHA-256; only the digest is stored. Tests assert no resolved token bytes.
Server results/stderr are server-controlled: servers must avoid returning or
logging credentials. OAuth is an explicit separate upstream feature using an
OS credential store; registry runtime-variable credentials do not use it.

Actual 2.32.1 source behavior differs from a strict reading of “lazy”:

- Missing metadata cache triggers a one-time connection to **all enabled
  servers**, even lazy servers, to discover tools.
- With valid metadata, lazy servers stay disconnected until called, while
  search/list/describe work offline. Eager/keep-alive servers connect at session
  startup; uncached configured direct tools also trigger discovery.
- Lazy servers have the upstream idle timeout; eager servers have no implicit
  idle timeout. Upstream owns reconnect, cancellation, and shutdown. Core
  prohibits background startup before `session_start`.

Generated root guidance teaches `mcp({search: "capability"})`,
`mcp({describe: "<returned name>"})`, then
`mcp({tool: "<returned name>", args: {...}})`. Inspect one server with
`mcp({server: "name"})`, or connect with `mcp({connect: "name"})` when metadata
is absent. Activate Serena before other Serena tool calls. The shared default
full context is upstream `agent`, exposing activation and symbolic tools;
memory-only includes activation plus memory tools. Consumers explicitly
selecting `claude-code` must account for its `single_project` setting, which
removes activation. Tool exposure remains proxy-first; there is no duplicate
Serena entry or large global direct-tools list.

## Targeted validation

```sh
nix build .#pi-mcp-adapter .#checks.aarch64-darwin.pi-mcp \
  .#checks.aarch64-darwin.agents-registry .#checks.aarch64-darwin.serena \
  .#checks.aarch64-darwin.adapters .#checks.aarch64-darwin.org-neutral \
  .#checks.aarch64-darwin.pi-mcp-hm
nix run .#pi-mcp-runtime-check -- /absolute/path/to/pi
```

The runtime app uses an isolated temporary home, fake credentials, local HTTP,
and pinned stdio fixtures. It tests actual Pi loading/host peers, effective
merged server sets, interpolation, proxy calls, cwd, cold/warm/eager lifecycle,
trust allow/deny/parent/CLI cases, and credential-free artifacts. Retained-instance
tests alternate trusted and denied cwd contexts with real upstream handlers and
proxy calls, both with and without intervening shutdown. RPC tests exercise
actual session switching and new sessions within one Pi process. No model/API
calls or real credential-store access are needed. The Nix check evaluates the
real exported HM adapter against test-pinned Home Manager 26.05, including its
native MCP writer, assertions and final home-file target uniqueness. Normal,
custom-XDG, retargeted, disabled-writer, empty-registry and opt-out cases are
covered. The test builds HM home-files; it never activates a configuration.
Consumers still own their production Home Manager version and full configuration.

Validation covers aarch64-darwin and Pi 0.85.1. Linux/native keyring operation,
real OAuth, and live fleet MCP sessions need environment-level verification;
dependencies are declared for all four supported systems.

Sources: [release source](https://github.com/nicobailon/pi-mcp-adapter/tree/10a45367e033a32026987a75d6f401e37340c86f),
[Pi 0.85.1 security](https://github.com/earendil-works/pi-mono/blob/v0.85.1/packages/coding-agent/docs/security.md),
[Pi package contract](https://github.com/earendil-works/pi-mono/blob/v0.85.1/packages/coding-agent/docs/packages.md).
