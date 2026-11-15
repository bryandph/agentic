Serena provides code navigation and **read-only reference memories** —
plain markdown under `.serena/memories/`, MCP-served to every harness.
Agents do not call `write_memory`, `edit_memory`, `delete_memory` or
`rename_memory`.

- Activate the project before any other serena call; then list
  memories and read the ones relevant to your task — `feedback/*` and
  `style/*` names encode load-bearing operator preferences.
- In Pi, discover with `mcp({search: "serena activate_project"})`,
  describe the returned tool with `mcp({describe: "<tool>"})`, then
  call `mcp({tool: "<tool>", args: {project: "<absolute cwd>"}})`.
  After activation, discover/list the memory and symbolic tools through
  `mcp({server: "serena"})`. If metadata is absent, first connect with
  `mcp({connect: "serena"})`; connection is not a Serena tool call.
- New durable repo knowledge — decisions and rationale, gotchas,
  procedures and findings with evidence — belongs in the repository's
  OKF bundle by pull request (see the memory skill). Keep **pointers,
  not snapshots**: link sources rather than copying AGENTS.md, command
  lists, generated knowledge or repo overviews. Cross-project guidance
  belongs in the organisation's maintained articles.
- TODOs belong in the issue tracker, behaviour contracts in OpenSpec,
  session narratives nowhere. Bundle concepts link to specifications
  rather than restating them.
- The `knowledge/` namespace is **generated and read-only** (rendered
  from the declared fragment registry). Existing memories outside it
  are read-only reference material; leave them untouched. Follow
  `mem:`-prefixed links when reading memories; `serena memories check`
  gates reference integrity in CI.
- Retrieval: names/grep first; use a knowledge-search tool, when the
  environment provides one, for concept-level recall over the corpus.
- Prefer symbolic tools (`get_symbols_overview`, `find_symbol`) over
  whole-file reads when serena runs with language servers.

Deeper sources: https://github.com/oraios/serena (memories docs).
