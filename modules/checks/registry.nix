# Fixture-consumer checks for the MCP server registry (task 2.2).
#
# A fixture consumer defines an org-neutral server set exercising every
# schema shape: a dual-tier stdio server with secrets (forge-shaped), a
# project-tier http server with a secret header, a plain stdio server,
# and an `external` marker entry. Eval-time asserts cover tier
# filtering, http secret collection, and agent-reference validation;
# the built wrapper is grepped to prove secret resolution goes through
# the backend CLI.
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
          agentic.secrets = {
            backend = "vault";
            vault = {
              address = "https://vault.fixture.example:8200";
              mount = "fixture-kv";
            };
          };

          agentic.mcp.servers = {
            forge = {
              tiers = ["user" "project"];
              command = pkgs: "${pkgs.hello}/bin/hello";
              args = ["-t" "stdio"];
              env.FORGE_HOST = "https://forge.fixture.example";
              secrets.FORGE_TOKEN = {
                path = "fixture/forge";
                field = "token";
              };
            };

            docs = {
              tiers = ["project"];
              type = "http";
              url = "https://docs.fixture.example/mcp";
              headers.Authorization = "Bearer \${DOCS_API_KEY}";
              secrets.DOCS_API_KEY = {
                path = "fixture/docs";
                field = "key";
              };
            };

            plain = {
              tiers = ["user" "project"];
              command = pkgs: "${pkgs.hello}/bin/hello";
            };

            adhoc.external = true;
          };

          # Eval-level invariants, surfaced as a flake output the check
          # asserts on.
          flake.agenticProbe = {
            userTier = builtins.attrNames (config.agentic.mcp.lib.serversForTier "user");
            projectTier = builtins.attrNames (config.agentic.mcp.lib.serversForTier "project");
            httpSecretVars = builtins.attrNames config.agentic.mcp.lib.httpSecretRefs;
            validOk = config.agentic.mcp.lib.validateAgentRefs "fixture-agent" ["forge"];
            externalOk = config.agentic.mcp.lib.validateAgentRefs "fixture-agent" ["adhoc"];
            missingFails =
              !(builtins.tryEval (
                builtins.deepSeq (config.agentic.mcp.lib.validateAgentRefs "fixture-agent" ["nonexistent"]) true
              ))
              .success;
          };

          perSystem = {pkgs, ...}: {
            packages.fixture-project-forge = pkgs.writeText "forge-rendered.json" (builtins.toJSON (config.agentic.mcp.lib.renderTier pkgs "project").forge);
          };
        })
      ];
    };

    p = fixture.agenticProbe;
  in {
    checks.mcp-registry = assert p.userTier == ["forge" "plain"];
    assert p.projectTier == ["docs" "forge" "plain"];
    assert p.httpSecretVars == ["DOCS_API_KEY"];
    assert p.validOk == ["forge"];
    assert p.externalOk == ["adhoc"];
    assert p.missingFails;
      pkgs.runCommand "agentic-mcp-registry" {
        nativeBuildInputs = [pkgs.gnugrep pkgs.jq];
      } ''
        set -euo pipefail

        # The rendered forge entry: stdio, wrapped command, args/env
        # carried through, and the wrapper resolves the secret via the
        # backend CLI (no value at rest anywhere).
        rendered=${fixture.packages.${system}.fixture-project-forge}
        [ "$(jq -r .type "$rendered")" = stdio ]
        [ "$(jq -r '.args | join(" ")' "$rendered")" = "-t stdio" ]
        [ "$(jq -r .env.FORGE_HOST "$rendered")" = "https://forge.fixture.example" ]
        wrapper=$(jq -r .command "$rendered")
        grep -qF "vault kv get '-mount=fixture-kv' '-field=token' fixture/forge" "$wrapper"
        grep -qF 'export FORGE_TOKEN="$(' "$wrapper"

        touch $out
      '';
  };
}
