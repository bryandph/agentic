# Checks for `workspace-overrides` (modules/workspace-overrides.nix).
#
#   * workspace-overrides-unit: URL normalisation, lock walking, URL and
#     alias matching and `--` insertion, as Python unit fixtures.
#   * workspace-overrides: end to end. Local bare repositories stand in
#     for the forge; a fixture consumer flake locks inputs to them; the
#     workspace checkouts carry uncommitted edits; Nix, running against a
#     store inside the build directory, evaluates the consumer with the
#     emitted arguments and must see the edits, and flake.lock must be
#     byte-identical afterwards.
#
# The end-to-end check is written for a strict Linux sandbox: own HOME and
# XDG directories, a local store, no substituters, no registries, and a
# consumer whose only inputs are the local bare repositories, so nothing
# needs nixpkgs or the network. Core has no CI: besides unsandboxed macOS
# runs, it passed once as checks.x86_64-linux on a sandbox = true Linux
# remote builder (2026-10-24, BPH-73). Rerun it there after changes.
#
# devenv is stubbed as in modules/checks/workspace.nix (copied, not shared).
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
    evalDevenv = extra:
      (lib.evalModules {
        modules = [
          devenvStubs
          {_module.args.pkgs = pkgs;}
          config.flake.devenvModules.workspace
          extra
        ];
      }).config;
    failedMessages = cfg: map (a: a.message) (lib.filter (a: !a.assertion) cfg.assertions);
    commandOf = cfg: lib.findFirst (p: p.name == "workspace-overrides") null cfg.packages;

    # The declaration under test, with placeholders for the sandbox
    # directories holding the stand-in forge and its mirror.
    fixture = evalDevenv {
      workbench.workspace = {
        remotes.local = {
          url = "file://@REMOTES@";
          aliases = ["file://@MIRROR@"];
        };
        repos = {
          core = {
            remote = "local";
            groups = ["nix"];
          };
          gone.remote = "local";
          subm.remote = "local";
          subrepo.remote = "local";
        };
        overrides.sub = "subrepo";
      };
    };
    empty = evalDevenv {};
    unknownKey = evalDevenv {
      workbench.workspace = {
        repos.a.url = "https://forge.fixture.example/a.git";
        overrides.x = "missing";
      };
    };

    moduleValid =
      commandOf fixture
      != null
      && failedMessages fixture == []
      && fixture.env ? WORKBENCH_WORKSPACE_OVERRIDES
      && commandOf empty == null
      && !(empty.env ? WORKBENCH_WORKSPACE_OVERRIDES)
      && lib.any (lib.hasInfix "workspace.overrides.x") (failedMessages unknownKey);
  in {
    checks.workspace-overrides-unit = pkgs.runCommand "agentic-workspace-overrides-unit" {nativeBuildInputs = [pkgs.python3 pkgs.git];} ''
      export HOME=$TMPDIR
      python3 -I ${./_fixtures/workspace-overrides-unit.py} ${../_workspace-overrides}
      touch $out
    '';

    checks.workspace-overrides = assert moduleValid;
      pkgs.runCommand "agentic-workspace-overrides" {nativeBuildInputs = [pkgs.nix pkgs.git pkgs.jq (commandOf fixture)];} ''
        set -euo pipefail
        export HOME=$TMPDIR/home XDG_CONFIG_HOME=$TMPDIR/xdg/config XDG_CACHE_HOME=$TMPDIR/xdg/cache \
          XDG_DATA_HOME=$TMPDIR/xdg/data XDG_STATE_HOME=$TMPDIR/xdg/state
        mkdir -p $HOME $XDG_CONFIG_HOME $XDG_CACHE_HOME $XDG_DATA_HOME $XDG_STATE_HOME
        echo '{"flakes":[],"version":2}' > $TMPDIR/registry.json
        export NIX_CONFIG="experimental-features = nix-command flakes
        store = $TMPDIR/store
        substituters =
        flake-registry = $TMPDIR/registry.json
        use-registries = false
        warn-dirty = false"
        git config --global user.name fixture
        git config --global user.email fixture@fixture.example
        git config --global init.defaultBranch main
        # Submodules of the fixture come from local bare repositories.
        git config --global protocol.file.allow always

        remotes=$TMPDIR/remotes mirror=$TMPDIR/mirror ws=$TMPDIR/ws r=$TMPDIR/results
        mkdir -p $remotes $mirror $ws $r
        publish() { # <name>: commit the seed tree in $TMPDIR/seed-<name> to the forge
          git -C $TMPDIR/seed-$1 init -q
          git -C $TMPDIR/seed-$1 add -A
          git -C $TMPDIR/seed-$1 commit -qm init
          git clone -q --bare $TMPDIR/seed-$1 $remotes/$1.git
        }
        mkdir -p $TMPDIR/seed-{gone,inner,subrepo,core,subm}
        echo '{ outputs = _: { value = "gone"; }; }' > $TMPDIR/seed-gone/flake.nix
        publish gone
        echo inner-committed > $TMPDIR/seed-inner/data
        publish inner
        echo '{ outputs = _: { value = "subrepo-committed"; }; }' > $TMPDIR/seed-subrepo/flake.nix
        publish subrepo
        cat > $TMPDIR/seed-core/flake.nix <<EOF
        {
          inputs.dep.url = "git+file://$remotes/gone.git";
          outputs = { dep, ... }: { value = import ./value.nix; seesNew = builtins.pathExists ./new.nix; dep = dep.value; };
        }
        EOF
        echo '"core-committed"' > $TMPDIR/seed-core/value.nix
        publish core
        git clone -q --bare $remotes/core.git $mirror/core.git
        echo '{ outputs = _: { value = builtins.readFile ./inner/data; }; }' > $TMPDIR/seed-subm/flake.nix
        git -C $TMPDIR/seed-subm init -q
        git -C $TMPDIR/seed-subm submodule -q add $remotes/inner.git inner
        publish subm

        # The consumer: a forge URL, the same repository through its mirror,
        # a nested input that follows a root input, a repository with no
        # checkout, a submodule-bearing one and a relative path input.
        consumer=$TMPDIR/consumer
        mkdir -p $consumer/sub
        echo '{ outputs = _: { value = "sub-in-consumer"; }; }' > $consumer/sub/flake.nix
        cat > $consumer/flake.nix <<EOF
        {
          inputs = {
            core.url = "git+file://$remotes/core.git";
            core.inputs.dep.follows = "gone";
            viaMirror.url = "git+file://$mirror/core.git";
            gone.url = "git+file://$remotes/gone.git";
            subm.url = "git+file://$remotes/subm.git?submodules=1";
            sub.url = "path:./sub";
          };
          outputs = { core, viaMirror, gone, subm, sub, ... }: {
            result = {
              core = core.value;
              seesNew = core.seesNew;
              dep = core.dep;
              mirror = viaMirror.value;
              gone = gone.value;
              subm = subm.value;
              sub = sub.value;
            };
          };
        }
        EOF
        git -C $consumer init -q
        git -C $consumer add -A
        (cd $consumer && nix flake lock)
        git -C $consumer add flake.lock
        git -C $consumer commit -qm consumer
        lockBefore=$(sha256sum < $consumer/flake.lock)
        (cd $consumer && nix eval --json .#result) > $r/baseline.json
        jq -e '.core == "core-committed" and .sub == "sub-in-consumer" and .subm == "inner-committed\n"' $r/baseline.json

        # Checkouts with uncommitted edits to tracked files; `gone` has none.
        git clone -q $remotes/core.git $ws/core
        echo '"core-edited"' > $ws/core/value.nix
        echo '{}' > $ws/core/new.nix
        git clone -q $remotes/subrepo.git $ws/subrepo
        echo '{ outputs = _: { value = "subrepo-edited"; }; }' > $ws/subrepo/flake.nix
        git clone -q --recurse-submodules $remotes/subm.git $ws/subm
        echo inner-edited > $ws/subm/inner/data

        substitute ${fixture.env.WORKBENCH_WORKSPACE_MANIFEST} manifest.json \
          --replace-fail @REMOTES@ $remotes --replace-fail @MIRROR@ $mirror
        export WORKBENCH_WORKSPACE_MANIFEST=$PWD/manifest.json
        export WORKBENCH_WORKSPACE_OVERRIDES=${fixture.env.WORKBENCH_WORKSPACE_OVERRIDES}
        export DEVENV_ROOT=$ws

        cd $consumer
        workspace-overrides > $TMPDIR/args 2> $TMPDIR/report
        cat $TMPDIR/args $TMPDIR/report
        args=$(cat $TMPDIR/args)
        test "$args" = "--override-input core git+file://$ws/core --override-input sub git+file://$ws/subrepo --override-input subm 'git+file://$ws/subm?submodules=1' --override-input viaMirror git+file://$ws/core --no-write-lock-file"
        grep -q "override core -> core at git+file://$ws/core (url " $TMPDIR/report
        grep -q "override viaMirror -> core" $TMPDIR/report
        grep -q "override sub -> subrepo at git+file://$ws/subrepo (mapped by declaration)" $TMPDIR/report
        grep -q "skip gone: matched gone .* checkout $ws/gone does not exist" $TMPDIR/report
        if grep -q "core/dep" $TMPDIR/args; then exit 1; fi
        grep -q "git add -N" $TMPDIR/report

        evalWith() { eval "set -- $1"; nix eval --json .#result "$@"; }
        evalWith "$args" > $r/edited.json
        jq -e '. == {core: "core-edited", seesNew: false, dep: "gone", mirror: "core-edited", gone: "gone", subm: "inner-edited\n", sub: "subrepo-edited"}' $r/edited.json

        # --scheme path carries untracked files; --checkout and --only.
        evalWith "$(workspace-overrides --scheme path --only core 2>/dev/null)" > $r/path.json
        jq -e '.seesNew == true and .sub == "sub-in-consumer" and .subm == "inner-committed\n"' $r/path.json
        git -C $ws/core worktree add -q -b side $TMPDIR/core-wt
        echo '"core-worktree"' > $TMPDIR/core-wt/value.nix
        evalWith "$(workspace-overrides --checkout core=$TMPDIR/core-wt --only nix 2>/dev/null)" > $r/wt.json
        jq -e '.core == "core-worktree" and .mirror == "core-worktree" and .sub == "sub-in-consumer"' $r/wt.json
        # --map on the command line wins over the declaration.
        test "$(workspace-overrides --map sub=core --only core 2>/dev/null)" = "--override-input core git+file://$ws/core --override-input sub git+file://$ws/core --override-input viaMirror git+file://$ws/core --no-write-lock-file"

        # Exec mode inserts the arguments after the subcommand and refuses
        # anything that is not a supported nix command.
        workspace-overrides -- nix eval --json .#result > $r/exec.json
        cmp $r/exec.json $r/edited.json
        if workspace-overrides -- echo hi 2> $r/refused; then exit 1; fi
        grep -q "refusing to run 'echo'" $r/refused
        if workspace-overrides -- nix flake lock 2> $r/refused; then exit 1; fi
        grep -q "refusing .nix flake lock" $r/refused

        test "$(sha256sum < flake.lock)" = "$lockBefore"
        test -z "$(git -C $consumer status --porcelain)"
        touch $out
      '';
  };
}
