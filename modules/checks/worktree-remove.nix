# Real Git checkouts, PATH-faked Herdr, and the repository's actual teardown runner.
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
    fixture = hooks:
      (inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [
          config.flake.flakeModules.default
          ({config, ...}: {
            agentic.worktree.teardownHooks = hooks;
            flake.lib.worktree = config.agentic.worktreeLib;
          })
        ];
      }).lib.worktree;
    good = fixture ["echo verified: resources absent"];
    bad = fixture ["echo cleanup failed; exit 1"];
    skipped = fixture ["echo verified: resources absent; echo skipped: unavailable"];
  in {
    checks.worktree-remove =
      pkgs.runCommand "workbench-worktree-remove-fixtures" {
        nativeBuildInputs = [pkgs.python3 pkgs.git];
      } ''
        python3 ${./_worktree-remove.py} \
          ${good.removeScript pkgs}/bin/workbench-worktree-remove \
          ${bad.removeScript pkgs}/bin/workbench-worktree-remove \
          ${skipped.removeScript pkgs}/bin/workbench-worktree-remove > "$out"
      '';
  };
}
