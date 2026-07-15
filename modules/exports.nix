# Conventional consumer exports (design D10). Internals are dendritic:
# feature modules publish into `flake.modules.<class>.<name>` (`flake` =
# flake-parts modules, `homeManager`, `devenv`). This file aliases that
# namespace into the conventional output attrs — the multi-adapter shape
# established by mcp-servers-nix and devenv — so non-dendritic consumers
# never need import-tree or the modules namespace. Both channels expose
# the same modules; dendritic consumers may merge `flake.modules.*`
# directly instead.
{config, ...}: {
  # Seed the namespace with the (currently empty) core modules so the
  # aliases below always resolve. Task groups 2-4 grow these: the MCP
  # registry and agent/knowledge registry land in `flake.agentic`, the
  # shell bootstrap in `devenv.agentic`, the user-tier delivery in
  # `homeManager.agentic`.
  flake.modules = {
    flake.agentic = {};
    homeManager.agentic = {};
    devenv.agentic = {};
  };

  flake = {
    flakeModules = {
      agentic = config.flake.modules.flake.agentic;
      default = config.flake.modules.flake.agentic;
    };

    devenvModules = {
      agentic = config.flake.modules.devenv.agentic;
      default = config.flake.modules.devenv.agentic;
    };

    homeModules = {
      agentic = config.flake.modules.homeManager.agentic;
      default = config.flake.modules.homeManager.agentic;
    };
  };
}
