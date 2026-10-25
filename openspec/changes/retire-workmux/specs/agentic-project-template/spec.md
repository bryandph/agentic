## MODIFIED Requirements

### Requirement: Workflow-complete scaffold
Core SHALL ship a flake template that scaffolds a new repo with a `flake.nix`
consuming core and optionally an environment layer, Devenv wiring, `.envrc`,
the agentic Devenv module and an OpenSpec scaffold. Entering the shell once
SHALL yield a workflow-complete project under `agentic-devenv`. The scaffold
MUST NOT require Workmux or promise a generated `.workmux.yaml` after retirement.

#### Scenario: template to working shell
- **WHEN** `nix flake init` is run with the template and the dev shell is entered
- **THEN** MCP config, agent directories and committed `AGENTS.md` are available and the template's evaluation check passes
- **AND** the workflow works without Workmux or its generated configuration

### Requirement: Workflow-only adoption of existing repos
The template SHALL provide an adoption mode for existing repos, including
repos with no flake, such as an embedded Cargo workspace. It SHALL add a minimal
`flake.nix` and `.envrc` whose dev shell delivers only the agentic workflow
artifacts. The flake SHALL touch only the dev shell and keep the common flake
contract for pinning, CI and layering. Devenv-native adoption without a flake
MAY be documented as an opt-in, never the default. The repo's existing build
workflow MUST keep working for collaborators who never enter the shell.
Adoption MUST NOT add a Workmux dependency after retirement.

#### Scenario: non-flake embedded repo adopts the workflow
- **WHEN** adoption mode is applied to a Cargo/probe-rs workspace with no prior Nix environment and the shell is entered once
- **THEN** MCP config and agent directories are present without a generated Workmux configuration
- **AND** building and flashing with Cargo outside the shell behave as before adoption
