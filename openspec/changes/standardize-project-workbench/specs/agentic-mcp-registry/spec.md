## ADDED Requirements

### Requirement: Workbench is the canonical registry namespace
The single MCP server registry SHALL be configured through `workbench.mcp`. During the compatibility window, `agentic.mcp` SHALL be a deprecated alias of the same module options and renderers. Adapters, secret resolution, agent validation, user/project tiering, and harness outputs MUST consume the canonical evaluated registry exactly once.

#### Scenario: legacy and canonical imports render the same servers
- **WHEN** equivalent fixtures configure the registry through `workbench.mcp` and through the deprecated `agentic.mcp` alias
- **THEN** their effective server sets and generated Claude, OpenCode, Codex, and user-tier artifacts are identical

#### Scenario: alias does not create a second definition plane
- **WHEN** a server is contributed through one namespace and referenced by an agent through the other compatibility surface
- **THEN** validation resolves the one server definition and it is rendered once

### Requirement: Project mechanics reuse the existing delivery authority
Workbench project profiles and repository traits SHALL consume the existing MCP registry and managed-file adapters. A profile, archetype, or private environment layer MUST NOT define a parallel MCP schema or directly hand-render a harness file.

#### Scenario: infrastructure profile adds no renderer
- **WHEN** a Terraform or Kubernetes repository imports an infrastructure-oriented Workbench profile
- **THEN** its enabled MCP capabilities are selected from the canonical registry and delivered by the existing adapters
