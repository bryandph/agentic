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
    flakeShell =
      (fixture {
        imports = [base];
        agentic.worktree.shell.kind = "flake";
      }).lib.fixture;
    requiredShell =
      (fixture {
        imports = [base];
        agentic.worktree.shell = {
          kind = "flake";
          required = true;
        };
      }).lib.fixture;
    absentShell =
      (fixture {
        agentic.worktree.shell = {
          kind = "flake";
          attr = "absent";
        };
      }).lib.fixture;
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
    globs =
      (fixture {
        agentic.worktree.copyFiles = [".env.*" "config/*.local" "missing/*.local" "space dir/*.local"];
        agentic.worktree.traits.secretDotfiles = ["secrets/*.env"];
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
  in {
    checks.worktree-setup =
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
        # Globs expand against main, preserve nested/spaced paths, and never
        # replace existing files. A no-match pattern is harmless.
        mkdir -p main/config main/secrets "main/space dir" two/config
        echo dotenv > main/.env.fixture
        echo source > main/config/keep.local
        echo nested > main/config/new.local
        echo secret > main/secrets/token.env
        echo spaced > "main/space dir/name with spaces.local"
        echo existing > two/config/keep.local
        ${globs.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/two"
        cmp main/.env.fixture two/.env.fixture
        cmp main/config/new.local two/config/new.local
        cmp main/secrets/token.env two/secrets/token.env
        cmp "main/space dir/name with spaces.local" "two/space dir/name with spaces.local"
        test "$(cat two/config/keep.local)" = existing
        test ! -e two/missing
        jq -e '.status == "ok" and .failedStep == null' "$(git -C two rev-parse --absolute-git-dir)/workbench-setup.json"
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
        expect_code 2 ${setup} --check --json "$TMPDIR/one"
        jq -e '. == {status: "missing", code: 2, digest: null, record: null}' "$TMPDIR/stdout"
        # Worker-start must use this consumer's setup, even in a shell with
        # no sibling executable on PATH and an inherited foreign override.
        ! command -v workbench-worktree-setup
        export AGENTIC_WORKTREE_SETUP=/nonexistent/foreign-setup
        expect_code 30 ${good.worktreeLib.workerStartScript pkgs}/bin/workbench-worker-start \
          --pane fixture --worktree "$TMPDIR/one" -- launcher
        jq -e '.status == "setup-failed" and (.diagnostics | contains("setup missing"))' "$TMPDIR/stdout"
        # Not applicable: the main checkout and a directory outside any
        # repository get exit 4 and no advice to run setup.
        mkdir "$TMPDIR/plain"
        for na in "$TMPDIR/main" "$TMPDIR/plain"; do
          expect_code 4 ${setup} --check "$na"
          test "$(wc -l < "$TMPDIR/stderr" | tr -d ' ')" = 1
          grep -F 'worktree setup does not apply' "$TMPDIR/stderr"
          ! grep -F 'run workbench-worktree-setup' "$TMPDIR/stderr"
          expect_code 4 ${setup} --check --json "$na"
          jq -e '. == {status: "not-applicable", code: 4, digest: null, record: null}' "$TMPDIR/stdout"
        done
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
        # Matching configured setup gets past preflight (Herdr is deliberately
        # absent); a different configured setup sees the record as stale.
        expect_code 20 ${good.worktreeLib.workerStartScript pkgs}/bin/workbench-worker-start \
          --pane fixture --worktree "$TMPDIR/one" -- launcher
        jq -e '.status == "launch-failed"' "$TMPDIR/stdout"
        expect_code 30 ${changed.worktreeLib.workerStartScript pkgs}/bin/workbench-worker-start \
          --pane fixture --worktree "$TMPDIR/one" -- launcher
        jq -e '.status == "setup-failed" and (.diagnostics | contains("setup stale"))' "$TMPDIR/stdout"
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
        # Reproduce a parent-owned shared core.worktree with the extension
        # already enabled, and create via gitdir just like submodule tooling.
        sub_common="$(git -C two/sub rev-parse --absolute-git-dir)"
        git config --file "$sub_common/config" extensions.worktreeConfig true
        git --git-dir "$sub_common" worktree add -b linked-sub "$TMPDIR/linked-sub" HEAD
        # Depending on the depth of the gitdir, the inherited relative value
        # either resolves elsewhere or fails because its destination is absent.
        before_top="$(git -C linked-sub rev-parse --show-toplevel 2>/dev/null || true)"
        test "$before_top" != "$TMPDIR/linked-sub"
        ${setup} --worktree "$TMPDIR/linked-sub"
        expect_check 0 "$TMPDIR/linked-sub"
        test "$(git -C linked-sub rev-parse --show-toplevel)" = "$TMPDIR/linked-sub"
        git -C two submodule sync --recursive
        git -C two submodule update --init --recursive
        test "$(git -C linked-sub rev-parse --show-toplevel)" = "$TMPDIR/linked-sub"
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
        # v1 is stale even when it names the current setup command.
        jq 'del(.schema)' "$(record two)" > legacy
        cp legacy "$(record two)"
        expect_check 3 "$TMPDIR/two"
        expect_code 3 ${setup} --check --json "$TMPDIR/two"
        jq -e '.status == "stale" and .code == 3 and (.record | has("schema") | not)' "$TMPDIR/stdout"
        printf 'malformed {' > "$(record two)"
        expect_code 1 ${setup} --check --json "$TMPDIR/two"
        jq -e '.status == "failed" and .code == 1 and .record == null and (.digest | length == 64)' "$TMPDIR/stdout"
        # Auto none: shell steps do not apply, but ordinary setup still runs.
        cp two/flake.nix good-flake
        rm two/flake.nix
        rm -f two/devenv.nix
        ${setup} --worktree "$TMPDIR/two"
        jq -e '.schema == "workbench.worktree-setup/2" and .status == "ok" and ([.steps[] | select(.name == "discovery" or .name == "warm-up") | .outcome] == ["not-applicable", "not-applicable"])' "$(record two)"
        cp good-flake two/flake.nix
        ${absentShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/two"
        jq -e '.status == "ok" and (.steps[] | select(.name == "warm-up") | .applies == false and (.reason | contains("absent")))' "$(record two)"
        # Missing devShells entirely is also not-applicable.
        echo '{ outputs = _: {}; }' > two/flake.nix
        ${flakeShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/two"
        jq -e '.status == "ok" and (.steps[] | select(.name == "warm-up") | .outcome == "not-applicable")' "$(record two)"
        # Successful metadata discovery does not imply shell-name eval works.
        # Probe errors must retain stderr, never masquerade as absent shells.
        echo '{ outputs = _: throw "fixture probe eval failure"; }' > two/flake.nix
        rm two/setup-order
        ${flakeShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/two" > "$TMPDIR/stdout" 2> "$TMPDIR/stderr"
        grep -F 'fixture probe eval failure' "$TMPDIR/stderr"
        jq -e '.status == "degraded" and (.steps[] | select(.name == "discovery") | .outcome == "ok") and (.steps[] | select(.name == "warm-up") | .applies == true and .outcome == "failed" and (.message | contains("fixture probe eval failure")))' "$(record two)"
        test "$(cat two/setup-order)" = "$(printf 'first\nsecond')"
        rm two/setup-order
        expect_code 1 ${requiredShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/two"
        test ! -e two/setup-order
        jq -e '.status == "failed" and .failedStep == "warm-up" and (.steps[-1] | .applies == true and .required == true and .outcome == "failed" and (.message | contains("fixture probe eval failure")))' "$(record two)"
        # BPH-66: old libgit2 rejects the repo-wide relativeWorktrees extension.
        # Fake only Nix, before the real binary on PATH, for each failing call.
        mkdir "$TMPDIR/fake-nix"
        cat > "$TMPDIR/fake-nix/nix" <<'EOF'
        #!${pkgs.runtimeShell}
        set -eu
        fail() {
          for i in $(seq 1 30); do echo "older diagnostic $i" >&2; done
          echo 'error: unsupported extension name ExTeNsIoNs.ReLaTiVeWoRkTrEeS' >&2
          exit 1
        }
        case "$*" in
          --version) echo 'nix (Nix) 2.34.7';;
          'flake metadata --json')
            if [ "$NIX_FAIL_AT" = discovery ]; then fail; fi;;
          'eval --impure --raw --expr builtins.currentSystem')
            if [ "$NIX_FAIL_AT" = system ]; then fail; fi
            echo '${system}';;
          'eval --json --impure --expr '*)
            if [ "$NIX_FAIL_AT" = probe ]; then fail; fi
            echo '["default"]';;
          'develop '*) fail;;
          *) echo "unexpected fixture nix call: $*" >&2; exit 99;;
        esac
        EOF
        chmod +x "$TMPDIR/fake-nix/nix"
        real_path="$PATH"
        export PATH="$TMPDIR/fake-nix:$PATH"
        for NIX_FAIL_AT in discovery system probe warm-up; do
          export NIX_FAIL_AT
          blocked_step=warm-up
          if [ "$NIX_FAIL_AT" = discovery ]; then blocked_step=discovery; fi
          for required in false true; do
            blocked_setup=${flakeShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup
            blocked_start=${flakeShell.worktreeLib.workerStartScript pkgs}/bin/workbench-worker-start
            if "$required"; then
              blocked_setup=${requiredShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup
              blocked_start=${requiredShell.worktreeLib.workerStartScript pkgs}/bin/workbench-worker-start
            fi
            rm -f two/setup-order
            expect_code 6 "$blocked_setup" --worktree "$TMPDIR/two"
            test ! -e two/setup-order
            jq -e --arg step "$blocked_step" --argjson required "$required" '
              .status == "blocked" and .failedStep == $step and
              (.steps[-1] | .name == $step and .outcome == "blocked" and .required == $required and .exitCode == 1) and
              ([.steps[] | select(.name | startswith("setupHooks"))] | length == 0) and
              (.blocker | .kind == "environment" and .code == "nix-relativeworktrees" and .step == $step and
                .nixVersion == "nix (Nix) 2.34.7" and (.detail | contains("ExTeNsIoNs.ReLaTiVeWoRkTrEeS")) and
                (.detail | length <= 2048) and (.detail | split("\n") | length <= 20) and
                (.remediation | contains("absolute links") and contains("operator cleanup") and contains("nix >= 2.34.9")))' "$(record two)"
            expect_code 6 "$blocked_setup" --check "$TMPDIR/two"
            expect_code 6 "$blocked_setup" --check --json "$TMPDIR/two"
            jq -e '.status == "blocked" and .code == 6 and .record.blocker.code == "nix-relativeworktrees" and (.digest | length == 64)' "$TMPDIR/stdout"
            blocked_digest="$(jq -r .digest "$TMPDIR/stdout")"
            expect_code 32 "$blocked_start" --pane fixture --worktree "$TMPDIR/two" -- launcher
            jq -e '.status == "setup-blocked" and (has("setupOverride") | not)' "$TMPDIR/stdout"
            expect_code 32 "$blocked_start" --pane fixture --worktree "$TMPDIR/two" \
              --accept-setup "$blocked_digest" --reason 'reviewed but not overridable' -- launcher
            jq -e '.status == "setup-blocked" and (.reason | contains("cannot override")) and (has("setupOverride") | not)' "$TMPDIR/stdout"
          done
        done
        cp "$(record two)" "$TMPDIR/blocked-sample.json"
        export PATH="$real_path"
        unset NIX_FAIL_AT
        # Broken discovery degrades by default and still runs ordered hooks.
        echo 'invalid nix !' > two/flake.nix
        rm -f two/setup-order
        ${flakeShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/two"
        expect_code 5 ${flakeShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --check --json "$TMPDIR/two"
        jq -e '.status == "degraded" and .code == 5 and (.digest | length == 64) and (.record.steps[] | select(.name == "discovery") | .message | contains("nix flake discovery failed"))' "$TMPDIR/stdout"
        test "$(cat two/setup-order)" = "$(printf 'first\nsecond')"
        rm two/setup-order
        expect_code 1 ${requiredShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/two"
        test ! -e two/setup-order
        jq -e '.status == "failed" and .failedStep == "discovery" and .warmUp.status == "not-run" and (.steps[-1] | .name == "discovery" and .required == true and .outcome == "failed" and (.message | contains("nix flake discovery failed")))' "$(record two)"
        echo '{ outputs = _: { devShells.${system}.default = throw "fixture warm-up failure"; }; }' > two/flake.nix
        ${flakeShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/two"
        jq -e '.status == "degraded" and (.steps[] | select(.name == "warm-up") | .outcome == "failed" and .required == false)' "$(record two)"
        test "$(cat two/setup-order)" = "$(printf 'first\nsecond')"
        cp "$(record two)" "$TMPDIR/degraded-sample.json"
        cat "$TMPDIR/degraded-sample.json"
        expect_code 5 ${flakeShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --check --json "$TMPDIR/two"
        test "$(jq -r .digest "$TMPDIR/stdout")" = "$(sha256sum "$(record two)" | cut -d ' ' -f 1)"
        # A required hook failure wins over an earlier non-required failure.
        expect_code 9 ${failing.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/two"
        jq -e '.status == "failed" and .failedStep == "setupHooks[0]" and (.steps[-1] | .name == "setupHooks[0]" and .required == true and .exitCode == 9)' "$(record two)"
        rm two/setup-order
        expect_code 1 ${requiredShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --worktree "$TMPDIR/two"
        test ! -e two/setup-order
        jq -e '.status == "failed" and .failedStep == "warm-up" and .warmUp.status == "failed" and .warmUp.exitCode != 0 and (.steps[-1] | .name == "warm-up" and .required == true and .outcome == "failed")' "$(record two)"
        expect_code 1 ${requiredShell.worktreeLib.setupScript pkgs}/bin/workbench-worktree-setup --check --json "$TMPDIR/two"
        jq -e '.status == "failed" and .code == 1 and .record.status == "failed"' "$TMPDIR/stdout"
        cp good-flake two/flake.nix
        ${lib.optionalString pkgs.stdenv.isDarwin "touch two/devenv.nix"}
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
        mkdir "$out"
        cp "$TMPDIR/degraded-sample.json" "$out/degraded-sample.json"
        cp "$TMPDIR/blocked-sample.json" "$out/blocked-sample.json"
      '';
  };
}
