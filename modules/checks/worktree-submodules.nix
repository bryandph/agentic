# BPH-88: real Git submodules in throwaway linked worktrees. Only Nix
# discovery is stubbed; worktree-setup covers real discovery and warm-up.
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
    fixture = extra:
      (inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [config.flake.flakeModules.default extra ({config, ...}: {flake.lib.fixture = config.agentic;})];
      }).lib.fixture;
    enabled = fixture {
      agentic.worktree = {
        traits.submodules = true;
        submodules.exclude = ["excluded space"];
      };
    };
    disabled = fixture {};
  in {
    checks.worktree-submodules =
      pkgs.runCommand "workbench-worktree-submodules" {
        nativeBuildInputs = [pkgs.git pkgs.python3];
      } ''
        python3 ${./_worktree-submodules.py} \
          ${enabled.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup \
          ${disabled.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup > "$out"
      '';
  };
}
