Serena is the project's **memory holder** — plain markdown under
`.serena/memories/`, MCP-served to every harness.

- Activate the project before any other serena call; then list
  memories and read the ones relevant to your task — `feedback/*` and
  `style/*` names encode load-bearing operator preferences.
- Write durable findings (decisions + rationale, gotchas, bring-up
  research) via `write_memory`. Store **pointers, not snapshots**: "run
  X / see file Y" survives; copied values drift into lies. Ask: "will
  this be false in 3 months?" — if yes, point at the source of truth.
- TODOs belong in the issue tracker, active designs in the spec system,
  session narratives nowhere — a memory is for what a stranger needs a
  year from now.
- The `knowledge/` namespace is **generated and read-only** (rendered
  from the declared fragment registry) — never write there; your
  writable namespaces are everything else. Cross-reference memories
  with `mem:`-prefixed links; `serena memories check` gates reference
  integrity in CI.
- Retrieval: names/grep first; use the knowledge semantic-search tool
  (`qmd`-based, MCP or CLI) for concept-level recall over the corpus.
- Prefer symbolic tools (`get_symbols_overview`, `find_symbol`) over
  whole-file reads when serena runs with language servers.

Deeper sources: https://github.com/oraios/serena (memories docs).
