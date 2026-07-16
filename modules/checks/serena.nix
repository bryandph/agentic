# Fixture check for the pinned serena entry (task 2.5): one dual-tier
# definition resolves to the lock-pinned mcp-servers-nix package through
# a wrapper carrying --project "$(pwd)" and PYTHONPATH isolation. The
# user tier renders into Codex's native MCP schema, and both deployment
# shapes render — memory-only with a fixed_tools custom context and no
# language servers, full with the built-in context and declared language
# servers on PATH.
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
          agentic.serena.languageServers = [(pkgs: pkgs.hello)];

          flake.agenticProbe = {
            serenaTiers = config.agentic.mcp.servers.serena.tiers;
          };

          perSystem = {pkgs, ...}: {
            packages = {
              serena-full = config.agentic.serena.lib.wrapperFor pkgs "full";
              serena-memory = config.agentic.serena.lib.wrapperFor pkgs "memory-only";
              serena-context = config.agentic.serena.lib.memoryContextFile pkgs;
              serena-codex-user = pkgs.writeText "serena-codex-user.json" (
                builtins.toJSON (config.agentic.mcp.lib.renderCodexTier pkgs "user")
              );
            };
          };
        })
      ];
    };

    fp = n: fixture.packages.${system}.${n};
  in {
    checks.serena = assert fixture.agenticProbe.serenaTiers == ["user" "project"];
      pkgs.runCommand "agentic-serena" {
        nativeBuildInputs = [pkgs.gnugrep pkgs.jq];
      } ''
        set -euo pipefail

        full=${fp "serena-full"}/bin/serena-full
        memory=${fp "serena-memory"}/bin/serena-memory-only
        context=${fp "serena-context"}
        codex_user=${fp "serena-codex-user"}

        # The same registry definition reaches Codex through the user
        # tier and retains the pinned full-shape wrapper command.
        [ "$(jq -r 'has("serena")' "$codex_user")" = true ]
        [ "$(jq -r '.serena.command' "$codex_user")" = "$full" ]

        # Both shapes: pinned binary (store path, not nix run), project
        # pinning expanded by the wrapper shell, PYTHONPATH isolation.
        for w in "$full" "$memory"; do
          grep -qF 'export PYTHONPATH=""' "$w"
          grep -qF -- '--project "$(pwd)"' "$w"
          grep -qE 'exec /nix/store/.*/bin/serena start-mcp-server' "$w"
        done

        # full: built-in context + declared language servers on PATH.
        grep -qF -- '--context claude-code' "$full"
        grep -qF 'hello' "$full"

        # memory-only: custom context file with fixed_tools = memory
        # tool set; no language-server PATH injection.
        grep -qF -- "--context $context" "$memory"
        ! grep -qF 'hello' "$memory"
        grep -qF 'fixed_tools' "$context"
        grep -qF 'read_memory' "$context"
        grep -qF 'rename_memory' "$context"
        ! grep -qE 'find_symbol|language_server' "$context"

        touch $out
      '';
  };
}
