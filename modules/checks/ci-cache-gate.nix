# Offline, no-upload writer regression matrix. Uses the production shell
# source with synthetic Nix capability stubs; the real-store scenario suite
# is separate (ci-cache-tools).
{...}: {
  perSystem = {pkgs, ...}: {
    checks.ci-cache-gate =
      pkgs.runCommand "agentic-ci-cache-gate" {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.diffutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.jq
          pkgs.python3
        ];
      } ''
        python3 ${./_fixtures/ci-cache-gate.py} ${pkgs.bash}/bin/bash ${../registry/_ci-cache/agentic-ci-cache.sh}
        touch "$out"
      '';
  };
}
