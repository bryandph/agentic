Serena is the project's **memory holder** — plain markdown under
`.serena/memories/`, MCP-served to every harness.

- Activate the project before any other serena call; then list
  memories and read the ones relevant to your task — `feedback/*` and
  `style/*` names encode load-bearing operator preferences.
- In Pi, discover with `mcp({search: "serena activate_project"})`,
  describe the returned tool with `mcp({describe: "<tool>"})`, then
  call `mcp({tool: "<tool>", args: {project: "<absolute cwd>"}})`.
  After activation, discover/list the memory and symbolic tools through
  `mcp({server: "serena"})`. If metadata is absent, first connect with
  `mcp({connect: "serena"})`; connection is not a Serena tool call.
- Write what cannot be derived: decisions + rationale, gotchas, findings
  with evidence. Store **pointers, not snapshots** via `write_memory`:
  link `mem:` refs, file paths or AGENTS.md sections. Never snapshot
  AGENTS.md, command lists, generated knowledge or repo overviews into
  memories — those copies drift; point to the source instead.
- TODOs belong in the issue tracker, active designs in the spec system,
  session narratives nowhere — a memory is for what a stranger needs a
  year from now.
- The `knowledge/` namespace is **generated and read-only** (rendered
  from the declared fragment registry) — never write there; your
  writable namespaces are other subdirectories. Move root memories with
  `rename_memory` so `mem:` references stay valid. Cross-reference memories
  with `mem:`-prefixed links; `serena memories check` gates reference
  integrity in CI.
- Retrieval: names/grep first; use a knowledge-search tool, when the
  environment provides one, for concept-level recall over the corpus.
- Prefer symbolic tools (`get_symbols_overview`, `find_symbol`) over
  whole-file reads when serena runs with language servers.

Deeper sources: https://github.com/oraios/serena (memories docs).
