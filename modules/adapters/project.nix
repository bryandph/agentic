# Project-tier delivery adapter (design D4).
#
# Feeds the rendered project-tier registry into mcp-servers-nix's
# flake-parts module, which owns the per-flavor file formats
# (`.mcp.json` for Claude Code, Codex TOML, OpenCode config, VS Code workspace) and
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
      type = lib.types.listOf (lib.types.enum ["claude-code" "codex" "opencode" "vscode-workspace"]);
      default = ["claude-code" "codex" "opencode"];
      description = ''
        Project-tier flavors rendered by the upstream flake-parts module.
      '';
    };

    config.perSystem = {pkgs, ...}: {
      mcp-servers = {
        flavors = lib.genAttrs config.agentic.mcp.projectFlavors (
          flavor: {
            enable = true;
            settings =
              {
                servers =
                  if flavor == "codex"
                  then config.agentic.mcp.lib.renderCodexTier pkgs "project"
                  else config.agentic.mcp.lib.renderTier pkgs "project";
              }
              // lib.optionalAttrs (flavor == "opencode") {
                "$schema" = "https://opencode.ai/config.json";
              };
          }
        );
      };
    };
  };
}
