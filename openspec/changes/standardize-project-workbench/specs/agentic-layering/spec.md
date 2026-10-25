## MODIFIED Requirements

### Requirement: Org-neutral core
The public Workbench core flake SHALL contain no environment-specific values: no forge hostnames, secret mounts/addresses, model endpoints, host names, or org-specific knowledge fragments. Every environment-specific value MUST enter through a module option supplied by an environment layer or consuming repository. Agent, MCP, skill, knowledge, and project-profile modules SHALL share this same publication boundary.

#### Scenario: core contains no environment endpoints
- **WHEN** the Workbench core repo is searched for environment-specific identifiers such as an environment's forge hostname, private secret mount names, or its hostnames
- **THEN** no matches exist outside documentation/fixtures clearly marked as non-live examples

#### Scenario: core evaluates without an environment layer
- **WHEN** a minimal consumer imports Workbench modules and supplies only their required options with no environment layer present
- **THEN** evaluation succeeds and profiles/renderers produce artifacts using only public inputs and supplied values

### Requirement: Env layer supplies environment identity
An environment layer SHALL supply forge instances, secret-backend configuration, model/provider endpoints, organization knowledge/skills, and environment defaults by setting Workbench options without redefining core schemas, profiles, or renderers. A private environment layer SHALL live in a narrow capsule owned by its environment repository that can evaluate without importing host configurations or the complete fleet projection graph.

#### Scenario: environment layer configures without forking
- **WHEN** the environment repository or another repository of that environment composes Workbench core with the private capsule
- **THEN** rendered artifacts contain environment values sourced exclusively from capsule option values and no public core file requires modification

#### Scenario: capsule is independently consumable
- **WHEN** a standalone project of that environment imports the private capsule
- **THEN** it receives Workbench environment policy without evaluating the environment repository's host configurations, deployment outputs, or fleet projections

### Requirement: Conventional module exports over dendritic internals
Workbench MAY organize internals dendritically, but SHALL expose conventional outputs to consumers: `flakeModules.default` plus named Workbench entries, `devenvModules.default` plus named profiles, and `homeModules.default` where applicable. Dendritic-aware consumers MAY additionally consume the `flake.modules.<class>.workbench` namespace directly; conventional and dendritic channels SHALL expose equivalent modules.

During the compatibility window, Agentic-named outputs SHALL alias the canonical Workbench modules rather than re-evaluate or reimplement them.

#### Scenario: non-dendritic consumer uses standard outputs
- **WHEN** a plain flake-parts repository imports Workbench's conventional flake and Devenv modules
- **THEN** the registries, profiles, adapters, and bootstrap are usable with no import-tree or environment-repository machinery

#### Scenario: compatibility output is identical
- **WHEN** the same fixture evaluates through a canonical Workbench output and its deprecated Agentic alias
- **THEN** the resulting option values and generated artifacts are identical

### Requirement: Versioned consumption across environments
Workbench SHALL be consumable by at least two independent environments pinned to different versions. Releases MUST be tagged; consuming flakes SHALL reference a tag or locked revision, never an implicitly tracked branch contract. The repository/remote rename SHALL occur only after a reachable tagged revision exposes the canonical Workbench API and compatibility aliases.

#### Scenario: environments pin independently
- **WHEN** two environments pin different Workbench tags
- **THEN** both evaluate independently with their pinned behavior

#### Scenario: remote rename does not strand old locks
- **WHEN** the primary and mirror repositories adopt the Workbench name
- **THEN** the pre-rename compatibility revision remains reachable and existing locked consumers can migrate without resolving a mutable branch

### Requirement: Layering does not require submodule composition
The Workbench layering contract SHALL function when core is consumed as a plain flake input fetched by URL/revision, with no assumption that layers are mounted as git submodules of the consumer.

#### Scenario: consumption without submodules
- **WHEN** a consumer adds Workbench as a remote flake input with no submodule mounting
- **THEN** all core modules, profiles, renderers, and templates function identically to a locally mounted checkout

## ADDED Requirements

### Requirement: Canonical namespace migrates without a flag day
`workbench.*` and Workbench-named flake outputs SHALL be the canonical API. Existing `agentic.*` options and Agentic-named outputs SHALL remain deprecated aliases for at least one tagged release after all canonical outputs are published and until known consumer migrations are complete. Both names MUST feed one underlying option/renderer authority; aliases MUST NOT form a second configuration plane.

#### Scenario: mixed migration remains deterministic
- **WHEN** a repository uses a deprecated Agentic import while its environment layer uses canonical Workbench configuration
- **THEN** the module system resolves one shared configuration and generated artifacts contain no duplicate declarations
