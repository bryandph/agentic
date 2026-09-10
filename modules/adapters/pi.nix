{
  flake.modules.flake.agentic = {config, ...}: {
    perSystem = {pkgs, ...}: {
      packages.pi-agent-roles = config.agentic.agentsLib.piPackage pkgs;
    };
  };
}
