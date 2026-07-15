# Harness coverage

The registry targets four harnesses. Three consume MCP natively; Pi does
not — its delivery path is documented here (agentic-mcp-registry spec,
"Harness coverage including MCP-less harnesses").

| Harness | MCP delivery | Channel |
|---|---|---|
| **Claude Code** | native | project tier: `.mcp.json` (mcp-servers-nix claude-code flavor, symlinked by the devenv bootstrap); user tier: home-manager `programs.mcp` + `programs.claude-code.enableMcpIntegration` |
| **OpenCode** | native | project tier: opencode config (mcp-servers-nix opencode flavor); user tier: `programs.mcp` + `programs.opencode.enableMcpIntegration` |
| **Codex** | native, **user-tier only** | Codex reads MCP servers from its user-level TOML (`~/.codex/config.toml`, `mcp_servers` key). Delivery is the home-manager plane: `programs.mcp` + `programs.codex.enableMcpIntegration` (upstream ships the integration). There is no project-tier codex file — do not invent one. |
| **Pi** | **none in core** | see below |

## Pi

Pi has no core MCP support; MCP arrives via extensions/adapters. Two
sanctioned paths, in preference order:

1. **CLI equivalents** — servers whose *function* an agent may need on
   every harness declare `cliEquivalent` in their registry definition
   (knowledge/semantic search at minimum; fleet tooling like a fleet CLI
   naturally qualifies since its MCP server is porcelain over the same
   binary). The devenv bootstrap puts those CLIs on PATH, so a Pi agent
   invokes the documented command instead of an MCP tool. Collected at
   eval time via `agentic.mcp.lib.cliEquivalents` and surfaced in
   generated instructions (`AGENTS.md`), which Pi does read.
2. **pi-mcp-adapter / extension** — where a true MCP client is required,
   run the community adapter as a Pi extension against the same rendered
   project config. This is per-user setup, not rendered by core; treat
   it as an escape hatch, not the default.

Design consequence enforced by the schema: a registry entry that only
exists as MCP (`cliEquivalent = null`) is understood to be unreachable
from Pi. That is acceptable for harness-specific conveniences, never for
knowledge access.
