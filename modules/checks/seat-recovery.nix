{
  perSystem = {pkgs, ...}: {
    checks = {
      seat-snapshot = pkgs.runCommand "agentic-seat-snapshot-fixtures" {nativeBuildInputs = [pkgs.nodejs];} ''
        node ${./_fixtures/seat-snapshot.mjs} ${../packages/_pi-seat-snapshot/index.js}
        touch "$out"
      '';
      worker-recover = pkgs.runCommand "workbench-worker-recover-fixtures" {nativeBuildInputs = [pkgs.python3];} ''
        python3 ${./_worker-recover.py} \
          ${import ../registry/_seat-tools/package.nix pkgs "workbench-worker-recover"}/bin/workbench-worker-recover \
          ${import ../registry/_seat-tools/package.nix pkgs "agentic-seat-snapshot"}/bin/agentic-seat-snapshot
        touch "$out"
      '';
    };
  };
}
