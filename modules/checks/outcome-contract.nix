# Offline stdlib fixtures exercise the installed CLIs, not alternate wrappers.
{
  perSystem = {pkgs, ...}: let
    package = import ../registry/_outcome/package.nix {inherit pkgs;};
  in {
    checks.outcome-contract = pkgs.runCommand "agentic-outcome-contract" {nativeBuildInputs = [pkgs.python3 pkgs.git];} ''
      export HOME=$TMPDIR
      export GIT_CONFIG_NOSYSTEM=1
      export AGENTIC_OUTCOME_SCHEMA=${../../schemas/agentic.outcome-1.json}
      export PYTHONDONTWRITEBYTECODE=1
      python3 ${../registry/_outcome}/test_outcome.py \
        ${package}/bin/workbench-outcome ${package}/bin/workbench-verify
      touch "$out"
    '';
  };
}
