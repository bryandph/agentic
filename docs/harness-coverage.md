# Harness coverage

One MCP registry supplies four harnesses through shared artifacts.

| Harness | MCP delivery |
|---|---|
| Claude Code | Project `.mcp.json`; user `programs.mcp` with native HM integration |
| OpenCode | Project OpenCode config; user `programs.mcp` with native HM integration |
| Codex | Project Codex TOML and user `programs.mcp` with native HM integration |
| Pi | Pinned `pi-mcp-adapter` local package; shared project `.mcp.json` and user `~/.config/mcp/mcp.json`, with project trust gating |

Pi's package contract, trust behavior, dependency pin, and validation commands
are in [Pi delivery](pi.md). There is no extra server registry or Pi MCP flavor.
CLI equivalents remain useful alongside MCP and appear in generated instructions;
MCP-only servers are reachable through Pi's proxy.

Specialists use one compiled registry body. Claude Code and OpenCode have native
agent projections; Pi receives ordinary `/role-<name>` prompt templates for the
current session. Workmux owns worker orchestration.
