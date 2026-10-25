# Contributor shell for this repository (`nix develop`, loaded by .envrc):
# the treefmt wrapper behind `nix fmt`, openspec for the spec tree, and the
# workspace tooling. Internal only; modules/exports.nix does not publish it.
{
  perSystem = {
    config,
    pkgs,
    ...
  }: {
    devShells.default = pkgs.mkShell {
      packages = [
        config.treefmt.build.wrapper
        pkgs.openspec
        pkgs.git
        pkgs.mani
      ];
    };
  };
}
