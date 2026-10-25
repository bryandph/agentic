## MODIFIED Requirements

### Requirement: Shell bootstrap of workflow artifacts
The Workbench Devenv module SHALL place the project workflow artifacts: MCP configuration, agent directories, generated Serena project/memory configuration, generated Workmux configuration, and other registry-owned project files, all idempotently and through their existing single-writer lifecycle. `AGENTS.md` and `CLAUDE.md` remain committed artifacts governed by the agents capability rather than shell-entry placements. Enabling workflow bootstrap MUST NOT implicitly enable language profiles, stateful services, or project processes.

#### Scenario: fresh clone becomes workflow-complete
- **WHEN** a consumer repository is cloned and its Workbench-enabled dev shell is entered once
- **THEN** the declared workflow artifacts are present and consistent while committed instruction files were already available from the clone

#### Scenario: workflow-only adoption remains minimal
- **WHEN** an existing repository enables only the Workbench workflow module
- **THEN** no language, service, process, container, or packaging option is forced by that adoption

## ADDED Requirements

### Requirement: Devenv profiles are independently composable
Each Workbench project profile SHALL be importable independently of workflow artifact bootstrap and independently of every other profile except documented base imports. Profile modules SHALL configure only their declared language/tool/hook concern and MUST NOT use force-priority overrides to empty unrelated Devenv options.

#### Scenario: Python profile without agent delivery
- **WHEN** a public Python repository imports the Python/uv profile without the workflow module
- **THEN** it receives the declared Python/uv tools and hooks without MCP, agent, knowledge, or Workmux artifacts

#### Scenario: polyglot profile preserves consumer processes
- **WHEN** finance composes the polyglot profile with its frontend/backend processes and PostgreSQL service
- **THEN** all consumer processes and services remain present in the evaluated shell

### Requirement: Shared checks compose from selected concerns
Workbench SHALL publish reusable Nix, Python, Rust, and generated-artifact check modules that follow the same profile boundaries. A repository SHALL be able to select or override checks without installing a second formatter or bypassing its own package/build verification.

#### Scenario: Python and Nix checks compose
- **WHEN** real-estate-search selects Python/uv and Nix project concerns
- **THEN** Ruff/uv and Statix/Deadnix/treefmt checks compose without duplicating formatter ownership
