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
      url = "github:bryandph/mcp-servers-nix/11c18bdce72a134168384a09b9df52268d3dcfd9";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Knowledge semantic search (design D11): local models, disposable
    # out-of-repo index (~/.cache/qmd), MCP + CLI — the CLI matters
    # because Pi has no core MCP support.
    #
    # Deliberately NOT following our nixpkgs: qmd's bun/node-gyp build
    # (better-sqlite3 native rebuild) only works against the
    # bun/node/node-gyp combination of its own pinned nixpkgs-unstable —
    # under 26.05's toolchain, gyp fails on darwin ("No Xcode or CLT
    # version detected"). Same deviation rationale as the Hyprland
    # chain in nixspace: follows-dedup yields a broken build here.
    qmd.url = "github:tobi/qmd";

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
