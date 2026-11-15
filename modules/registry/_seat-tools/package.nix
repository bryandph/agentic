# The old two-argument import remains usable. Consumer shells override the
# launcher through worktreeLib so recovery rechecks that consumer's setup.
pkgs: name:
pkgs.lib.makeOverridable ({workerStartScript ? import ../_worker-start.nix pkgs}:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        ${pkgs.lib.optionalString (name == "workbench-worker-recover") ''
          export AGENTIC_WORKER_START=${pkgs.lib.escapeShellArg "${workerStartScript}/bin/workbench-worker-start"}
        ''}
        ${pkgs.python3}/bin/python3 ${./.}/${
          if name == "agentic-seat-snapshot"
          then "snapshots.py"
          else "recover.py"
        } "$@"
      '';
    }) {}
