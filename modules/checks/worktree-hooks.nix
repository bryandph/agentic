# Fixture checks for creator-neutral hooks and the worktree setup script
# (tasks 4.2/4.3): a submodule repo gets the submodule init; a repo
# with a secret .env (the finance shape) copies .env per worktree.
# Neither shares devenv state, and both give linked worktrees their own
# hooks dir. The degrade diagnostic lives in the setup script BEFORE
# any artifact placement.
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
    mkFixture = module:
      inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [
          config.flake.flakeModules.default
          module
          ({config, ...}: {
            perSystem = {pkgs, ...}: {
              packages = {
                worktree-setup = config.agentic.worktreeLib.setupScript pkgs;
                worktree-hooks = config.agentic.worktreeLib.hooksScript pkgs;
              };
            };
          })
        ];
      };

    submoduleRepo = mkFixture {
      agentic.worktree.traits.submodules = true;
    };

    financeShape = mkFixture {
      agentic.worktree.traits.secretDotfiles = [".env"];
    };

    pkgOf = fixture: name: fixture.packages.${system}.${name};
    hooksHelper = pkgOf submoduleRepo "worktree-hooks";
  in {
    # A linked worktree of a SUBMODULE: the helper must move the shared
    # core.worktree into the main worktree's config.worktree before
    # enabling extensions.worktreeConfig, so both checkouts still resolve.
    checks.worktree-hooks =
      pkgs.runCommand "agentic-worktree-hooks" {
        nativeBuildInputs = [pkgs.git];
      } ''
        set -euo pipefail
        export HOME=$TMPDIR
        git config --global user.email t@example.invalid
        git config --global user.name t
        git config --global init.defaultBranch main
        git config --global protocol.file.allow always
        cd $TMPDIR
        git init -q sub && git -C sub commit -q --allow-empty -m init
        git init -q super && git -C super commit -q --allow-empty -m init
        git -C super submodule add -q "$TMPDIR/sub" sub
        git -C super commit -q -m add
        common="$(git -C super/sub rev-parse --path-format=absolute --git-common-dir)"
        git config --file "$common/config" --get core.worktree >/dev/null
        git -C super/sub worktree add -q --detach "$TMPDIR/sub-wt"

        # Main worktree: no-op.
        (cd super/sub && ${hooksHelper}/bin/agentic-worktree-hooks)
        ! git config --file "$common/config" --get extensions.worktreeConfig

        (cd sub-wt && ${hooksHelper}/bin/agentic-worktree-hooks)
        ! git config --file "$common/config" --get core.worktree
        git config --file "$common/config.worktree" --get core.worktree >/dev/null
        test "$(git config --file "$common/config" --get extensions.worktreeConfig)" = true
        wt_git="$(git -C sub-wt rev-parse --absolute-git-dir)"
        test "$(git -C sub-wt config --worktree --get core.hooksPath)" = "$wt_git/hooks"
        test "$(git -C sub-wt rev-parse --path-format=absolute --git-path hooks)" = "$wt_git/hooks"
        test "$(git -C super/sub rev-parse --show-toplevel)" = "$(cd super/sub && pwd -P)"
        test "$(git -C sub-wt rev-parse --show-toplevel)" = "$(cd sub-wt && pwd -P)"
        git -C super/sub status --short >/dev/null
        git -C super status --short >/dev/null
        test "$(git -C super/sub rev-parse --path-format=absolute --git-path hooks)" = "$common/hooks"

        # Idempotent.
        before="$(cat "$common/config" "$common/config.worktree")"
        (cd sub-wt && ${hooksHelper}/bin/agentic-worktree-hooks)
        test "$before" = "$(cat "$common/config" "$common/config.worktree")"
        touch $out
      '';

    checks.worktree-setup-script =
      pkgs.runCommand "agentic-worktree-setup-script" {
        nativeBuildInputs = [pkgs.gnugrep];
      } ''
        set -euo pipefail

        setup=${pkgOf submoduleRepo "worktree-setup"}/bin/workbench-worktree-setup
        test -x ${pkgOf submoduleRepo "worktree-setup"}/bin/agentic-worktree-setup

        # Submodule repo: init; per-worktree devenv state and hooks.
        grep -qF 'git submodule update --init' "$setup"
        ! grep -qF '.direnv" .direnv' "$setup"
        ! grep -qF '.devenv" .devenv' "$setup"
        grep -qF 'agentic-worktree-hooks' "$setup"
        # Legacy shared-state links are replaced on re-run.
        grep -qF '"$(readlink "$d")" = "$main_wt/$d"' "$setup"
        # Dev shell warmed once, outside any agent sandbox.
        grep -qF 'nix develop --impure -c true' "$setup"
        grep -qF 'devenv shell -- true' "$setup"
        # Degrade probe precedes artifact placement and names the
        # constraint + workaround.
        grep -qF 'nix flake metadata --json' "$setup"
        grep -qF 'worktree of a SUBMODULE' "$setup"
        grep -qF 'nix shell nixpkgs#<tool>' "$setup"

        # Finance shape: secret .env copied per worktree, no submodule
        # init, no shared devenv state, per-worktree hooks.
        fsetup=${pkgOf financeShape "worktree-setup"}/bin/agentic-worktree-setup
        ! grep -qF '.direnv" .direnv' "$fsetup"
        grep -qF 'agentic-worktree-hooks' "$fsetup"
        ! grep -qF 'git submodule update --init' "$fsetup"
        grep -qF ".env" "$fsetup"

        touch $out
      '';
  };
}
