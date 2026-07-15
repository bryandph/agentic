# Project shell bootstrap (design D6/D9, agentic-devenv spec).
#
# The devenv module places the per-repo workflow artifacts on shell
# entry, idempotently: `.mcp.json` + opencode config (rendered by
# upstream mcp-servers-nix lib from the project-tier registry), agent
# directories (.claude/agents, .opencode/agents link farms), the
# generated `.serena/project.yml` + read-only memory namespace, and the
# http-secret exports from the selected backend. `AGENTS.md`/`CLAUDE.md`
# are committed artifacts (modules/instructions.nix), never shell-entry
# placements. `.workmux.yaml` generation joins in task 4.2.
#
# cwd-safety: the bootstrap makes NO `.git` assumptions at all — no
# gitdir probing, no `.git`-is-a-directory checks; it only writes
# workspace-relative paths, so gitlink files and `__worktrees`
# indirection cannot break it. (The known worktree failure mode lives
# in devenv/direnv initialization BEFORE enterShell — handled by the
# out-of-shell detect-and-degrade path, task 4.3.)
#
# Division of labor vs devenv's first-party `claude.code.*`: that
# integration generates .claude/settings.json (permissions/hooks) and
# its own .mcp.json from devenv-level options. The registry is the
# single MCP source of truth here, so .mcp.json comes from the
# registry render; consumers remain free to use `claude.code.hooks`
# etc. alongside (the WorktreeCreate hook wiring in 4.2 goes through
# it). We deliberately do not reimplement anything it provides.
{inputs, ...}: {
  flake.modules.flake.agentic = {
    lib,
    config,
    ...
  }: let
    acfg = config.agentic;
    mcpLib = import "${inputs.mcp-servers-nix}/lib";

    projectConfigFor = pkgs: flavor:
      (mcpLib.evalModule pkgs {
        inherit flavor;
        settings.servers = acfg.mcp.lib.renderTier pkgs "project";
      })
      .config
      .configFile;

    bootstrapScript = pkgs: ''
      # agentic bootstrap — idempotent; re-entry changes nothing when
      # inputs are unchanged.
      ln -sf ${projectConfigFor pkgs "claude-code"} .mcp.json
      ln -sf ${projectConfigFor pkgs "opencode"} opencode.json
      mkdir -p .claude .opencode
      # Replace leftover real (empty) dirs from pre-generated layouts,
      # then point the agent dirs at the rendered farms.
      [ -d .claude/agents ] && [ ! -L .claude/agents ] && rmdir .claude/agents 2>/dev/null || true
      [ -d .opencode/agents ] && [ ! -L .opencode/agents ] && rmdir .opencode/agents 2>/dev/null || true
      ln -sfn ${acfg.agentsLib.claudeAgentsDir pkgs} .claude/agents
      ln -sfn ${acfg.agentsLib.opencodeAgentsDir pkgs} .opencode/agents
      # Knowledge memory plane: generated namespace + project.yml.
      ${acfg.memoryPlane.lib.placeScript pkgs}
      # Generated workmux config — a real file (not a symlink): workmux
      # reads the main worktree's copy during merges, and the header
      # carries the operational rationale.
      install -m 644 ${acfg.workmuxLib.configFile pkgs} .workmux.yaml
      # http-server secrets: exported client-side from the backend CLI.
      ${acfg.secrets.lib.exportsScript acfg.mcp.lib.httpSecretRefs}
    '';
  in {
    options.agentic.devenvLib = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = "Bootstrap building blocks: `bootstrapScript pkgs`, `projectConfigFor pkgs flavor`, `packages pkgs`.";
    };

    config = {
      agentic.devenvLib = {
        inherit bootstrapScript projectConfigFor;
        # Workflow CLIs the shell should carry: knowledge search (the
        # CLI equivalent Pi relies on).
        packages = pkgs: [(acfg.knowledgeSearch.lib.wrapper pkgs)];
      };

      # Wired devenv module, published into the consumer's namespace
      # (imported by `devenv.shells.<name>.imports` under the
      # flake-parts transport).
      flake.modules.devenv.agentic = {pkgs, ...}: {
        packages = acfg.devenvLib.packages pkgs;
        enterShell = bootstrapScript pkgs;
        # One worktree setup path for ALL creators (agentic-devenv
        # spec): Claude Code's native worktrees run the SAME script the
        # generated .workmux.yaml post_create runs. Wired through
        # devenv's first-party claude.code integration; takes effect
        # when the consumer enables claude.code.
        claude.code.hooks.agentic-worktree-setup = {
          hookType = "WorktreeCreate";
          name = "agentic-worktree-setup";
          command = "${acfg.workmuxLib.setupScript pkgs}/bin/agentic-worktree-setup";
        };
      };
    };
  };
}
