# Project shell bootstrap building blocks (design D6/D9, agentic-devenv
# spec) — transport-neutral: consumed by the flake-parts adapter
# (modules/adapters/devenv.nix) AND the devenv-native shim (/devenv.nix)
# so both transports produce the same artifact set.
#
# On shell entry, idempotently places: `.mcp.json` + opencode config
# (rendered by upstream mcp-servers-nix lib from the project-tier
# registry), agent directories, the generated `.serena/project.yml` +
# read-only memory namespace, the generated `.workmux.yaml`, and the
# http-secret exports. `AGENTS.md`/`CLAUDE.md` are committed artifacts,
# never shell-entry placements.
#
# cwd-safety: no `.git` assumptions at all — only workspace-relative
# writes, so gitlink files and `__worktrees` indirection cannot break
# it. (The historical worktree failure lived in devenv/direnv init
# BEFORE enterShell; the worktree-setup script's probe handles that.)
{
  lib,
  config,
  agenticInputs,
  ...
}: let
  acfg = config.agentic;
  mcpLib = import "${agenticInputs.mcpServersSrc}/lib";

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
    description = "Bootstrap building blocks: `bootstrapScript pkgs`, `projectConfigFor pkgs flavor`, `packages pkgs`, `shellModule` (the devenv module body both transports wire).";
  };

  config.agentic.devenvLib = {
    inherit bootstrapScript projectConfigFor;
    # Workflow CLIs the shell should carry: knowledge search (the CLI
    # equivalent Pi relies on).
    packages = pkgs: [(acfg.knowledgeSearch.lib.wrapper pkgs)];

    # The devenv module body — identical under both transports.
    shellModule = {pkgs, ...}: {
      packages = acfg.devenvLib.packages pkgs;
      enterShell = bootstrapScript pkgs;
      # One worktree setup path for ALL creators (agentic-devenv spec):
      # Claude Code's native worktrees run the SAME script the generated
      # .workmux.yaml post_create runs. Wired through devenv's
      # first-party claude.code integration; takes effect when the
      # consumer enables claude.code.
      claude.code.hooks.agentic-worktree-setup = {
        hookType = "WorktreeCreate";
        name = "agentic-worktree-setup";
        command = "${acfg.workmuxLib.setupScript pkgs}/bin/agentic-worktree-setup";
      };
    };
  };
}
