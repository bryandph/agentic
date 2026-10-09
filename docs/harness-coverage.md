# Harness coverage

One MCP registry supplies four harnesses through shared artifacts.

| Harness | MCP delivery |
|---|---|
| Claude Code | Project `.mcp.json`; user `programs.mcp` with native HM integration |
| OpenCode | Project OpenCode config; user `programs.mcp` with native HM integration |
| Codex | Project Codex TOML and user `programs.mcp` with native HM integration |
| Pi | Built-in MCP client; writable user `~/.pi/agent/mcp.json` reconciliation and trusted project `.pi/mcp.json` |

Pi's native paths, ownership contract, temporary adapter compatibility, and
validation commands are in [Pi delivery](pi.md). There is no extra server
registry or Pi-specific server schema. CLI equivalents remain useful alongside
MCP and appear in generated instructions.

Specialists use one compiled registry body. Claude Code and OpenCode have native
agent projections; Pi receives ordinary `/role-<name>` prompt templates for the
current session. Workmux owns worker orchestration.
