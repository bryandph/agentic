{...}: {
  perSystem = {pkgs, ...}: let
    setup = pkgs.writeScriptBin "workbench-worktree-setup" ''
      #!${pkgs.runtimeShell}
      exec ${pkgs.python3}/bin/python3 "$FIXTURE/setup.py" "$@"
    '';
    start = (import ../registry/_worker-start.nix pkgs).override {setupScript = setup;};
  in {
    checks.worker-start =
      pkgs.runCommand "workbench-worker-start-fixtures" {
        nativeBuildInputs = [pkgs.python3];
      } ''
        python3 ${./_worker-start.py} ${start}/bin/workbench-worker-start
        touch "$out"
      '';
  };
}
