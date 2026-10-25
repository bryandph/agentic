## MODIFIED Requirements

### Requirement: Knowledge fragments as bounded convention cards
`workbench.knowledge.<topic>` SHALL define reusable markdown fragments. Fragments MUST be size-bounded by a module assertion and SHALL point to deeper sources rather than inline exhaustive detail. Deeper-source references MUST be visible to every consumer of the fragment's layer: core fragments MUST NOT reference repository-local artifacts, but may reference memories that core renders into every consumer; environment and repository fragments may reference sources in their own layer. Workbench core ships org-neutral fragments, and environment/repository layers contribute additional fragments through the same module schema. During migration, `agentic.knowledge` SHALL alias this one registry.

#### Scenario: oversized fragment is rejected
- **WHEN** a fragment exceeds the configured size bound
- **THEN** evaluation fails with a message naming the fragment and the bound

#### Scenario: fragments merge across layers
- **WHEN** Workbench defines a portable subject fragment and the private environment layer defines a repository fragment
- **THEN** both are available to agent composition without copying the environment fragment into public core

#### Scenario: legacy namespace shares one registry
- **WHEN** one layer contributes through the deprecated `agentic.knowledge` alias and another uses `workbench.knowledge`
- **THEN** both contributions merge in one canonical registry and render once

### Requirement: Agents composed from fragments and structured scope
`workbench.agents.<name>` SHALL declare description, ordered knowledge-fragment references, structured scope, a platform-agnostic capability set, and required MCP servers. Definitions may carry per-platform overrides where the common capability model is insufficient. Agent bodies SHALL be compiled from these fields; hand-written monolithic bodies are not part of the schema. During migration, `agentic.agents` SHALL alias this one registry.

#### Scenario: scope renders uniformly
- **WHEN** two agents declare the same forbidden path through structured scope
- **THEN** their rendered platforms contain the same generated scope language

#### Scenario: unknown fragment reference fails
- **WHEN** an agent references a knowledge fragment that no layer defines
- **THEN** evaluation fails naming the agent and missing fragment

#### Scenario: canonical and legacy definitions cannot diverge
- **WHEN** a consumer attempts to give the same agent incompatible values through canonical and deprecated names
- **THEN** normal module conflict reporting fails evaluation instead of silently selecting one definition

## ADDED Requirements

### Requirement: Skills share the layered Workbench registry
Reusable skills and their platform projections SHALL follow the same Workbench core/environment/repository placement rule as agents and knowledge. Public core skills MUST be organization-neutral; the private environment layer may add environment skills; a repository may add domain skills. Generated skill artifacts SHALL derive from one registry and retain their existing drift/ownership checks.

#### Scenario: repository skill remains local
- **WHEN** finance declares a finance-domain skill while importing core and environment skills
- **THEN** all selected skills render for finance but the finance skill is absent from public Workbench and unrelated repositories
