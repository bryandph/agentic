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
    pkgs,
    ...
  }: let
    sharedPath = "${config.home.homeDirectory}/.config/mcp/mcp.json";
    native = config.xdg.configFile."mcp/mcp.json" or null;
    # HM file targets are home-relative unless outside the home directory.
    nativePath =
      if native == null
      then null
      else
        toString (/.
          + (
            if lib.hasPrefix "/" native.target
            then native.target
            else "${config.home.homeDirectory}/${native.target}"
          ));
    nativeDeliversShared = native != null && native.enable && nativePath == sharedPath;
    # Reuse upstream's serialization, including null/default-field removal and
    # environment references. Do not emit raw HM options.
    source =
      if native != null
      then native.source
      else
        (pkgs.formats.json {}).generate "mcp.json" {
          mcpServers = lib.mapAttrs (_: server:
            lib.hm.mcp.transformMcpServer {
              inherit server;
              extraTransforms = [lib.hm.mcp.addType];
              exclude = ["serverUrl"];
            })
          config.programs.mcp.servers;
        };
  in {
    imports = [
      inputs.mcp-servers-nix.homeManagerModules.default
      (lib.mkAliasOptionModule ["workbench"] ["agentic"])
    ];

    options.agentic.mcp.sharedUserConfig.enable = lib.mkEnableOption "shared user MCP delivery to ~/.config/mcp/mcp.json (including Pi)";

    options.agentic.mcp.userServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = ''
        Rendered user-tier MCP servers (Claude schema — the registry's
        `renderTier pkgs "user"` output), bridged into home-manager's
        `programs.mcp` via mcp-servers-nix.
      '';
    };

    config = {
      mcp-servers.settings.servers = config.agentic.mcp.userServers;
      # Preserve public enrollment metadata across the upstream HM bridge.
      programs.mcp.servers =
        lib.mapAttrs (_: server: {inherit (server) oauth;})
        (lib.filterAttrs (_: server: (server.oauth or null) != null)
          config.agentic.mcp.userServers);
      # Prefer HM's native writer. A consumer can still explicitly disable it.
      programs.mcp.enable = lib.mkIf config.agentic.mcp.sharedUserConfig.enable (lib.mkDefault true);
      # Pi deliberately uses this literal path, not XDG_CONFIG_HOME. Add one
      # fallback only when the upstream file does not already land here.
      home.file.".config/mcp/mcp.json" =
        lib.mkIf
        (config.agentic.mcp.sharedUserConfig.enable && !nativeDeliversShared) {
          inherit source;
        };
    };
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
