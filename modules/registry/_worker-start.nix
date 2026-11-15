# Keep the standalone `import ... pkgs` form; worktreeLib overrides setup with
# its consumer-configured derivation rather than relying on a sibling on PATH.
pkgs:
pkgs.lib.makeOverridable ({setupScript ? (pkgs.lib.evalModules {modules = [./_worktree.nix];}).config.agentic.worktreeLib.setupScript pkgs}:
    pkgs.writeShellApplication {
      name = "workbench-worker-start";
      text = ''
        export AGENTIC_WORKTREE_SETUP=${pkgs.lib.escapeShellArg "${setupScript}/bin/workbench-worktree-setup"}
        ${pkgs.python3}/bin/python3 ${./_worker-start.py} "$@"
      '';
    }) {}
