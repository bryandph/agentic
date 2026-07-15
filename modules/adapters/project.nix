# Project-tier delivery adapter (design D4).
#
# Feeds the rendered project-tier registry into mcp-servers-nix's
# flake-parts module, which owns the per-flavor file formats
# (`.mcp.json` for Claude Code, opencode config, vscode workspace) and
# the shellHook that symlinks them into the worktree. Core maps schema
# only — the upstream module is imported into the consumer's eval as
# part of `flakeModules.default`, pinned by core's flake.lock.
#
# Consumers read `perSystem.mcp-servers.{configs,shellHook,packages}`
# downstream (the agentic devenv module wires the shellHook into
# enterShell).
{inputs, ...}: {
  flake.modules.flake.agentic = {
    lib,
    config,
    ...
  }: {
    imports = [inputs.mcp-servers-nix.flakeModule];

    options.agentic.mcp.projectFlavors = lib.mkOption {
      type = lib.types.listOf (lib.types.enum ["claude-code" "opencode" "vscode-workspace"]);
      default = ["claude-code" "opencode"];
      description = ''
        Project-tier flavors rendered by the upstream flake-parts module.
        Codex is placed separately by the transport-neutral bootstrap using
        the upstream library's `codex` flavor because the upstream
        flake-parts flavor list does not expose it.
      '';
    };

    config.perSystem = {pkgs, ...}: {
      mcp-servers = {
        flavors = lib.genAttrs config.agentic.mcp.projectFlavors (flavor:
          {enable = true;}
          // lib.optionalAttrs (flavor == "opencode") {
            settings."$schema" = "https://opencode.ai/config.json";
          });
        settings.servers = config.agentic.mcp.lib.renderTier pkgs "project";
      };
    };
  };
}
