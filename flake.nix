{
  description = "agentic — org-neutral agentic environment core: MCP registry, agent/knowledge registry, devenv bootstrap, project templates";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Dendritic auto-import library. Walks ./modules and treats every .nix
    # file (paths NOT containing `/_`) as a flake-parts module.
    import-tree.url = "github:denful/import-tree";

    # Upstream MCP delivery planes (design D4): the flake-parts module
    # renders per-flavor project configs (.mcp.json, opencode config) and
    # the home-manager module bridges into `programs.mcp`. Core's
    # adapters feed the registry into these — core maps schema, upstream
    # owns file formats. Consumers lock this pin through their own
    # flake.lock (follows-overridable).
    mcp-servers-nix = {
      url = "github:natsukium/mcp-servers-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      # Dendritic tree-walk: every modules/<...>.nix (paths NOT containing
      # `/_`) is auto-imported as a flake-parts module. Internals stay
      # dendritic; consumers get the conventional exports published by
      # modules/exports.nix (see README, "Consuming").
      imports = [(inputs.import-tree ./modules)];
    };
}
