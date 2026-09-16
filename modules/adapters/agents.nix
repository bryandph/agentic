# Refresh only the generated project roles, without running the full shell
# bootstrap (MCP credentials, memory setup, and workmux are separate).
{
  flake.modules.flake.agentic = {config, ...}: {
    perSystem = {pkgs, ...}: {
      apps.write-agent-roles = {
        type = "app";
        program = toString (pkgs.writeShellScript "write-agent-roles" ''
          set -euo pipefail
          ${config.agentic.agentsLib.placeScript pkgs}
        '');
      };
    };
  };
}
