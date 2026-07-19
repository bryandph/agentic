# devenv-NATIVE transport shim (design D9, agentic-devenv spec).
#
# Opt-in acceleration: a consumer's devenv.yaml declares this repo as an
# input and imports it — devenv loads THIS file, no flake-parts eval, no
# flake git discovery (the in-place eval that sidesteps worktree gitdir
# indirection entirely). It composes the SAME transport-neutral registry
# modules as the exported flakeModule and wires the same shellModule, so
# the artifact set matches flake-parts consumption exactly.
#
#   # consumer devenv.yaml
#   inputs:
#     agentic:
#       url: github:bryandph/agentic
#       flake: false
#   imports:
#     - agentic
#
# Upstream deps resolve from CORE'S OWN committed flake.lock via
# fetchTree/getFlake (locked, narHash-pinned — deterministic without a
# flake eval). DUAL-LOCK DISCIPLINE: devenv.yaml/devenv.lock pins core
# itself a second time next to any flake.lock in the repo; the flake.lock
# is the authoritative version statement — generate devenv.yaml's pin
# from it or CI-check that both reference the same core rev (see
# docs/native-transport.md).
{
  pkgs,
  lib,
  config,
  ...
}: let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  locked = name: builtins.fetchTree lock.nodes.${name}.locked;
in {
  _module.args.agenticInputs = {
    mcpServersSrc = "${locked "mcp-servers-nix"}";
    qmdBase = pkgs': (builtins.getFlake "github:tobi/qmd/${lock.nodes.qmd.locked.rev}").packages.${pkgs'.stdenv.hostPlatform.system}.qmd;
  };

  imports = [
    ./modules/registry/_secrets.nix
    ./modules/registry/_mcp.nix
    ./modules/registry/_forges.nix
    ./modules/registry/_serena.nix
    ./modules/registry/_knowledge-search.nix
    ./modules/registry/_knowledge.nix
    ./modules/registry/_agents.nix
    ./modules/registry/_memory-plane.nix
    ./modules/registry/_workmux.nix
    ./modules/registry/_bootstrap.nix
    ./modules/registry/_core-fragments.nix
    (builtins.toPath "${locked "mcp-servers-nix"}/modules/devenv.nix")
  ];

  mcp-servers = config.agentic.devenvLib.managedMcpConfig pkgs;
  packages = config.agentic.devenvLib.packages pkgs;
  enterShell = config.agentic.devenvLib.bootstrapScript pkgs;
  claude.code.hooks.agentic-worktree-setup = {
    hookType = "WorktreeCreate";
    name = "agentic-worktree-setup";
    command = "${config.agentic.workmuxLib.setupScript pkgs}/bin/agentic-worktree-setup";
  };
}
