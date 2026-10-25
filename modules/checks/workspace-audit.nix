# Fixture check for `workspace-audit`. devenv is stubbed as in
# checks/workspace.nix; the command and the resolved manifest come from
# evaluating the exported workspace devenv module, and the audit runs over
# a sandbox tree of local repositories whose origins use fixture hosts.
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
        # lazyAttrsOf, as devenv declares it: a key under a false mkIf stays
        # present and throws when read, which attrsOf would hide.
        env = lib.mkOption {
          type = lib.types.lazyAttrsOf lib.types.anything;
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
    evalDevenv = extra:
      (lib.evalModules {
        modules = [
          devenvStubs
          {_module.args.pkgs = pkgs;}
          config.flake.devenvModules.workspace
          extra
        ];
      }).config;

    fixture = evalDevenv {
      workbench.workspace = {
        remotes.team = {
          url = "https://forge.fixture.example/team";
          aliases = ["git@mirror.fixture.example:team"];
        };
        repos = {
          good.remote = "team";
          mirrored.remote = "team";
          nested = {
            remote = "team";
            path = "area/nested";
          };
          absent.remote = "team";
          drifted.remote = "team";
        };
        audit.ignore = ["scratch"];
      };
    };
    empty = evalDevenv {};
    audit = lib.findFirst (p: p.name == "workspace-audit") (throw "workspace-audit is not in the shell") fixture.packages;
    manifest = fixture.env.WORKBENCH_WORKSPACE_MANIFEST;

    # Exactly these findings; everything else in the tree is in order.
    expected = [
      {
        kind = "missing";
        key = "absent";
        path = "absent";
      }
      {
        kind = "origin";
        key = "drifted";
        path = "drifted";
        origin = "https://elsewhere.fixture.example/team/drifted.git";
        expected = ["https://forge.fixture.example/team/drifted.git" "git@mirror.fixture.example:team/drifted.git"];
      }
      {
        kind = "undeclared";
        key = null;
        path = "stray";
      }
    ];
    # The same tree with `good` stripped of its repository: a plain
    # directory inside the workspace repository.
    expectedPlain =
      lib.take 2 expected
      ++ [
        {
          kind = "not-a-repo";
          key = "good";
          path = "good";
        }
      ]
      ++ lib.drop 2 expected;
  in {
    checks.workspace-audit = assert empty.packages == [];
      pkgs.runCommand "agentic-workspace-audit" {nativeBuildInputs = [audit pkgs.git pkgs.jq];} ''
        set -euo pipefail
        export HOME=$TMPDIR
        git config --global user.name fixture
        git config --global user.email fixture@fixture.example
        git config --global init.defaultBranch main
        export WORKBENCH_WORKSPACE_MANIFEST=${manifest}

        ws=$TMPDIR/ws
        mkdir -p $ws
        checkout() {
          git init -q "$ws/$1"
          echo "$1" > "$ws/$1/README"
          git -C "$ws/$1" add README
          git -C "$ws/$1" commit -qm init
          git -C "$ws/$1" remote add origin "$2"
        }
        # The workspace root is itself a repository tracking scaffolding.
        git init -q $ws
        printf '*\n!.gitignore\n!flake.nix\n' > $ws/.gitignore
        touch $ws/flake.nix
        git -C $ws add .gitignore flake.nix
        git -C $ws commit -qm scaffolding
        checkout good https://forge.fixture.example/team/good.git
        checkout mirrored git@mirror.fixture.example:team/mirrored.git
        checkout area/nested https://forge.fixture.example/team/nested.git
        checkout drifted https://elsewhere.fixture.example/team/drifted.git
        # A worktree under the shared root, shell state, an ignored
        # scratch directory and one nobody declared.
        mkdir -p $ws/.worktrees/good
        git -C $ws/good worktree add -q -b side $ws/.worktrees/good/side
        mkdir -p $ws/.direnv $ws/scratch $ws/stray
        # Leave unstaged edits so an index refresh would have work to do.
        echo edited >> $ws/good/README
        echo edited >> $ws/drifted/README

        treehash() {
          (
            cd "$1"
            find . -print0 | sort -z | xargs -0 stat -c '%N %F %a %s %.9Y'
            find . -type f -print0 | sort -z | xargs -0 sha256sum
          ) | sha256sum
        }
        before=$(treehash $ws)

        cd $ws
        workspace-audit --help
        workspace-audit | tee $TMPDIR/human
        workspace-audit --json > $TMPDIR/found.json
        status=0; workspace-audit --strict > /dev/null || status=$?
        test "$status" = 1
        cd $TMPDIR
        workspace-audit --root $ws --json > $TMPDIR/rooted.json
        # Inside the workspace shell the root defaults to $DEVENV_ROOT,
        # wherever the command runs; --root still wins.
        DEVENV_ROOT=$ws workspace-audit --json > $TMPDIR/shell.json
        DEVENV_ROOT=$TMPDIR workspace-audit --root $ws --json > $TMPDIR/shell-rooted.json

        after=$(treehash $ws)
        test "$before" = "$after"

        jq -e --argjson want ${lib.escapeShellArg (builtins.toJSON expected)} '.findings == $want' $TMPDIR/found.json
        jq -e --argjson want ${lib.escapeShellArg (builtins.toJSON expected)} '.findings == $want' $TMPDIR/rooted.json
        jq -e --argjson want ${lib.escapeShellArg (builtins.toJSON expected)} --arg root $ws '.findings == $want and .root == $root' $TMPDIR/shell.json
        jq -e --argjson want ${lib.escapeShellArg (builtins.toJSON expected)} '.findings == $want' $TMPDIR/shell-rooted.json
        test "$(grep -c '^missing \|^origin \|^undeclared ' $TMPDIR/human)" = 3
        grep -q '^3 finding(s)' $TMPDIR/human

        # Not a repository, without the tree changing either.
        cp -a $ws $TMPDIR/plain
        rm -rf $TMPDIR/plain/good/.git
        before=$(treehash $TMPDIR/plain)
        workspace-audit --root $TMPDIR/plain --json > plain.json
        test "$before" = "$(treehash $TMPDIR/plain)"
        jq -e --argjson want ${lib.escapeShellArg (builtins.toJSON expectedPlain)} '.findings == $want' plain.json

        # Ignoring from the command line; strict passes on a clean tree.
        rm -rf $TMPDIR/clean; cp -a $ws $TMPDIR/clean
        mkdir $TMPDIR/clean/absent
        git -C $TMPDIR/clean/absent init -q
        git -C $TMPDIR/clean/absent remote add origin https://forge.fixture.example/team/absent.git
        git -C $TMPDIR/clean/drifted remote set-url origin https://forge.fixture.example/team/drifted.git/
        workspace-audit --root $TMPDIR/clean --strict --ignore stray | grep -q 'matches the declaration'

        # Without a manifest the command refuses with a usage error.
        status=0; env -u WORKBENCH_WORKSPACE_MANIFEST workspace-audit 2> err || status=$?
        test "$status" = 2
        grep -q 'WORKBENCH_WORKSPACE_MANIFEST' err
        touch $out
      '';
  };
}
