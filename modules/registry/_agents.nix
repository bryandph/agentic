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
#   * Cotal persona markdown (`.cotal/agents/<name>.md`) — mesh identity
#     in the frontmatter (role, channel ACLs, connector pin), the shared
#     body as the persona. Opt-in per agent through `platforms`, because
#     a mesh persona is rarely also a harness subagent.
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

      platforms = lib.mkOption {
        type = lib.types.listOf (lib.types.enum ["claude" "codex" "opencode" "pi" "cotal"]);
        default = ["claude" "codex" "opencode" "pi"];
        description = "Platforms this agent is rendered for. `cotal` is opt-in and needs `cotal.role`.";
      };

      cotal = {
        role = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Cotal role: the presence label and anycast address (one `[A-Za-z0-9_-]` token). Required when `platforms` lists `cotal`.";
        };
        agent = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Cotal connector pin (`pi`, `claude`, ...); null lets the launcher choose.";
        };
        model = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Model override handed to the connector; null preserves harness model selection.";
        };
        tags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Capability tags on the presence card.";
        };
        subscribe = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Channels joined at boot. Empty joins none.";
        };
        allowSubscribe = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Read ACL (wildcards such as `team.>` allowed). Empty means the same as `subscribe`.";
        };
        allowPublish = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Post ACL. Empty denies posting everywhere.";
        };
      };
    };
  };

  forPlatform = platform: lib.filterAttrs (_: agent: lib.elem platform agent.platforms) cfg.agents;

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

  # Cotal reads the frontmatter as YAML; JSON scalars and lists are valid
  # YAML, so every operator-supplied string goes through toJSON. `name`
  # is also the file name the launcher resolves, so they must agree. The
  # body is appended to the agent's system prompt, so it is the bare
  # fragment text: no description line and no section headers.
  cotalBody = agent:
    lib.concatStringsSep "\n" (map (fname: (cfg.knowledgeLib.fragment fname).text) agent.fragments);
  renderCotal = name: agent: let
    c = agent.cotal;
  in
    assert lib.assertMsg (c.role != null) "agentic.agents.${name}: platforms lists cotal but cotal.role is unset";
    assert lib.assertMsg (builtins.match "[A-Za-z0-9_-]+" name != null) "agentic.agents.${name}: a Cotal persona name must be one [A-Za-z0-9_-] token"; ''
      ---
      name: ${name}
      role: ${builtins.toJSON c.role}
      description: ${builtins.toJSON agent.description}
      tags: ${builtins.toJSON c.tags}
      ${lib.optionalString (c.agent != null) "agent: ${builtins.toJSON c.agent}\n"}${lib.optionalString (c.model != null) "model: ${builtins.toJSON c.model}\n"}subscribe: ${builtins.toJSON c.subscribe}
      allowSubscribe: ${builtins.toJSON c.allowSubscribe}
      allowPublish: ${builtins.toJSON c.allowPublish}
      ---

      ${cotalBody agent}'';

  cotalAgentsDir = pkgs:
    pkgs.linkFarm "cotal-personas" (
      lib.mapAttrsToList (name: agent: {
        name = "${name}.md";
        path = pkgs.writeText "${name}.md" (renderCotal name agent);
      })
      (forPlatform "cotal")
    );

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
      (forPlatform "pi")
    );

  agentsDir = platform: render: extension: farmName: pkgs:
    pkgs.linkFarm farmName (
      lib.mapAttrsToList (n: agent: {
        name = "${n}.${extension}";
        path = pkgs.writeText "${n}.${extension}" (render n agent);
      })
      (forPlatform platform)
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
        (forPlatform "codex"))}
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
    # Relink only on change: agent sandboxes (Codex) may forbid writes
    # under .codex/ even when the link is already current.
    agentic_link() { [ "$(readlink "$2" 2>/dev/null)" = "$1" ] || ln -sfn "$1" "$2"; }
    agentic_link ${agentsDir "claude" renderClaude "md" "claude-agents" pkgs} .claude/agents
    agentic_link ${codexAgentsDir pkgs} .codex/agents
    agentic_link ${agentsDir "opencode" renderOpencode "md" "opencode-agents" pkgs} .opencode/agents
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
        `piPackage pkgs` (local package of /role-<name> prompt templates).
        Cotal: `renderCotal`, `cotalAgentsDir pkgs` (link farm of
        `.cotal/agents/<name>.md` personas for agents whose `platforms`
        list `cotal`). `compileBody` is the shared body before platform framing.
      '';
    };
  };

  config.agentic.agentsLib = {
    inherit compileBody renderClaude renderCodex renderOpencode renderPi renderCotal piPackage cotalAgentsDir claudeTools opencodePermission placeScript codexAgentsDir;
    claudeAgentsDir = agentsDir "claude" renderClaude "md" "claude-agents";
    opencodeAgentsDir = agentsDir "opencode" renderOpencode "md" "opencode-agents";
  };
}
