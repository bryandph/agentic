# agentic-project-template Specification

## Purpose
Flake templates scaffolding workflow-complete repos with archetype variants (rust, python/uv, polyglot, embedded) and a workflow-only adoption mode for existing repos, carrying no environment identity.
## Requirements
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

### Requirement: Archetype variants for packaging projects
The template SHALL offer archetype variants for software-packaging
projects — at minimum rust, python/uv, polyglot, and embedded — composing
core's org-neutral language profile modules with the agentic devenv
module. A variant SHALL NOT own the project's packaging: build wiring
(uv2nix, rust-overlay, OCI images, CI) remains the repo's own, composed
alongside.

#### Scenario: python packaging repo scaffolds with its toolchain
- **WHEN** the python/uv variant is instantiated and the shell entered
- **THEN** the shell provides the python/uv profile plus the agentic
  workflow artifacts, and the repo's own build config is untouched by
  regeneration

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

### Requirement: Template carries no environment identity
The template SHALL reference env-layer values only as placeholders/options
to fill; instantiating it MUST NOT embed environment-specific endpoints unless the
user selects an env layer.

#### Scenario: org-neutral instantiation
- **WHEN** the template is instantiated without an env layer
- **THEN** the result evaluates and contains no environment-specific values

### Requirement: Environment CI cache profile integration
When a private environment layer is selected, packaging-project templates SHALL expose reusable CI cache-profile integration for supported active ecosystems while leaving each repository in control of its pipeline. Org-neutral template instantiation MUST NOT contain environment endpoints, credentials, or mandatory CI configuration.

#### Scenario: environment Rust template opts into CI caching
- **WHEN** a Rust project is instantiated or adopted with the private environment layer and enables the Rust CI cache profile
- **THEN** it receives the reusable sccache/RustFS contract and required cache-key inputs without copying another repository's workflow

#### Scenario: Org-neutral template is instantiated
- **WHEN** the same template is instantiated without the private environment layer
- **THEN** it evaluates without environment cache endpoints or credentials
- **AND** its existing external build workflow remains unchanged
