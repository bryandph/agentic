# User-tier delivery adapter (design D4).
#
# Two channels, same base module (the agentic-layering contract: both
# expose the same modules):
#
#   * static — `homeModules.default`: a home-manager module importing
#     mcp-servers-nix's HM bridge (which lands servers in home-manager's
#     `programs.mcp`, consumed by programs.{claude-code,opencode,codex}
#     via `enableMcpIntegration` — the codex TOML is user-tier and
#     upstream ships that integration). Plain HM consumers set
#     `agentic.mcp.userServers` themselves.
#
#   * wired — importing `flakeModules.default` publishes a fully-wired
#     variant into the CONSUMER's `flake.modules.homeManager.agentic`
#     namespace (and their `homeModules.agentic` output): the user-tier
#     registry rendering is baked in, so dendritic and flake-parts
#     consumers get zero-glue HM delivery.
{inputs, ...}: let
  baseModule = {
    config,
    lib,
    ...
  }: {
    imports = [inputs.mcp-servers-nix.homeManagerModules.default];

    options.agentic.mcp.userServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = ''
        Rendered user-tier MCP servers (Claude schema — the registry's
        `renderTier pkgs "user"` output), bridged into home-manager's
        `programs.mcp` via mcp-servers-nix.
      '';
    };

    config.mcp-servers.settings.servers = config.agentic.mcp.userServers;
  };
in {
  # Static channel (core's own namespace -> exports.nix aliases).
  flake.modules.homeManager.agentic = baseModule;

  # Wired channel, published into the consumer's eval.
  flake.modules.flake.agentic = {config, ...}: {
    flake.modules.homeManager.agentic = {pkgs, ...}: {
      imports = [baseModule];
      agentic.mcp.userServers = config.agentic.mcp.lib.renderTier pkgs "user";
    };
  };
}
