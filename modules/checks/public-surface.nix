# Pre-Workbench compatibility baseline. The two conventional flake module
# names must publish the same consumer modules and rendered project artifacts.
# Existing adapter, agent, memory, and workmux checks cover the file contents.
{
  inputs,
  config,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    lib = pkgs.lib;

    mkConsumer = entry: namespace:
      inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [
          entry
          ({config, ...}: let
            topConfig = config;
          in {
            ${namespace} = {
              secrets.backend = "env";
              mcp.servers.fixture = {
                tiers = ["project"];
                command = pkgs: "${pkgs.hello}/bin/hello";
              };
            };
            perSystem = {config, ...}: {
              packages = {
                baseline-claude = config.mcp-servers.configs.claude-code;
                baseline-codex = config.mcp-servers.configs.codex;
                baseline-opencode = config.mcp-servers.configs.opencode;
                baseline-workmux = topConfig.agentic.workmuxLib.configFile pkgs;
              };
            };
          })
        ];
      };

    byDefault = mkConsumer config.flake.flakeModules.default "agentic";
    byName = mkConsumer config.flake.flakeModules.agentic "agentic";
    byWorkbench = mkConsumer config.flake.flakeModules.workbench "workbench";
    artifactNames = ["baseline-claude" "baseline-codex" "baseline-opencode" "baseline-workmux"];
    sameArtifact = name: let
      expected = toString byDefault.packages.${system}.${name};
    in
      expected
      == toString byName.packages.${system}.${name}
      && expected == toString byWorkbench.packages.${system}.${name};
  in {
    checks.public-surface = assert lib.all sameArtifact artifactNames;
    assert lib.attrNames config.flake.templates == ["adopt" "agentic" "default" "embedded" "polyglot" "python" "rust"];
    assert toString config.flake.templates.agentic.path == toString config.flake.templates.default.path;
    assert config.flake.modules.flake ? agentic;
    assert config.flake.modules.flake ? workbench;
    assert config.flake.modules.devenv ? agentic;
    assert config.flake.modules.devenv ? workbench;
    assert config.flake.modules.homeManager ? agentic;
    assert config.flake.modules.homeManager ? workbench;
      pkgs.runCommand "agentic-public-surface" {} ''
        touch $out
      '';
  };
}
