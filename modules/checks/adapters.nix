# Fixture check for the delivery adapters (task 2.4): one registry, and
# the project-tier artifacts (.mcp.json + opencode config) render from
# it through the upstream mcp-servers-nix module — consistent content,
# per-flavor format owned upstream. The wired user-tier HM module must
# be published into the consumer's modules namespace (its full HM eval
# is the consuming repo's integration test — core does not pin
# home-manager).
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
            vault.mount = "fixture-kv";
          };

          agentic.mcp.servers = {
            forge = {
              tiers = ["user" "project"];
              command = pkgs: "${pkgs.hello}/bin/hello";
              args = ["-t" "stdio"];
              secrets.FORGE_TOKEN = {
                path = "fixture/forge";
                field = "token";
              };
            };
            docs = {
              type = "http";
              url = "https://docs.fixture.example/mcp";
              headers.Authorization = "Bearer \${DOCS_API_KEY}";
              secrets.DOCS_API_KEY = {
                path = "fixture/docs";
                field = "key";
              };
            };
          };

          flake.agenticProbe.hmPublished = config.flake.modules.homeManager ? agentic;

          perSystem = {config, ...}: {
            packages = {
              fixture-claude-config = config.mcp-servers.configs.claude-code;
              fixture-opencode-config = config.mcp-servers.configs.opencode;
            };
          };
        })
      ];
    };
  in {
    checks.adapters = assert fixture.agenticProbe.hmPublished;
      pkgs.runCommand "agentic-adapters" {
        nativeBuildInputs = [pkgs.jq pkgs.gnugrep];
      } ''
        set -euo pipefail

        claude=${fixture.packages.${system}.fixture-claude-config}
        opencode=${fixture.packages.${system}.fixture-opencode-config}

        # .mcp.json (claude-code flavor): registry entries under
        # mcpServers, stdio command wrapped, http header untouched.
        [ "$(jq -r '.mcpServers.forge.type' "$claude")" = stdio ]
        [ "$(jq -r '.mcpServers.forge.args | join(" ")' "$claude")" = "-t stdio" ]
        wrapper=$(jq -r '.mcpServers.forge.command' "$claude")
        grep -qF "vault kv get '-mount=fixture-kv' '-field=token' fixture/forge" "$wrapper"
        [ "$(jq -r '.mcpServers.docs.url' "$claude")" = "https://docs.fixture.example/mcp" ]
        [ "$(jq -r '.mcpServers.docs.headers.Authorization' "$claude")" = 'Bearer ''${DOCS_API_KEY}' ]

        # opencode config: same definitions, upstream-translated schema
        # (local/remote, command array, enabled flag).
        [ "$(jq -r '.mcp.forge.type' "$opencode")" = local ]
        [ "$(jq -r '.mcp.forge.command | join(" ")' "$opencode")" = "$wrapper -t stdio" ]
        [ "$(jq -r '.mcp.docs.type' "$opencode")" = remote ]
        [ "$(jq -r '.mcp.docs.url' "$opencode")" = "https://docs.fixture.example/mcp" ]

        # No plaintext anywhere: the only credential material in either
        # artifact is the CLI invocation / env reference.
        ! grep -riE 'fixture-secret|hvs\.' "$claude" "$opencode"

        touch $out
      '';
  };
}
