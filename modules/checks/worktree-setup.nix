# Offline, isolated lifecycle fixtures. The creator invocation is copied from
# installed Herdr 0.9.5 src/worktree.rs::build_worktree_add_new_branch_command:
# git -C <repo> worktree add -b <branch> <path> <base> (no reset or recursion).
# All platforms use real metadata discovery in a private local store. Darwin
# models native warm-up with an explicit fixture stub (diverted builds are not
# supported there); Linux runs real nix develop with an input-free devShell.
{
  inputs,
  config,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    lib,
    ...
  }: let
    fixture = extra:
      inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [config.flake.flakeModules.default extra ({config, ...}: {flake.lib.fixture = config.agentic;})];
      };
    base = {
      workbench.worktree = {
        traits.submodules = true;
        traits.secretDotfiles = [".env"];
        setupHooks = [
          "printf 'first\\n' > setup-order"
          "test \"$(head -1 setup-order)\" = first; printf 'second\\n' >> setup-order"
        ];
        teardownHooks = [
          "test -f setup-order; echo verified: repository resources absent"
          "echo verified: second check"
        ];
      };
    };
    good = (fixture base).lib.fixture;
    changed =
      (fixture {
        imports = [base];
        agentic.worktree.copyFiles = lib.mkForce [];
      }).lib.fixture;
    failing =
      (fixture {
        imports = [base];
        agentic.worktree.setupHooks = lib.mkForce ["echo failing >&2; exit 9"];
      }).lib.fixture;
    noProof = (fixture {workbench.worktree.teardownHooks = ["echo complete"];}).lib.fixture;
    skipped = (fixture {workbench.worktree.teardownHooks = ["echo verified: checked; echo skipped: unavailable"];}).lib.fixture;
    badExit = (fixture {workbench.worktree.teardownHooks = ["echo verified: checked; exit 4"];}).lib.fixture;
    empty = (fixture {}).lib.fixture;
    shellClosure = pkgs.closureInfo {rootPaths = [pkgs.bashInteractive pkgs.coreutils];};
    # Darwin Nix cannot build in a diverted store. Keep real metadata discovery,
    # but model devenv's warm-up exit here; Linux exercises real nix develop.
    fixtureDevenv = pkgs.writeShellApplication {
      name = "devenv";
      runtimeInputs = [pkgs.nix];
      text = ''
        test "$*" = 'shell -- true'
        test "$(nix eval --raw .#fixtureWarmUp)" = ok
      '';
    };
    setup = "${good.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup";
    teardown = "${good.worktreeLib.teardownScript pkgs}/bin/workbench-worktree-teardown";
    compatible =
      good.workmux.traits
      == good.worktree.traits
      && good.workmux.copyFiles == good.worktree.copyFiles
      && good.workmuxLib.setupScript pkgs == good.worktreeLib.setupScript pkgs
      && good.workmuxLib.worktreeHooksScript pkgs == good.worktreeLib.hooksScript pkgs;
  in {
    checks.worktree-setup = assert compatible;
      pkgs.runCommand "workbench-worktree-setup-fixtures" {
        nativeBuildInputs = [pkgs.nix pkgs.git pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.bashInteractive] ++ lib.optional pkgs.stdenv.isDarwin fixtureDevenv;
      } ''
        set -euo pipefail
        fixture_root="$(mktemp -d)"
        trap 'chmod -R u+w "$fixture_root"; rm -rf "$fixture_root"' EXIT
        export TMPDIR="$fixture_root"
        export HOME=$TMPDIR/home XDG_CONFIG_HOME=$TMPDIR/xdg/config XDG_CACHE_HOME=$TMPDIR/xdg/cache \
          XDG_DATA_HOME=$TMPDIR/xdg/data XDG_STATE_HOME=$TMPDIR/xdg/state
        mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
        echo '{"flakes":[],"version":2}' > "$TMPDIR/registry.json"
        export NIX_CONFIG="experimental-features = nix-command flakes
        store = $TMPDIR/store
        substituters =
        flake-registry = $TMPDIR/registry.json
        use-registries = false
        warn-dirty = false
        sandbox = false"
        ${lib.optionalString pkgs.stdenv.isLinux ''
          # Import only local build dependencies, without a daemon connection.
          mkdir -p "$TMPDIR/store/nix/store"
          while IFS= read -r path; do cp -a "$path" "$TMPDIR/store/nix/store/"; done < ${shellClosure}/store-paths
          nix-store --load-db < ${shellClosure}/registration
        ''}
        git config --global user.name fixture
        git config --global user.email fixture@fixture.example
        git config --global init.defaultBranch main
        git config --global protocol.file.allow always
        git config --global submodule.recurse true
        cd "$TMPDIR"
        mkdir remotes
        publish() {
          git -C "$1" add -A
          git -C "$1" commit -qm fixture
          git clone -q --bare "$1" "$TMPDIR/remotes/$1.git"
        }
        git init -q inner
        echo nested-data > inner/data
        publish inner
        # No flake inputs and no network. Nix develop runs this minimal derivation
        # using only the closure imported above.
        write_flake() {
        cat > "$1/flake.nix" <<'EOF'
        { outputs = _: { fixtureWarmUp = "ok"; devShells.${system}.default = builtins.derivation {
          name = "fixture-shell";
          outputs = [ "out" ];
          system = "${system}";
          builder = (builtins.storePath "${pkgs.bashInteractive}") + "/bin/bash";
          args = [ "-c" "eval \"$buildCommand\"" ];
          buildCommand = "echo unused > $out";
          PATH = (builtins.storePath "${pkgs.coreutils}") + "/bin:" + (builtins.storePath "${pkgs.bashInteractive}") + "/bin";
          bashInteractive = (builtins.storePath "${pkgs.bashInteractive}") + "/bin/bash";
        }; }; }
        EOF
        ${lib.optionalString pkgs.stdenv.isDarwin "touch \"$1/devenv.nix\""}
        }
        git init -q sub
        git -C sub submodule add -q "$TMPDIR/remotes/inner.git" nested
        write_flake sub
        publish sub
        git init -q seed
        git -C seed submodule add -q "$TMPDIR/remotes/sub.git" sub
        write_flake seed
        publish seed
        git clone -q --recurse-submodules "$TMPDIR/remotes/seed.git" main
        git -C main config submodule.recurse true
        echo fixture-secret > main/.env
        echo fixture-envrc > main/.envrc
        mkdir -p main/.direnv main/.devenv
        echo preserved > main/.devenv/state
        # New-branch and existing-branch invocation, as installed Herdr builds them.
        git -C main worktree add -b fixture-one "$TMPDIR/one" main
        git -C main branch fixture-two main
        git -C main worktree add "$TMPDIR/two" fixture-two
        ln -s "$TMPDIR/main/.devenv" one/.devenv
        ln -s "$TMPDIR/main/.direnv" one/.direnv
        record() { printf '%s/workbench-setup.json' "$(git -C "$1" rev-parse --absolute-git-dir)"; }
        expect_code() {
          expected=$1; shift
          actual=0
          "$@" > "$TMPDIR/stdout" 2> "$TMPDIR/stderr" || actual=$?
          cat "$TMPDIR/stdout" "$TMPDIR/stderr"
          test "$actual" = "$expected"
        }
        expect_check() {
          expect_code "$1" ${setup} --check "$2"
          if [ "$1" != 0 ]; then
            test "$(wc -l < "$TMPDIR/stderr" | tr -d ' ')" = 1
            grep -F "$2" "$TMPDIR/stderr"
            grep -F 'run workbench-worktree-setup --worktree' "$TMPDIR/stderr"
          fi
        }
        expect_check 2 "$TMPDIR/one"
        # LAB-178 reproduction: a recursive reset before init creates a
        # config-only gitdir. Setup must preserve it and fail closed, not repair.
        LC_ALL=C git -C main worktree add -b fixture-bad "$TMPDIR/bad" main
        stub="$TMPDIR/main/.git/worktrees/bad/modules/sub"
        test ! -e bad/sub/.git
        test ! -e "$stub"
        expect_code 128 git -C bad reset --hard main
        test -f "$stub/config"
        test ! -e "$stub/HEAD"
        test ! -e "$stub/objects"
        test -f bad/sub/.git
        cp "$stub/config" stub-config-before
        cp bad/sub/.git stub-gitfile-before
        if git -C bad submodule update --init; then echo 'expected stub init failure' >&2; exit 1; fi
        expect_code 1 ${setup} --worktree "$TMPDIR/bad"
        test "$(wc -l < "$TMPDIR/stderr" | tr -d ' ')" = 1
        grep -F "submodule-stub at $stub" "$TMPDIR/stderr"
        grep -F 'backups outside the worktree' "$TMPDIR/stderr"
        jq -e '.status == "failed" and .failedStep == "submodule-stub" and .warmUp.status == "not-run"' "$(record bad)"
        expect_check 1 "$TMPDIR/bad"
        cmp "$stub/config" stub-config-before
        cmp bad/sub/.git stub-gitfile-before
        test ! -e "$stub/HEAD"
        test ! -e "$stub/objects"
        # Manual, data-preserving repair, exercised only on our owned fixture.
        mkdir saved-stub
        mv "$stub" saved-stub/gitdir
        mv bad/sub saved-stub/sub
        ${setup} --worktree "$TMPDIR/bad"
        expect_check 0 "$TMPDIR/bad"
        test "$(cat bad/sub/nested/data)" = nested-data
        # The good path initializes first, then a recursive reset works.
        ${setup} --worktree "$TMPDIR/one"
        expect_check 0 "$TMPDIR/one"
        jq -e '.status == "ok" and .failedStep == null and .warmUp == {status: "ok", exitCode: 0} and (.startedAt | endswith("Z")) and (.finishedAt | endswith("Z")) and (.setupCommand | startswith("/nix/store/"))' "$(record one)"
        git -C one reset --hard main
        test "$(cat one/sub/nested/data)" = nested-data
        git -C one/sub/nested status --short
        cmp main/.env one/.env
        test ! -L one/.env
        cmp main/.envrc one/.envrc
        test ! -e one/.devenv
        test ! -e one/.direnv
        test "$(cat main/.devenv/state)" = preserved
        test "$(cat one/setup-order)" = "$(printf 'first\nsecond')"
        (cd one && ${setup})
        (cd one && ${setup} --check)
        (cd one && ${good.worktreeLib.setupScript pkgs}/bin/agentic-worktree-setup --check)
        expect_check 0 "$TMPDIR/one"
        test "$(cat one/setup-order)" = "$(printf 'first\nsecond')"
        ${setup} --worktree "$TMPDIR/two"
        one_git=$(git -C one rev-parse --absolute-git-dir)
        two_git=$(git -C two rev-parse --absolute-git-dir)
        # A linked worktree of an initialized submodule exercises the double
        # gitdir indirection, including core.worktree migration and recursion.
        git -C two/sub worktree add -b linked-sub "$TMPDIR/linked-sub" HEAD
        ${setup} --worktree "$TMPDIR/linked-sub"
        expect_check 0 "$TMPDIR/linked-sub"
        test "$(cat linked-sub/nested/data)" = nested-data
        git -C two/sub status --short >/dev/null
        git -C linked-sub status --short >/dev/null
        test "$(git -C one config --worktree core.hooksPath)" = "$one_git/hooks"
        test "$(git -C two config --worktree core.hooksPath)" = "$two_git/hooks"
        mkdir -p "$one_git/hooks" "$two_git/hooks"
        printf '#!${pkgs.runtimeShell}\necho one-hook\n' > "$one_git/hooks/pre-commit"
        printf '#!${pkgs.runtimeShell}\necho two-hook\n' > "$two_git/hooks/pre-commit"
        chmod +x "$one_git/hooks/pre-commit" "$two_git/hooks/pre-commit"
        (cd one && ${teardown})
        expect_code 1 ${noProof.worktreeLib.teardownScript pkgs}/bin/workbench-worktree-teardown --worktree "$TMPDIR/one"
        grep -F 'teardownHooks[0] failed: missing verified:' "$TMPDIR/stderr"
        expect_code 1 ${skipped.worktreeLib.teardownScript pkgs}/bin/workbench-worktree-teardown --worktree "$TMPDIR/one"
        grep -F 'reported skipped' "$TMPDIR/stderr"
        expect_code 1 ${badExit.worktreeLib.teardownScript pkgs}/bin/workbench-worktree-teardown --worktree "$TMPDIR/one"
        grep -F 'exit 4' "$TMPDIR/stderr"
        ${empty.worktreeLib.teardownScript pkgs}/bin/workbench-worktree-teardown --worktree "$TMPDIR/one"
        test -d one
        # Changed implementation/configuration yields a different immutable store path.
        expect_code 3 ${changed.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --check "$TMPDIR/one"
        grep -F 'setup stale' "$TMPDIR/stderr"
        expect_code 9 ${failing.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/one"
        jq -e '.status == "failed" and .failedStep == "setupHooks[0]"' "$(record one)"
        expect_code 1 ${failing.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --check "$TMPDIR/one"
        ${setup} --worktree "$TMPDIR/one"
        # Broken metadata and explicit warm-up failure both persist failed results.
        cp two/flake.nix good-flake
        echo 'invalid nix !' > two/flake.nix
        expect_code 1 ${setup} --worktree "$TMPDIR/two"
        expect_check 1 "$TMPDIR/two"
        jq -e '.status == "failed" and .failedStep == "discovery" and .warmUp.status == "not-run"' "$(record two)"
        echo '{ outputs = _: {}; }' > two/flake.nix
        expect_code 1 ${setup} --worktree "$TMPDIR/two"
        jq -e '.status == "failed" and .failedStep == "warm-up" and .warmUp.status == "failed" and .warmUp.exitCode != 0' "$(record two)"
        cp good-flake two/flake.nix
        ${setup} --worktree "$TMPDIR/two"
        # Only disposable fixture files are removed here, never user resources.
        # Git refuses even a clean, deinitialized submodule worktree. Assert that
        # refusal preserves the tree. Only this sandbox-owned disposable fixture
        # is then force-removed, after a clean-status check (not product policy).
        ${teardown} --worktree "$TMPDIR/one"
        git -C one -c submodule.recurse=false submodule deinit --all
        rm one/.env one/.envrc one/setup-order
        test -z "$(git -C one status --porcelain)"
        expect_code 128 git -C main worktree remove "$TMPDIR/one"
        test -d one
        git -C main worktree remove --force "$TMPDIR/one"
        test "$(git -C two hook run pre-commit 2>&1)" = two-hook
        test "$(git -C main rev-parse --show-toplevel)" = "$TMPDIR/main"
        expect_check 0 "$TMPDIR/two"
        touch "$out"
      '';
  };
}
