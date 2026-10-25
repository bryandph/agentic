# Fixture check for the `workspace` template (design D8). devenv is not
# pinned by core, so the template's flake.nix is evaluated with a stand-in
# for devenv's flakeModule whose shells are the same devenv option stubs
# as checks/workspace.nix, and with core itself substituted for the
# `workbench` input. The instantiated copy is then a git repository whose
# allowlist must keep everything but the scaffolding out.
{
  inputs,
  config,
  ...
}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    templateDir = ../../templates/workspace;

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
        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {};
        };
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [];
        };
        warnings = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };
      };
    };
    # Stands in for devenv's flakeModule: `devenv.shells.<name>` evaluated
    # over the stubs, exposed through legacyPackages for inspection.
    devenvFlakeModule = {flake-parts-lib, ...}: {
      options.perSystem = flake-parts-lib.mkPerSystemOption ({pkgs, ...}: {
        options.devenv.shells = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submoduleWith {
            modules = [devenvStubs {_module.args.pkgs = pkgs;}];
          });
          default = {};
        };
      });
      config.perSystem = {config, ...}: {
        legacyPackages.devenvShells = config.devenv.shells;
      };
    };

    template = import (templateDir + "/flake.nix");
    templateInputs = {
      inherit (inputs) nixpkgs flake-parts;
      devenv.flakeModule = devenvFlakeModule;
      workbench = inputs.self;
    };
    outputs = template.outputs (templateInputs
      // {
        self =
          outputs
          // {
            outPath = templateDir;
            inputs = templateInputs;
          };
      });
    shell = outputs.legacyPackages.${system}.devenvShells.default;

    # Evaluates, declares nothing and therefore renders nothing.
    evaluatesEmpty =
      lib.attrNames template.inputs
      == lib.attrNames templateInputs
      && toString config.flake.templates.workspace.path == toString templateDir
      && shell.workbench.workspace.repos == {}
      && shell.workbench.workspace.remotes == {}
      && shell.workbench.workspace.resolved == []
      && shell.files == {}
      && shell.packages == []
      && shell.env == {}
      && shell.warnings == []
      && lib.all (a: a.assertion) shell.assertions;
  in {
    checks.workspace-template = assert evaluatesEmpty;
      pkgs.runCommand "agentic-workspace-template" {nativeBuildInputs = [pkgs.git pkgs.gnugrep];} ''
        set -euo pipefail
        export HOME=$TMPDIR
        git config --global user.name fixture
        git config --global user.email fixture@fixture.example
        git config --global init.defaultBranch main

        # No environment hosts: only the placeholder core URL and public
        # flake inputs. Bracket classes keep this file out of its own scan.
        if grep -rniE '[.]bph\b|git[.]bph|bryan[d]ph|you[t]rack' ${templateDir}; then
          echo "environment identifier in the workspace template"
          exit 1
        fi
        grep -q 'url = "github:OWNER/agentic"' ${templateDir}/flake.nix
        grep -qx 'use flake . --no-pure-eval' ${templateDir}/.envrc

        # Instantiate as `nix flake init -t` does: copy the files.
        ws=$TMPDIR/ws
        mkdir $ws
        cp -r ${templateDir}/. $ws
        chmod -R u+w $ws
        cd $ws
        git init -q

        scaffolding=$(printf '%s\n' '?? .envrc' '?? .gitignore' '?? flake.nix')
        test "$(git status --porcelain --untracked-files=all)" = "$scaffolding"

        # The lock is the instance's own and is tracked once it exists.
        echo '{}' > flake.lock
        scaffolding=$(printf '%s\n' '?? .envrc' '?? .gitignore' '?? flake.lock' '?? flake.nix')

        # Checkouts at the root and under an area folder, a worktree under
        # the shared root, a plain directory, the rendered manifest and
        # shell state: none of it shows up.
        nested() {
          git init -q "$1"
          echo "$1" > "$1/README"
          git -C "$1" add README
          git -C "$1" commit -qm init
        }
        nested tool
        nested apps/web
        mkdir -p .worktrees/tool
        git -C tool worktree add -q -b side $ws/.worktrees/tool/side
        mkdir -p notes .direnv .devenv
        echo note > notes/todo
        echo 'projects: {}' > mani.yaml
        touch .devenv/state .direnv/env
        test "$(git status --porcelain --untracked-files=all)" = "$scaffolding"

        git add -A
        test "$(git ls-files)" = "$(printf '%s\n' .envrc .gitignore flake.lock flake.nix)"
        touch $out
      '';
  };
}
