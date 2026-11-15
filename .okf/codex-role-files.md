---
type: Gotcha
title: Codex role files and permission limits
description: Codex role TOMLs must be regular files; parsed role fields do not override runtime permissions.
tags: [codex, agents]
status: draft
generated: { by: worker-agentic-okf-codex-roles-1/gpt-6.1-sol, at: 2026-11-15T05:34:24Z }
sources:
  - id: codex-role
    resource: https://github.com/openai/codex/blob/rust-v0.157.0/codex-rs/core/src/agent/role.rs
  - id: codex-regular-file
    resource: https://github.com/openai/codex/blob/rust-v0.157.0/codex-rs/exec-server/src/regular_file.rs
  - id: role-rendering
    resource: ../modules/registry/_agents.nix
  - id: registry-check
    resource: ../modules/checks/agents.nix
  - id: role-projections
    resource: ../README.md#agent-role-projections
---

# Role files must be regular files

At Codex `rust-v0.157.0`, the version provided by agentic's `llm-agents`
pin, discovery accepts symlinked role files, but spawning reads them with
`read_sensitive_file_to_string`. On Unix it opens with
`O_NONBLOCK | O_NOFOLLOW` and rejects non-regular files. A symlink as the
final path component fails with `ELOOP` or "not a regular file". Codex
reports only "agent type is currently not available" and logs
`failed to apply role to config` at warn level.[^codex-role][^codex-regular-file]

The `.codex/agents` directory may itself be a symlink, but each
`<name>.toml` must be a regular file. A `pkgs.linkFarm` passes discovery
and fails at launch. Agentic's `codexAgentsDir` copies regular files in
[`modules/registry/_agents.nix`](../modules/registry/_agents.nix), lines
495–505. The `agents-registry` check opens every rendered TOML with
`O_NOFOLLOW` in [`modules/checks/agents.nix`](../modules/checks/agents.nix),
lines 418–424.[^role-rendering][^registry-check]

# Parsed fields are not permission overrides

A parsed role config is not a permission boundary. Codex applies only
`developer_instructions`, `model`, `model_reasoning_effort`,
`model_reasoning_summary`, `model_verbosity`, `personality` and
`service_tier`, plus disabling (never enabling) `shell_tool`, `apps`,
`plugins`, `memory_tool` and `request_permissions_tool`, and disabling
skills. Sandbox mode, approval policy and MCP configuration are not role
overrides: a native subagent inherits its parent's sandbox. Agentic's
rendered role capabilities are instructions, not enforcement, as described
in README's [Agent role projections](../README.md#agent-role-projections).[^codex-role][^role-projections]

Re-check `role.rs` in the installed Codex version before extending
permission projections. For launch failures, look only for the
`failed to apply role to config` warning in Codex's logs; do not dump
transcripts or credential-bearing logs.

This concept supersedes a retired environment-repository Serena memory.

[^codex-role]: Codex `rust-v0.157.0`, `role.rs`, lines 34–67, 80–118 and 143.
[^codex-regular-file]: Codex `rust-v0.157.0`, `regular_file.rs`, lines 20–42.
[^role-rendering]: Agentic's regular-file Codex role rendering.
[^registry-check]: Agentic's launch-compatible role-file check.
[^role-projections]: Agentic's native role projection limits.
