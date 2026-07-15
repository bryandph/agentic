# Dendritic bootstrap. Imports `flake-parts.flakeModules.modules` (which
# adds the `flake.modules.<class>.<name>` namespace every feature module
# publishes into) plus the third-party flakeModules the core repo itself
# consumes. flake.nix's outputs.imports collapses to just
# `(inputs.import-tree ./modules)`.
{inputs, ...}: {
  imports = [
    inputs.flake-parts.flakeModules.modules
    inputs.treefmt-nix.flakeModule
  ];
}
