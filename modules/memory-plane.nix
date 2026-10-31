# Flake-only CI adapter; the memory-plane registry and its check script
# also serve devenv-native consumers, which have no perSystem options.
{
  flake.modules.flake.agentic = {
    lib,
    config,
    ...
  }: let
    cfg = config.agentic.memoryPlane;
  in {
    config.perSystem = {pkgs, ...}: {
      checks = lib.mkIf cfg.namespaces.require {
        serena-memory-namespaces = pkgs.runCommand "serena-memory-namespaces" {} ''
          set -euo pipefail
          cd ${config.agentic.instructions.selfPath}
          ${cfg.lib.namespaceCheckScript pkgs}
          touch "$out"
        '';
      };
    };
  };
}
