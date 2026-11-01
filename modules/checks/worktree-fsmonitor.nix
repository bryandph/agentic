# Real Git config isolation, with only daemon IPC modeled in the sandbox.
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
      imports = [config.flake.flakeModules.default ({config, ...}: {flake.lib.fixture = config.agentic;})];
    };
    git = pkgs.writeShellScriptBin "git" ''
      if [[ "$*" = *fsmonitor--daemon* ]]; then
        printf '%s\n' "$*" >> "$DAEMON_LOG"
        case "''${*: -1}" in
          status) case "$DAEMON_MODE" in
            running|race|stuck) [ -f "$DAEMON_STATE" ] || exit 0; exit 1 ;;
            missing) exit 128 ;;
            *) exit 1 ;;
          esac ;;
          stop)
            if [ "$DAEMON_MODE" != stuck ]; then echo stopped > "$DAEMON_STATE"; fi
            if [ "$DAEMON_MODE" = race ]; then
              echo 'fatal: fsmonitor daemon not running' >&2
              exit 1
            fi
            exit 0 ;;
        esac
        exit 99
      fi
      exec ${pkgs.git}/bin/git "$@"
    '';
    setup = fixture.lib.fixture.worktreeLib.setupScript (pkgs // {inherit git;});
  in {
    checks.worktree-fsmonitor =
      pkgs.runCommand "worktree-fsmonitor" {
        nativeBuildInputs = [pkgs.python3 pkgs.git];
      } ''
        python3 ${./_worktree-fsmonitor.py} ${setup}/bin/workbench-worktree-setup ${pkgs.runtimeShell} > "$out"
      '';
  };
}
