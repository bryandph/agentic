# Shared by consumer shells, the contributor shell, and offline checks.
{pkgs}: let
  command = name: mode:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [pkgs.python3 pkgs.git];
      text = ''
        export AGENTIC_OUTCOME_SCHEMA=${../../../schemas/agentic.outcome-1.json}
        exec python3 ${./outcome.py} ${mode} "$@"
      '';
    };
in
  pkgs.symlinkJoin {
    name = "workbench-outcome";
    paths = [
      (command "workbench-outcome" "outcome")
      (command "workbench-verify" "verify")
    ];
  }
