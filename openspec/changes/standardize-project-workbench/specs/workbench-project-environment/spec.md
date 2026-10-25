## ADDED Requirements

### Requirement: Shared mechanics and domain behavior have separate owners
Workbench SHALL own reusable project mechanics that can serve multiple repository archetypes: shell bootstrap, language/tool profiles, formatting/check hooks, workflow registries, generated project artifacts, creator-neutral worktree setup primitives, and adapter delivery. A consuming repository SHALL retain its package construction, application services, processes, domain commands, deployment actions, state layout, and project-specific lifecycle scripts.

#### Scenario: finance keeps its stateful domain environment
- **WHEN** finance composes the Workbench polyglot and workflow modules
- **THEN** Workbench supplies shared language/tooling and generated workflow artifacts while finance remains the sole owner of its PostgreSQL bundle, service processes, application scripts, and database-per-worktree commands

#### Scenario: Python build remains repository-owned
- **WHEN** real-estate-search composes the Workbench Python/uv profile
- **THEN** its uv2nix workspace, Python version, package overrides, application outputs, and generated API-client dependency remain declared in that repository

### Requirement: Project profiles compose additively
Workbench SHALL publish importable project profiles for at least base, Nix, Python/uv, Rust, polyglot, and embedded Rust shapes. Profiles SHALL use ordinary module defaults and MUST NOT use force-priority overrides to disable unrelated Devenv facilities, enable stateful services, or erase consumer configuration. Consumers SHALL be able to override upstream language versions and package choices through normal Devenv/module options.

#### Scenario: stateful service composes with a language profile
- **WHEN** a repository imports the Python/uv profile and declares a PostgreSQL Devenv service
- **THEN** evaluation retains both configurations and the profile does not force containers, services, or processes to an empty value

#### Scenario: consumer selects its Python version
- **WHEN** a Python repository imports the Python/uv profile and sets its language package to Python 3.13
- **THEN** the resulting shell uses the consumer-selected package while retaining the profile's common uv/tool/hook behavior

### Requirement: Repository traits drive generic lifecycle behavior
Workbench SHALL expose typed repository traits for project identity, submodules, stateful Devenv services, cache-sharing eligibility, secret-bearing worktree files, selected profiles, and ordered lifecycle hook references. Generated bootstrap and worktree setup behavior SHALL derive from those traits. Arbitrary project lifecycle commands SHALL be supplied by the repository through explicit extension points and SHALL NOT be copied into Workbench core.

#### Scenario: submodule repository receives initialization
- **WHEN** a repository declares that it contains submodules
- **THEN** the generated worktree setup invokes submodule initialization without the repository hand-maintaining a copy of the generic setup logic

#### Scenario: finance supplies database hooks
- **WHEN** finance declares stateful services plus project-specific provision and cleanup hooks
- **THEN** Workbench orders those hook references in the generated lifecycle while the hook implementations remain in finance

### Requirement: Archetype fixtures validate the public boundary
Workbench SHALL carry self-contained evaluation fixtures for a core-only project, Python/uv project, polyglot project with stateful services, submodule infrastructure project, and private-environment composition. Core fixtures MUST NOT read sibling repositories or private environment-repository data. Checks SHALL prove additive module composition, generated-file single ownership, profile override behavior, and absence of environment identity from core-only outputs.

#### Scenario: core-only fixture is internet-portable
- **WHEN** Workbench checks evaluate the core-only and Python fixtures without the private environment layer
- **THEN** they succeed using only public locked inputs and rendered outputs contain no environment forge, host, secret-backend, or model endpoint values

#### Scenario: stateful fixture rejects unsafe cache sharing
- **WHEN** the polyglot fixture declares stateful services
- **THEN** its worktree setup does not share `.devenv` or `.direnv` state across worktrees

### Requirement: One authority owns each generated artifact
Workbench SHALL extend the existing registry and managed-file authorities rather than creating parallel renderers or file writers. A migration from repository-local mechanics SHALL remove the old declaration in the same change that enables the Workbench authority, and conflicts with unrelated regular files SHALL fail rather than overwrite them.

#### Scenario: MCP migration has no dual registry
- **WHEN** an infrastructure repository migrates its standalone shell to Workbench
- **THEN** its MCP servers derive from the one Workbench registry and its previous hand-rendered MCP declaration is absent
