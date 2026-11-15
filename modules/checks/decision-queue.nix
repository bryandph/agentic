# Offline fixtures only; the UNVERIFIED Cotal adapter never contacts a service.
{
  perSystem = {pkgs, ...}: let
    package = import ../registry/_outcome/package.nix {inherit pkgs;};
  in {
    checks.decision-queue = pkgs.runCommand "agentic-decision-queue" {nativeBuildInputs = [pkgs.python3];} ''
      export HOME=$TMPDIR
      export AGENTIC_OUTCOME_SCHEMA=${../../schemas/agentic.outcome-1.json}
      export PYTHONDONTWRITEBYTECODE=1
      python3 ${../registry/_outcome}/test_decide.py ${package}/bin/workbench-decide
      touch "$out"
    '';
  };
}
