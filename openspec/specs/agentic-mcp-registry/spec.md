# agentic-mcp-registry Specification

## Purpose
Single declarative MCP server definition set with user/project tiering, a modular CLI secret backend, forge instances, and pinned server packages — delivered through upstream modules so every consumer artifact derives from one definition, with coverage for MCP-less harnesses.
## Requirements
### Requirement: Single server definition, tiered delivery via upstream modules
The registry SHALL hold exactly one definition per MCP server, carrying a tier attribute (`user` | `project`). Delivery adapters SHALL feed that one definition into the upstream registries rather than rendering file formats in core: home-manager `programs.mcp`/mcp-servers-nix wiring for user-tier servers, and mcp-servers-nix project flavors for `.mcp.json`, `.codex/config.toml`, and OpenCode configuration. A server SHALL be definable in both tiers without duplicating its definition. The effective project-tier server-name set SHALL be identical across Claude Code, OpenCode, and Codex unless a server explicitly declares a documented harness restriction.

#### Scenario: one definition renders to all consumers
- **WHEN** a project-tier server is defined once in the registry
- **THEN** the project Claude Code, OpenCode, and Codex artifacts contain consistent configuration derived from that definition

#### Scenario: platform servers have harness parity
- **WHEN** Kubernetes, OpenTofu, AWS, Azure, and GCP are enabled for the project tier
- **THEN** each server appears in all three project artifacts with a lock-pinned executable and equivalent non-secret runtime configuration

#### Scenario: no dual definition remains after migration
- **WHEN** the environment repository's migration completes
- **THEN** platform child flakes do not export separate `mcp.servers` definitions and the compatibility bridge is absent

### Requirement: Modular CLI secret backend
Every secret SHALL be sourced at runtime by invoking a CLI — never stored
in rendered artifacts or the nix store. The backend SHALL be a command
abstraction (`secretCommand : ref -> argv`) where backends are data
(command template + package), so a new secret manager is a preset, not a
core change. Implementations this change: `vault` (OpenBao-compatible;
parameterized address and mount, generalizing the current wrapWithVault
pattern — the wired backend) and `env` (plain environment variable
passthrough for environments without a CLI manager). Backends such as
bitwarden, infisical, and 1password MUST be definable as presets without
modifying core. Server definitions SHALL declare abstract secret
requirements; the selected backend resolves them.

#### Scenario: same server, different backend
- **WHEN** the same server definition is rendered under the vault backend
  and under the env backend
- **THEN** both produce working configurations, differing only in the
  credential resolution mechanism

#### Scenario: new CLI manager without core changes
- **WHEN** a consumer defines a new backend preset (e.g. 1Password's
  `op read` or an infisical command template) via options only
- **THEN** server definitions resolve their secret requirements through
  the new CLI with no modification to core modules

#### Scenario: no secrets at rest
- **WHEN** rendered artifacts and store paths are inspected
- **THEN** no plaintext secret values are present

#### Scenario: http server secrets resolve at runtime
- **WHEN** an http server requires a secret header (e.g. an API key or
  bearer token), which cannot be delivered by wrapping a binary
- **THEN** the rendered config references an environment variable expanded
  client-side, and the shell bootstrap exports that variable via the same
  secret backend CLI — the value appears in neither the store nor any
  rendered file

### Requirement: Forges as instances
Git forges SHALL be declared as an attrset of instances, each with a kind
(github | gitea), endpoint, and secret reference. Each instance SHALL
produce its own MCP server entry. Multiple instances of the same kind MUST
be supported concurrently.

#### Scenario: public and private forges coexist
- **WHEN** an environment declares one GitHub instance and one private
  Gitea instance
- **THEN** two distinct forge MCP servers are rendered, each with its own
  endpoint and credentials

### Requirement: Pinned server packages
Every stdio MCP server in the registry SHALL resolve to a pinned package from nixpkgs, mcp-servers-nix, or another flake input locked by the consumer's `flake.lock`. The registry MUST NOT invoke servers through floating or runtime-resolved package references, including `@latest`, unversioned `npx`/`uvx`, mutable container tags, or untracked Git branches. Reusable server derivations and flavor adapters missing from mcp-servers-nix SHALL be developed as upstreamable contributions; a consumer MAY temporarily pin a concrete fork integration revision while those contributions are under review. Reusable BPH-maintained packages that exist only in a consumer overlay SHALL move to the lock-pinned fork integration after equivalent focused package/module tests pass. Serena specifically SHALL resolve to a lock-pinned package through mcp-servers-nix.

#### Scenario: server executable is store backed
- **WHEN** any project stdio MCP server is rendered
- **THEN** its command resolves to a Nix store path whose source or release artifact is fixed by a lock file and content hash

#### Scenario: platform servers do not resolve packages at runtime
- **WHEN** Kubernetes or a Terraform-family MCP server starts
- **THEN** it does not use `npx`, `uvx`, a mutable container tag, or a network fetch to resolve the server implementation

#### Scenario: temporary fork pin remains reproducible
- **WHEN** an environment consumes an unmerged mcp-servers-nix contribution
- **THEN** every consumer references a concrete reachable fork revision and changing the server implementation requires a lock update

#### Scenario: reusable consumer overlay package migrates to the fork
- **WHEN** a generic MCP package such as Woodpecker is maintained in an environment overlay and passes equivalent fork package/module tests
- **THEN** the registry resolves it from the lock-pinned mcp-servers-nix package set and the consumer-only derivation is removed

### Requirement: Harness coverage including MCP-less harnesses
Delivery SHALL cover the four target harnesses: Claude Code and OpenCode SHALL consume project- and user-tier registry artifacts, and Codex SHALL consume user-tier servers through its writable user configuration plus trusted project-tier configuration. For servers without a documented harness restriction, the effective project-tier set exposed to Claude Code, OpenCode, and Codex SHALL be equal. A project capability required by Codex, including pinned Serena and platform servers, SHALL also be eligible for user-tier delivery from the same registry definition. Pi, which has no core MCP support, SHALL have a documented MCP adapter, extension, or CLI-equivalent path. Servers whose function an agent may need on every harness SHALL declare a CLI-equivalent invocation so MCP-less harnesses are not excluded.

#### Scenario: codex receives pinned serena
- **WHEN** the registry enables Serena for the project and user tiers and the
  consumer enables Codex delivery
- **THEN** Codex's writable user configuration contains the pinned Serena
  server derived from the same definition used by project artifacts

#### Scenario: codex receives user and project registry servers
- **WHEN** the registry defines user-tier and project-tier servers and the
  consumer enables Codex delivery
- **THEN** the effective Codex configuration exposes both sets without
  duplicating server definitions in the registry

#### Scenario: project harness server sets agree
- **WHEN** all project artifacts are built from one registry evaluation
- **THEN** Claude Code, OpenCode, and Codex expose the same unrestricted project-tier server names

#### Scenario: Pi is not stranded
- **WHEN** an agent runs under Pi and needs a registry capability marked
  CLI-equivalent
- **THEN** the documented CLI path provides the same function without MCP

### Requirement: Registry validation with escape hatch
The registry SHALL validate at eval time that agent-declared MCP
requirements (see `agentic-agents`) reference defined servers. Entries
marked external SHALL be exempt (warning, not failure) to allow ad-hoc or
runtime-only servers.

#### Scenario: undefined server reference fails
- **WHEN** an agent declares `mcp = [ "nonexistent" ]` and no such registry
  entry or external marker exists
- **THEN** evaluation fails with a message naming the agent and the missing
  server

