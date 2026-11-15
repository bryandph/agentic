# Contributor shell for this repository (`nix develop`, loaded by .envrc):
# the treefmt wrapper behind `nix fmt`, openspec for the spec tree, and the
# workspace tooling. Internal only; modules/exports.nix does not publish it.
{
  inputs,
  config,
  ...
}: let
  # Evaluate the same exported registry consumers use, with this repository's
  # (currently default) creator-neutral worktree configuration.
  own = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
    systems = ["aarch64-darwin" "aarch64-linux" "x86_64-darwin" "x86_64-linux"];
    imports = [
      config.flake.flakeModules.default
      ({config, ...}: {
        flake.lib.worktree = config.agentic.worktreeLib;
        flake.lib.memoryPlane = config.agentic.memoryPlane.lib;
      })
    ];
  };
in {
  perSystem = {
    config,
    pkgs,
    self',
    ...
  }: {
    devShells.default = pkgs.mkShell {
      packages = [
        config.treefmt.build.wrapper
        pkgs.openspec
        pkgs.git
        pkgs.mani
        self'.packages.agentic-hooks-doctor
        self'.packages.agentic-attention-watch
        (import ./registry/_outcome/package.nix {inherit pkgs;})
        (own.lib.memoryPlane.ignoreCheckPackage pkgs)
        (own.lib.worktree.setupScript pkgs)
        (own.lib.worktree.teardownScript pkgs)
        (own.lib.worktree.workerStartScript pkgs)
        (own.lib.worktree.removeScript pkgs)
        (own.lib.worktree.servicesScript pkgs)
        (import ./registry/_seat-tools/package.nix pkgs "agentic-seat-snapshot")
        (own.lib.worktree.workerRecoverScript pkgs)
      ];
    };
  };
}
