{...}: {
  perSystem = {pkgs, ...}: {
    checks.worker-start =
      pkgs.runCommand "workbench-worker-start-fixtures" {
        nativeBuildInputs = [pkgs.python3];
      } ''
        python3 ${./_worker-start.py} ${import ../registry/_worker-start.nix pkgs}/bin/workbench-worker-start
        touch "$out"
      '';
  };
}
