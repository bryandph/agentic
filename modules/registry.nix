# Assembles the transport-neutral registry modules
# (modules/registry/_*.nix — underscore-skipped by import-tree) into the
# exported flakeModule, supplying the flake-transport input resolvers as
# the `agenticInputs` module arg. The devenv-native shim (/devenv.nix)
# imports the SAME files with lock-derived resolvers, so no capability
# can drift between transports.
{inputs, ...}: {
  flake.modules.flake.agentic = {
    _module.args.agenticInputs = {
      mcpServersSrc = "${inputs.mcp-servers-nix}";
      qmdBase = pkgs: inputs.qmd.packages.${pkgs.stdenv.hostPlatform.system}.qmd;
    };

    imports = [
      ./registry/_secrets.nix
      ./registry/_mcp.nix
      ./registry/_forges.nix
      ./registry/_serena.nix
      ./registry/_knowledge-search.nix
      ./registry/_knowledge.nix
      ./registry/_agents.nix
      ./registry/_memory-plane.nix
      ./registry/_workmux.nix
      ./registry/_bootstrap.nix
      ./registry/_core-fragments.nix
    ];
  };
}
