# agentic-layering Specification

## Purpose
The core/env/repo layering contract of the agentic environment: what may live in the org-neutral agentic core vs a private env layer vs a consuming repo, with versioned consumption so independent environments track core separately.
## Requirements

### Requirement: Org-neutral core
The `agentic` core flake SHALL contain no environment-specific values: no
forge hostnames, secret mounts/addresses, model endpoints, host names, or
org-specific knowledge fragments. Every environment-specific value MUST
enter through a module option supplied by an env layer or consuming repo.

#### Scenario: core contains no environment endpoints
- **WHEN** the core repo is searched for environment-specific identifiers (e.g.
  an environment's forge hostname, vault mount names, its hostnames)
- **THEN** no matches exist outside of documentation examples clearly
  marked as examples

#### Scenario: core evaluates without an env layer
- **WHEN** a minimal consumer imports core modules and supplies only the
  required options (no env layer present)
- **THEN** evaluation succeeds and renderers produce artifacts using only
  the supplied values

### Requirement: Env layer supplies environment identity
An env layer (e.g. a private `agentic-<org>` module in an environment repository) SHALL
supply forge instances, secret backend configuration, model/provider
endpoints, and org-specific knowledge fragments by setting core options —
without redefining core schemas or renderers.

#### Scenario: env layer configures without forking
- **WHEN** an environment repository composes core + its env layer
- **THEN** rendered artifacts contain environment endpoints sourced exclusively
  from the env layer's option values, and no core file required
  modification

### Requirement: Conventional module exports over dendritic internals
Core MAY organize its internals dendritically, but SHALL expose
conventional outputs to consumers: `flakeModules.default` (plus named
entries), `devenvModules.default`, and `homeModules.default` where
applicable — the multi-adapter shape established by mcp-servers-nix and
devenv. Dendritic-aware consumers MAY additionally consume the
`flake.modules.<class>.<name>` namespace directly; both channels SHALL
expose the same modules.

#### Scenario: non-dendritic consumer uses standard outputs
- **WHEN** a plain flake-parts repo imports core's `flakeModules.default`
  (no import-tree, no dendritic layout)
- **THEN** the registry, agent, and devenv modules are fully usable with
  no dendritic machinery required

#### Scenario: dendritic consumer merges the namespace
- **WHEN** a dendritic consumer (e.g. an environment repository) composes core and an env
  layer that both contribute to `flake.modules.*`
- **THEN** the namespaces merge natively via the module system with no
  extra glue

### Requirement: Versioned consumption across environments
Core SHALL be consumable by at least two independent environments pinned to
different versions. Releases MUST be tagged; consuming flakes reference a
tag or locked rev, never an implicitly-tracked branch contract.

#### Scenario: environments pin independently
- **WHEN** home pins core at tag A and a second consumer pins tag B
- **THEN** both evaluate independently with their pinned behavior

### Requirement: Layering does not require submodule composition
The layering contract SHALL function when core is consumed as a plain flake
input (fetched by URL/rev), with no assumption that layers are mounted as
git submodules of the consumer.

#### Scenario: consumption without submodules
- **WHEN** a consumer adds core as a remote flake input with no submodule
  mounting
- **THEN** all core modules, renderers, and templates function identically
  to submodule-mounted consumption
