# Cotal personas as a package: the environment places it at the space
# root's `.cotal/agents` (a mesh-wide catalog, so delivery is user-tier,
# not per project).
{
  flake.modules.flake.agentic = {config, ...}: {
    perSystem = {pkgs, ...}: {
      packages.cotal-personas = config.agentic.agentsLib.cotalAgentsDir pkgs;
    };
  };
}
