# Conventional consumer exports (design D10). Internals are dendritic:
# feature modules publish into `flake.modules.<class>.<name>` (`flake` =
# flake-parts modules, `homeManager`, `devenv`). This file aliases that
# namespace into the conventional output attrs — the multi-adapter shape
# established by mcp-servers-nix and devenv — so non-dendritic consumers
# never need import-tree or the modules namespace. Both channels expose
# the same modules; dendritic consumers may merge `flake.modules.*`
# directly instead.
{
  config,
  inputs,
  ...
}: {
  # Seed the namespace so the aliases below always resolve; the feature
  # modules grow these: the MCP registry and agent/knowledge registry
  # land in `flake.agentic`, the shell bootstrap in `devenv.agentic`,
  # the user-tier delivery in `homeManager.agentic`.
  flake.modules = {
    # The wired adapters publish into the CONSUMER's
    # `flake.modules.<class>.*` namespace — the exported flakeModule
    # therefore imports flake-parts' modules flakeModule so that
    # namespace exists even for non-dendritic consumers (harmless for
    # consumers that already import it, provided flake-parts is
    # follows-deduped to one copy).
    flake.agentic.imports = [inputs.flake-parts.flakeModules.modules];
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
      # Org-neutral language profiles (D8) — composable alongside the
      # agentic module; they never own a repo's packaging.
      inherit (config.flake.modules.devenv) rust python polyglot embedded-rust;
    };

    homeModules = {
      agentic = config.flake.modules.homeManager.agentic;
      default = config.flake.modules.homeManager.agentic;
    };
  };
}
