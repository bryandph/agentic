# Forge instances (design D4, agentic-mcp-registry spec).
#
# Git forges are declared as an attrset of instances — kind (github |
# gitea), endpoint, secret ref — because the upstream `programs.*`
# modules are single-instance and real environments run several forges
# concurrently (a public GitHub and a private Gitea at minimum). Each
# instance expands into its own registry entry (`agentic.mcp.servers.
# <name>`), which the delivery adapters emit as freeform
# `settings.servers` entries downstream.
#
# The per-kind expansion (server package, argv, token/endpoint env
# vars) is core data; instances contribute only identity. An upstream
# gitea program-module for mcp-servers-nix is a tracked PR candidate —
# until it exists the freeform path is the delivery mechanism.
{
  lib,
  config,
  ...
}: let
  cfg = config.agentic;

  forgeType = lib.types.submodule {
    options = {
      kind = lib.mkOption {
        type = lib.types.enum ["github" "gitea"];
        description = "Forge flavor: selects the MCP server package and its configuration vocabulary.";
      };
      endpoint = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Forge base URL. Required for gitea; null for github.com
          (set it for GitHub Enterprise).
        '';
      };
      secret = lib.mkOption {
        type = cfg.secrets.refType;
        description = "Access-token ref, resolved by the secret backend (the `env` attr is ignored — the kind fixes the variable name).";
      };
      tiers = lib.mkOption {
        type = lib.types.listOf (lib.types.enum ["user" "project"]);
        default = ["user" "project"];
        description = "Tier membership of the expanded server entry.";
      };
    };
  };

  expand = name: forge:
    if forge.kind == "gitea"
    then {
      inherit (forge) tiers;
      command = pkgs: "${pkgs.gitea-mcp-server}/bin/gitea-mcp";
      args = ["-t" "stdio"];
      env.GITEA_HOST =
        if forge.endpoint != null
        then forge.endpoint
        else throw "agentic.forges.${name}: gitea instances require `endpoint`";
      secrets.GITEA_ACCESS_TOKEN = {inherit (forge.secret) path field;};
    }
    else {
      inherit (forge) tiers;
      command = pkgs: "${pkgs.github-mcp-server}/bin/github-mcp-server";
      args = ["stdio"];
      env = lib.optionalAttrs (forge.endpoint != null) {GITHUB_HOST = forge.endpoint;};
      secrets.GITHUB_PERSONAL_ACCESS_TOKEN = {inherit (forge.secret) path field;};
    };
in {
  options.agentic.forges = lib.mkOption {
    type = lib.types.attrsOf forgeType;
    default = {};
    description = "Git forge instances; each expands to its own MCP server registry entry named after the instance.";
  };

  config.agentic.mcp.servers = lib.mapAttrs expand cfg.forges;
}
