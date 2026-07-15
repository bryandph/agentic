# Fixture check for the knowledge search server (task 2.5b): the
# registry entry is project-tier with a CLI equivalent (Pi coverage),
# and the wrapper registers the declared per-repo + org collections
# before serving.
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
    fixture = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [system];
      imports = [
        config.flake.flakeModules.default
        ({config, ...}: {
          agentic.knowledgeSearch.collections = {
            fixture-repo.path = ".serena/memories";
            fixture-org.path = "/nix/store/fixture-org-fragments";
          };

          flake.agenticProbe = {
            knowledgeTiers = config.agentic.mcp.servers.knowledge.tiers;
            knowledgeArgs = config.agentic.mcp.servers.knowledge.args;
            cliEquivalents = builtins.attrNames config.agentic.mcp.lib.cliEquivalents;
          };

          perSystem = {pkgs, ...}: {
            packages.fixture-qmd-wrapper = config.agentic.knowledgeSearch.lib.wrapper pkgs;
          };
        })
      ];
    };

    p = fixture.agenticProbe;
  in {
    checks.knowledge-search = assert p.knowledgeTiers == ["project"];
    assert p.knowledgeArgs == ["mcp"];
    assert p.cliEquivalents == ["knowledge"];
      pkgs.runCommand "agentic-knowledge-search" {
        nativeBuildInputs = [pkgs.gnugrep];
      } ''
        set -euo pipefail
        w=${fixture.packages.${system}.fixture-qmd-wrapper}/bin/qmd-knowledge

        grep -qF "collection add .serena/memories --name fixture-repo" "$w"
        grep -qF "collection add /nix/store/fixture-org-fragments --name fixture-org" "$w"
        grep -qE 'exec /nix/store/.*/bin/qmd "\$@"' "$w"

        touch $out
      '';
  };
}
