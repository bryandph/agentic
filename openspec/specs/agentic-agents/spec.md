# agentic-agents Specification

## Purpose
Knowledge fragments composed into agent roles with a platform-agnostic capability model, rendered per platform (Claude/OpenCode subagents, generated committed AGENTS.md, CLAUDE.md shim), plus the serena knowledge memory plane with CI reference checking and semantic search.
## Requirements
### Requirement: Knowledge fragments as bounded convention cards
`agentic.knowledge.<topic>` SHALL define reusable markdown fragments.
Fragments MUST be size-bounded (enforced by module assertion) and SHALL
point to deeper sources (serena memories, specs, docs) rather than inline
exhaustive detail. Deeper-source references MUST be visible to every
consumer of the fragment's layer: core fragments MUST NOT reference
repo-local artifacts, but MAY reference serena memories that core itself
renders into every consumer (see the knowledge memory plane requirement);
env and repo fragments MAY reference their own layer's sources. Core
ships org-neutral subject fragments; env layers and repos contribute
their own, merged by the module system.

#### Scenario: oversized fragment rejected
- **WHEN** a fragment exceeds the configured size bound
- **THEN** evaluation fails with a message naming the fragment and the
  bound

#### Scenario: fragments merge across layers
- **WHEN** core defines `knowledge.pki` and an env layer defines
  `knowledge.repo-example`
- **THEN** both are available to agent composition in the consuming repo

### Requirement: Knowledge memory plane
Declared knowledge SHALL render into per-repo serena memories (core and
env fragments plus their deep-source documents), placed under a
generated namespace and marked immutable via serena's
`read_only_memory_patterns`; agent-written memories live in a separate
writable namespace and are never touched by generation. The serena
project configuration (`.serena/project.yml` — languages, read-only and
ignored memory patterns) SHALL be generated from module options. Memory
reference integrity (`serena memories check`) SHALL run in repo CI.
Retrieval SHALL be available beyond name-based listing: a semantic search
tool over the committed markdown, whose index is disposable and lives
outside the repo, exposed via MCP AND as a plain CLI (harnesses without
core MCP support, e.g. Pi, retain access).

#### Scenario: core deep-sources are portable
- **WHEN** a core fragment references a core-shipped memory and a new
  repo consumes core
- **THEN** the referenced memory exists in that repo's memory plane,
  read-only, after generation

#### Scenario: agent memories survive regeneration
- **WHEN** an agent has written memories in the writable namespace and
  knowledge generation re-runs
- **THEN** the agent-written memories are unchanged and only the
  generated namespace is updated

#### Scenario: semantic search reaches every harness
- **WHEN** an agent needs a concept-level query over the repo's knowledge
  (not a filename or exact string)
- **THEN** MCP-capable harnesses query the search server and Pi invokes
  the equivalent CLI, over the same committed markdown corpus

### Requirement: Agents composed from fragments and structured scope
`agentic.agents.<name>` SHALL declare: description, ordered knowledge
fragment references, structured scope (`paths`, `forbidden`,
`delegateTo`), a platform-agnostic capability set (at minimum edit, exec,
web), and required MCP servers. Definitions MAY additionally carry
per-platform override fields (e.g. extra Claude tool grants, OpenCode
permission entries); the capability set is the default derivation and
overrides win where present. Agent bodies SHALL be compiled from these
fields; hand-written monolithic bodies are not part of the schema. Every
declared agent SHALL include the shared MCP-first routing fragment and
SHALL receive GitHub and Gitea MCP grants. Agents SHALL additionally
receive the operational MCP servers required by their structured domain
scope without receiving unrelated operational servers.

#### Scenario: scope renders uniformly
- **WHEN** two agents declare `scope.forbidden = [ "secrets/" ]`
- **THEN** both rendered agents contain the same generated scope language
  derived from the structured field

#### Scenario: unknown fragment reference fails
- **WHEN** an agent references a knowledge fragment that no layer defines
- **THEN** evaluation fails naming the agent and the missing fragment

#### Scenario: forge access is universal
- **WHEN** any declared agent is rendered
- **THEN** its platform grants include both the GitHub and Gitea MCP servers

#### Scenario: operational access follows role scope
- **WHEN** an agent owns Kubernetes, Flux, Woodpecker, or Terraform/OpenTofu work
- **THEN** its grants include the matching operational MCP servers and omit unrelated operational servers

### Requirement: Platform renderers from one definition
The system SHALL render each agent to Claude subagent markdown and OpenCode
subagent markdown, deriving platform grants (Claude tools list incl.
`mcp__*` entries, OpenCode permission map) from the capability set and MCP
requirements, then applying any per-platform overrides. Adding a platform
SHALL mean adding a renderer, not editing agent definitions.

#### Scenario: capability drives platform grants
- **WHEN** an agent declares `exec = false`
- **THEN** the Claude rendering omits Bash from tools and the OpenCode
  rendering denies bash, with no per-platform configuration on the agent

#### Scenario: override augments derived grants
- **WHEN** an agent needs a grant the capability set cannot express (e.g.
  a specific Claude tool) and declares it in the per-platform override
- **THEN** that platform's rendering includes the override on top of the
  derived grants, and other platforms are unaffected

### Requirement: Generated, committed AGENTS.md with CLAUDE.md shim
The system SHALL generate a per-repo `AGENTS.md` from the repo's declared
fragment set, serving platforms without a subagent format. The root
fragment set MUST include the shared MCP-first routing contract. The file
SHALL be committed to the repo (not a shell-entry store symlink) so non-nix
consumers (forge web UIs, cloud agents, CI, collaborators without direnv)
see it; CI SHALL fail on drift between the committed file and the rendered
output. Because Claude Code does not read `AGENTS.md` natively, the system
SHALL also generate a committed `CLAUDE.md` shim importing it
(`@AGENTS.md`). Generated files SHALL carry a do-not-edit header directing
durable additions to fragments; agent memory writes MUST NOT be appended to
generated files. Migration MUST diff generated output against the
pre-existing hand-written file before the hand-written content is deleted.
Repos MAY declare directory-scoped fragment sets rendering nested
`AGENTS.md` files (nearest-file-wins per the standard); generation MUST
NOT touch hand-written nested `AGENTS.md` files outside declared scopes.

#### Scenario: AGENTS.md reflects registry
- **WHEN** a repo declares its fragment set and the renderer runs
- **THEN** `AGENTS.md` content is exactly the rendered projection of those
  fragments, and regenerating without changes is idempotent

#### Scenario: drift fails CI
- **WHEN** the committed `AGENTS.md` differs from the rendered projection
  (hand edit or stale regeneration)
- **THEN** the repo's CI check fails, naming the file and the regeneration
  command

#### Scenario: Claude Code loads the shared instructions
- **WHEN** Claude Code starts a session in a repo with the generated files
- **THEN** it loads `CLAUDE.md`, whose `@AGENTS.md` import pulls in the
  shared instruction content without duplicating it

#### Scenario: hand-written nested AGENTS.md survives generation
- **WHEN** a repo has a hand-written `AGENTS.md` in a subdirectory (e.g.
  an embedded repo's `bsp/AGENTS.md`) outside any declared fragment scope
- **THEN** regenerating the root `AGENTS.md` leaves the nested file
  byte-identical

#### Scenario: main sessions receive the MCP-first contract
- **WHEN** a main assistant session loads the generated root instructions
- **THEN** it receives the same MCP-first default and fallback contract used by declared agents
