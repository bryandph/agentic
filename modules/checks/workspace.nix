# Fixture checks for the workspace layout feature. devenv is not pinned
# by core, so the devenv half evaluates against stubs of the two devenv
# options it writes and the rendered mani.yaml is validated by mani
# itself. The HM half uses the same test-only Home Manager pin as the
# pi-mcp fixture, with a stub `programs.herdr` standing in for the
# consumer-provided herdr module.
{config, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    devenvStubs = {
      options = {
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [];
        };
        files = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
          default = {};
        };
      };
    };
    evalDevenv = extra:
      (lib.evalModules {
        modules = [
          devenvStubs
          {_module.args.pkgs = pkgs;}
          config.flake.devenvModules.workspace
          extra
        ];
      }).config;
    populated = evalDevenv {
      agentic.workspace.repos = {
        core = {
          path = "src/core";
          url = "https://forge.fixture.example/core.git";
          tags = ["nix"];
        };
        docs = {
          path = "docs";
          url = "https://forge.fixture.example/docs.git";
        };
      };
    };
    empty = evalDevenv {};
    maniYaml = (pkgs.formats.yaml {}).generate "mani.yaml" populated.files."mani.yaml".yaml;

    hmSource = builtins.fetchTree {
      type = "github";
      owner = "nix-community";
      repo = "home-manager";
      rev = "65258d5c65a250189fde2e35f490d15e064c4c62";
      narHash = "sha256-Sxu1NLTD/Ern6hFGLlZmtKCSct3YQXZI/lls8RE1XeM=";
    };
    herdrStub = {
      options.programs.herdr.extraConfig = lib.mkOption {
        type = (pkgs.formats.toml {}).type;
        default = {};
      };
    };
    evalHome = modules:
      ((import "${hmSource}/lib" {inherit lib;}).homeManagerConfiguration {
        inherit pkgs;
        modules =
          [
            {
              home = {
                username = "fixture";
                homeDirectory = "/home/fixture";
                stateVersion = "26.05";
              };
            }
          ]
          ++ modules;
      }).config;
    rooted = {agentic.workspace.root = "/home/fixture/ws";};
    withHerdr = evalHome [config.flake.homeModules.workspace herdrStub rooted];
    withoutHerdr = evalHome [config.flake.homeModules.workspace rooted];
    unset = evalHome [config.flake.homeModules.workspace herdrStub];
    # Same feature through both exports: the key must dedupe the options.
    both = evalHome [config.flake.homeModules.workspace config.flake.homeModules.agentic rooted];

    hmValid =
      withHerdr.programs.herdr.extraConfig.worktrees.directory
      == "/home/fixture/ws/.worktrees"
      && withHerdr.programs.git.settings.worktree.useRelativePaths
      && withoutHerdr.programs.git.settings.worktree.useRelativePaths
      && unset.programs.herdr.extraConfig == {}
      && !(unset.programs.git.settings ? worktree)
      && both.agentic.workspace.worktreeDir == "/home/fixture/ws/.worktrees";
  in {
    checks.workspace-devenv = assert empty.files == {} && empty.packages == [];
      pkgs.runCommand "agentic-workspace-devenv" {nativeBuildInputs = [pkgs.mani pkgs.git];} ''
        set -euo pipefail
        export HOME=$TMPDIR
        cd $TMPDIR
        cp ${maniYaml} mani.yaml
        mani check
        mani list projects --color=false --output markdown > projects.md
        grep -qE '^\| *core *\| *nix *\|' projects.md
        grep -qE '^\| *docs *\|' projects.md
        grep -q 'sync_gitignore: false' mani.yaml
        touch $out
      '';

    checks.workspace-home = assert hmValid;
      pkgs.runCommand "agentic-workspace-home" {} "touch $out";
  };
}
