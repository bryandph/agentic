# Agent registry (design D5, agentic-agents spec).
#
# `agentic.agents.<name>` = description + ordered knowledge fragments +
# structured scope + platform-agnostic capabilities + MCP requirements.
# Bodies are COMPILED from these fields — hand-written monolithic bodies
# are not part of the schema. The capability set {edit, exec, web} is
# the default derivation of platform grants; per-platform override
# fields augment/win where the capability vocabulary is too coarse
# (real agents need finer grants — task-tracking tools, specific
# mcp__* namespaces).
#
# Renderers (replaces nixspace modules/mcp/agent-module.nix):
#   * Claude Code subagent markdown — `tools:` frontmatter derived from
#     capabilities + mcp + claude.extraTools.
#   * OpenCode subagent markdown — V1-SUBSET DECISION (recorded per
#     design D5): we emit the stable V1 frontmatter (`permission:` key,
#     files under `.opencode/agents/`) because the fleet's pinned
#     opencode consumes V1 and upstream auto-translates V1 -> V2
#     (`permissions`) internally. Revisit when the fleet's opencode
#     moves to a V2-only release.
#
# Adding a platform = adding a renderer here, never editing agent
# definitions.
{
  lib,
  config,
  ...
}: let
  cfg = config.agentic;

  agentType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        description = "One-line agent description (drives delegation).";
      };

      fragments = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Ordered knowledge fragment references (keys of agentic.knowledge; unknown references fail eval).";
      };

      scope = {
        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Path globs the agent operates within.";
        };
        forbidden = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Path globs the agent must never read, edit, or act on.";
        };
        delegateTo = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Agent names to hand off to when a task crosses out of scope.";
        };
      };

      capabilities = {
        edit = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "May modify files (Claude: Edit/Write; OpenCode: edit permission).";
        };
        exec = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "May run commands (Claude: Bash; OpenCode: bash permission).";
        };
        web = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "May reach the web (Claude: WebFetch/WebSearch; OpenCode: webfetch permission).";
        };
      };

      mcp = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Required MCP servers (validated against the registry; external entries warn).";
      };

      claude = {
        extraTools = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Per-platform override: extra Claude tool grants on top of the derived set.";
        };
        model = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Claude model alias or ID; null preserves harness model selection.";
        };
        maxTurns = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          description = "Native Claude subagent turn limit; null preserves the harness default.";
        };
      };

      codex = {
        model = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Codex model ID; null preserves harness model selection.";
        };
        reasoningEffort = lib.mkOption {
          type = lib.types.nullOr (lib.types.enum ["minimal" "low" "medium" "high" "xhigh" "max" "ultra"]);
          default = null;
          description = "Native reasoning effort; choose a value supported by the selected model.";
        };
      };

      opencode = {
        model = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "OpenCode provider/model ID; null preserves harness model selection.";
        };
        mode = lib.mkOption {
          type = lib.types.str;
          default = "subagent";
          description = "OpenCode mode (subagent | primary | all).";
        };
        permission = lib.mkOption {
          type = lib.types.attrs;
          default = {};
          description = "Per-platform override: OpenCode permission entries merged over (winning against) the derived map.";
        };
      };
    };
  };

  # --- compiled body (shared across platforms) ---------------------

  scopeSection = agent:
    lib.optionalString (agent.scope.paths != [] || agent.scope.forbidden != [] || agent.scope.delegateTo != []) ''

      ## Scope

      ${lib.optionalString (agent.scope.paths != []) "Operate only within: ${lib.concatStringsSep ", " (map (p: "`${p}`") agent.scope.paths)}.\n"}${lib.optionalString (agent.scope.forbidden != []) "Never read, modify, or act on: ${lib.concatStringsSep ", " (map (p: "`${p}`") agent.scope.forbidden)}.\n"}${lib.optionalString (agent.scope.delegateTo != []) "If a task crosses out of this scope, hand off to: ${lib.concatStringsSep ", " agent.scope.delegateTo}.\n"}'';

  knowledgeSection = agent:
    lib.optionalString (agent.fragments != []) (
      lib.concatMapStrings (fname: let
        f = cfg.knowledgeLib.fragment fname;
      in ''

        ## ${f.title}

        ${f.text}
      '')
      agent.fragments
    );

  compileBody = name: agent: let
    validatedMcp = cfg.mcp.lib.validateAgentRefs name agent.mcp;
  in ''
    ${agent.description}
    ${scopeSection agent}${knowledgeSection agent}${lib.optionalString (validatedMcp != []) ''

      ## MCP servers

      Required for this role: ${lib.concatStringsSep ", " (map (s: "`${s}`") validatedMcp)}.
    ''}'';

  # --- platform grant derivation ------------------------------------

  claudeTools = agent:
    ["Read" "Glob" "Grep"]
    ++ lib.optionals agent.capabilities.edit ["Edit" "Write"]
    ++ lib.optionals agent.capabilities.exec ["Bash"]
    ++ lib.optionals agent.capabilities.web ["WebFetch" "WebSearch"]
    ++ map (s: "mcp__${s}") agent.mcp
    ++ agent.claude.extraTools;

  opencodePermission = agent:
    {
      edit =
        if agent.capabilities.edit
        then "allow"
        else "deny";
      bash =
        if agent.capabilities.exec
        then "allow"
        else "deny";
      webfetch =
        if agent.capabilities.web
        then "allow"
        else "deny";
    }
    // agent.opencode.permission;

  # --- renderers ----------------------------------------------------

  renderClaude = name: agent: ''
    ---
    name: ${name}
    description: ${builtins.toJSON agent.description}
    tools: ${lib.concatStringsSep ", " (lib.unique (claudeTools agent))}
    ${lib.optionalString (agent.claude.model != null) "model: ${builtins.toJSON agent.claude.model}\n"}${lib.optionalString (agent.claude.maxTurns != null) "maxTurns: ${toString agent.claude.maxTurns}\n"}---

    ${compileBody name agent}'';

  renderOpencode = name: agent: ''
    ---
    description: ${builtins.toJSON agent.description}
    mode: ${agent.opencode.mode}
    permission: ${builtins.toJSON (opencodePermission agent)}
    ${lib.optionalString (agent.opencode.model != null) "model: ${builtins.toJSON agent.opencode.model}\n"}---

    ${compileBody name agent}'';

  # JSON strings are valid TOML basic strings. Keep model/authentication
  # routing separate: a role never chooses credentials or a provider.
  renderCodex = name: agent: ''
    name = ${builtins.toJSON name}
    description = ${builtins.toJSON agent.description}
    developer_instructions = ${builtins.toJSON (compileBody name agent)}
    ${lib.optionalString (agent.codex.model != null) "model = ${builtins.toJSON agent.codex.model}\n"}${lib.optionalString (agent.codex.reasoningEffort != null) "model_reasoning_effort = ${builtins.toJSON agent.codex.reasoningEffort}\n"}
  '';

  renderPi = name: agent: ''
    ---
    description: ${builtins.toJSON agent.description}
    ---

    Adopt the `${name}` specialist role for this task. This is a prompt
    in the current Pi session; workmux owns separate worker orchestration.
    Scope and capability limits below are instructions, not a sandbox.

    ${compileBody name agent}

    ## Capabilities

    File edits: ${
      if agent.capabilities.edit
      then "permitted"
      else "not permitted"
    }.
    Shell commands: ${
      if agent.capabilities.exec
      then "permitted"
      else "not permitted"
    }.
    Web access: ${
      if agent.capabilities.web
      then "permitted"
      else "not permitted"
    }.

    For required MCP servers, use `mcp` search, describe, then call the
    discovered tool. Activate Serena for the current project before other
    Serena calls. Do not infer authorization from a tool being available.

    Task: $ARGUMENTS
  '';

  piPackage = pkgs:
    pkgs.linkFarm "pi-agent-roles" (
      [
        {
          name = "package.json";
          path = pkgs.writeText "package.json" (builtins.toJSON {
            name = "agentic-roles";
            pi.prompts = ["./prompts"];
          });
        }
      ]
      ++ lib.mapAttrsToList (name: agent: {
        name = "prompts/role-${name}.md";
        path = pkgs.writeText "role-${name}.md" (renderPi name agent);
      })
      cfg.agents
    );

  agentsDir = render: extension: farmName: pkgs:
    pkgs.linkFarm farmName (
      lib.mapAttrsToList (n: agent: {
        name = "${n}.${extension}";
        path = pkgs.writeText "${n}.${extension}" (render n agent);
      })
      cfg.agents
    );

  # Codex discovers symlinked files but opens role files with O_NOFOLLOW
  # when spawning. The directory may be a symlink; its TOML entries must
  # be regular files. A linkFarm therefore passes discovery but fails launch.
  codexAgentsDir = pkgs:
    pkgs.runCommand "codex-agents" {} ''
      mkdir -p "$out"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: agent: ''
          cp ${pkgs.writeText "${name}.toml" (renderCodex name agent)} "$out"/${lib.escapeShellArg "${name}.toml"}
        '')
        cfg.agents)}
    '';

  # Check every destination before changing any of them. Never nest a
  # generated farm inside a user's real, nonempty agents directory.
  placeScript = pkgs: ''
    for agentic_dir in .claude/agents .codex/agents .opencode/agents; do
      if [ -e "$agentic_dir" ] && [ ! -L "$agentic_dir" ]; then
        if [ ! -d "$agentic_dir" ] || [ -n "$(ls -A "$agentic_dir")" ]; then
          echo "agentic: refusing to replace unmanaged $agentic_dir; move its definitions into the Nix registry first" >&2
          exit 1
        fi
      fi
    done
    mkdir -p .claude .codex .opencode
    for agentic_dir in .claude/agents .codex/agents .opencode/agents; do
      if [ -d "$agentic_dir" ] && [ ! -L "$agentic_dir" ]; then
        rmdir "$agentic_dir"
      fi
    done
    ln -sfn ${agentsDir renderClaude "md" "claude-agents" pkgs} .claude/agents
    ln -sfn ${codexAgentsDir pkgs} .codex/agents
    ln -sfn ${agentsDir renderOpencode "md" "opencode-agents" pkgs} .opencode/agents
  '';
in {
  options.agentic = {
    agents = lib.mkOption {
      type = lib.types.attrsOf agentType;
      default = {};
      description = "Composed agent roles, merged across layers.";
    };

    agentsLib = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = ''
        Renderers: `renderClaude name agent`, `renderOpencode name
        agent` (markdown strings), `claudeAgentsDir pkgs` /
        `opencodeAgentsDir pkgs` (link farms for
        .claude/agents / .opencode/agents), and the derivation
        helpers `claudeTools` / `opencodePermission`. Codex: `renderCodex`,
        `codexAgentsDir pkgs` (standalone .codex/agents/*.toml roles).
        `placeScript pkgs` safely places project agent directories. Pi: `renderPi`,
        `piPackage pkgs` (local package of /role-<name> prompt templates),
        and `compileBody` (the shared body before platform framing).
      '';
    };
  };

  config.agentic.agentsLib = {
    inherit compileBody renderClaude renderCodex renderOpencode renderPi piPackage claudeTools opencodePermission placeScript codexAgentsDir;
    claudeAgentsDir = agentsDir renderClaude "md" "claude-agents";
    opencodeAgentsDir = agentsDir renderOpencode "md" "opencode-agents";
  };
}
