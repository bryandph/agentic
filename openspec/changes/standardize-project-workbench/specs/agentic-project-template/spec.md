## MODIFIED Requirements

### Requirement: Workflow-complete scaffold
Workbench SHALL ship a flake template that scaffolds a new repository with a `flake.nix` consuming Workbench core and optionally an environment layer, Devenv wiring, `.envrc`, the Workbench workflow module, and an OpenSpec scaffold. Entering the scaffolded repository's shell once SHALL yield a workflow-complete project under the Workbench Devenv contract.

#### Scenario: template to working shell
- **WHEN** `nix flake init` is run with the Workbench template and the dev shell is entered
- **THEN** declared MCP configuration, agent directories, committed instructions, and Workmux configuration exist and the template's evaluation check passes

### Requirement: Archetype variants for packaging projects
Workbench SHALL offer archetype variants for software-packaging projects—at minimum Rust, Python/uv, polyglot, and embedded—by composing org-neutral profile modules with the workflow module. An archetype MUST NOT own the project's package construction: uv2nix, Rust overlays, OCI images, application services, and CI remain repository-owned and compose alongside it.

#### Scenario: Python packaging repository scaffolds with its toolchain
- **WHEN** the Python/uv variant is instantiated and the shell entered
- **THEN** the shell provides the shared Python/uv profile and selected workflow artifacts while repository-owned build configuration remains independent of regeneration

#### Scenario: stateful polyglot repository can extend the variant
- **WHEN** a repository based on the polyglot variant adds stateful services and project processes
- **THEN** those declarations compose without being forced off or absorbed into the template

### Requirement: Workflow-only adoption of existing repos
Workbench SHALL provide an adoption mode for existing repositories, including repositories with no flake: it adds a minimal flake and `.envrc` whose dev shell delivers only selected Workbench workflow mechanics while leaving the existing build workflow unchanged for collaborators who never enter the shell. Devenv-native adoption without a flake may be documented as an opt-in, never the default.

#### Scenario: non-flake embedded repository adopts the workflow
- **WHEN** workflow-only adoption is applied to a Cargo/probe-rs workspace with no prior Nix environment
- **THEN** declared workflow artifacts become available and building/flashing outside the shell behaves as before

### Requirement: Template carries no environment identity
Workbench templates SHALL reference environment-layer values only as explicit selectable inputs/placeholders. Instantiating a template MUST NOT embed environment endpoints, secret mounts, hostnames, model endpoints, or organization knowledge unless a private environment capsule is deliberately selected.

#### Scenario: org-neutral instantiation
- **WHEN** a template is instantiated without an environment layer
- **THEN** the result evaluates using public inputs and contains no environment-specific values

## ADDED Requirements

### Requirement: Existing Agentic template names migrate compatibly
Canonical template names and generated documentation SHALL use Workbench. Deprecated Agentic template aliases MAY remain during the compatibility window, but they SHALL instantiate the same canonical template sources and MUST NOT fork scaffold content.

#### Scenario: legacy template alias is byte-equivalent
- **WHEN** the canonical Workbench template and its deprecated Agentic alias are instantiated at the same revision
- **THEN** their generated repository content is byte-identical except for invocation metadata that explicitly records the selected alias
