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

      claude.extraTools = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Per-platform override: extra Claude tool grants on top of the derived set.";
      };

      opencode = {
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
    description: ${agent.description}
    tools: ${lib.concatStringsSep ", " (lib.unique (claudeTools agent))}
    ---

    ${compileBody name agent}'';

  renderOpencode = name: agent: ''
    ---
    description: ${agent.description}
    mode: ${agent.opencode.mode}
    permission: ${builtins.toJSON (opencodePermission agent)}
    ---

    ${compileBody name agent}'';

  agentsDir = render: farmName: pkgs:
    pkgs.linkFarm farmName (
      lib.mapAttrsToList (n: agent: {
        name = "${n}.md";
        path = pkgs.writeText "${n}.md" (render n agent);
      })
      cfg.agents
    );
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
        helpers `claudeTools` / `opencodePermission`.
      '';
    };
  };

  config.agentic.agentsLib = {
    inherit renderClaude renderOpencode claudeTools opencodePermission;
    claudeAgentsDir = agentsDir renderClaude "claude-agents";
    opencodeAgentsDir = agentsDir renderOpencode "opencode-agents";
  };
}
