# Flake-parts publication of the devenv shell module (design D6/D9).
# The actual bootstrap lives transport-neutral in
# modules/registry/_bootstrap.nix (`agentic.devenvLib.shellModule`);
# this file only publishes it into the consumer's namespace for the
# flake-parts transport (`devenv.shells.<name>.imports`). The
# devenv-native transport wires the same shellModule via the shim at
# /devenv.nix.
{
  flake.modules.flake.agentic = {config, ...}: {
    flake.modules.devenv.agentic = config.agentic.devenvLib.shellModule;
  };
}
