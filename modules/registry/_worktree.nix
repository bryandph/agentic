# Creator-neutral preparation and verified cleanup. Herdr owns creation/removal;
# this module owns only repository setup, its result, and repository hooks.
{
  lib,
  config,
  ...
}: let
  cfg = config.agentic.worktree;
  hook = pkgs: phase: index: command:
    pkgs.writeShellApplication {
      name = "workbench-worktree-${phase}-hook-${toString index}";
      text = command;
    };
  arguments = ''
    worktree="$PWD"
    if [ "''${1:-}" = --worktree ]; then
      [ "$#" = 2 ] || { echo 'expected --worktree <path>' >&2; exit 64; }
      worktree="$2"
    elif [ "$#" != 0 ]; then
      echo 'expected [--worktree <path>]' >&2
      exit 64
    fi
    cd -- "$worktree"
    worktree="$PWD"
  '';

  hooksScript = pkgs:
    pkgs.writeShellApplication {
      name = "agentic-worktree-hooks";
      runtimeInputs = [pkgs.git];
      text = ''
        git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
        common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
        [ "$git_dir" != "$common_dir" ] || exit 0
        if [ "$(git config --file "$common_dir/config" --get extensions.worktreeConfig || true)" != true ]; then
          for key in core.worktree core.bare; do
            value="$(git config --file "$common_dir/config" --get "$key" || true)"
            if [ -n "$value" ] && { [ "$key" = core.worktree ] || [ "$value" = true ]; }; then
              git config --file "$common_dir/config.worktree" "$key" "$value"
              git config --file "$common_dir/config" --unset "$key"
            fi
          done
          git config --file "$common_dir/config" extensions.worktreeConfig true
        fi
        if [ "$(git config --worktree --get core.hooksPath || true)" != "$git_dir/hooks" ]; then
          git config --worktree core.hooksPath "$git_dir/hooks"
        fi
      '';
    };

  setupScript = pkgs:
    (pkgs.writeShellApplication {
      name = "workbench-worktree-setup";
      runtimeInputs = [pkgs.git pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.findutils];
      text = ''
        setup_command="${builtins.placeholder "out"}/bin/workbench-worktree-setup"
        if [ "''${1:-}" = --check ]; then
          shift
          if [ "''${1:-}" = --worktree ]; then shift; fi
          [ "$#" -le 1 ] || { echo 'expected --check [<path>]' >&2; exit 64; }
          worktree="''${1:-$PWD}"
          # Setup applies to linked worktrees only: a main checkout or a
          # directory outside any repository has no record by design.
          if ! git_dir="$(git -C "$worktree" -c submodule.recurse=false rev-parse --absolute-git-dir 2>/dev/null)"; then
            printf 'worktree %s: not a git repository; worktree setup does not apply\n' "$worktree" >&2
            exit 4
          fi
          common_dir="$(git -C "$worktree" -c submodule.recurse=false rev-parse --path-format=absolute --git-common-dir)"
          if [ "$git_dir" = "$common_dir" ]; then
            printf 'worktree %s: main checkout, not a linked worktree; worktree setup does not apply\n' "$worktree" >&2
            exit 4
          fi
          state=missing code=2
          if [ -f "$git_dir/workbench-setup.json" ]; then
            record="$git_dir/workbench-setup.json"
            if ! jq -e 'type == "object" and (.status == "ok" or .status == "failed") and (.setupCommand | type == "string")' "$record" >/dev/null 2>&1; then
              state=failed code=1
            elif [ "$(jq -r .setupCommand "$record")" != "$setup_command" ]; then
              state=stale code=3
            elif [ "$(jq -r .status "$record")" = ok ]; then
              exit 0
            else
              state=failed code=1
            fi
          fi
          printf 'worktree %s: setup %s; run workbench-worktree-setup --worktree %q\n' "$worktree" "$state" "$worktree" >&2
          exit "$code"
        fi
        ${arguments}
        git_dir="$(git -c submodule.recurse=false rev-parse --absolute-git-dir)"
        started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        step=discovery
        warm_result=not-run warm_status=null
        finish() {
          result=$?
          trap - EXIT
          status=failed failed_step="$step"
          if [ "$result" = 0 ]; then status=ok failed_step=""; fi
          record_tmp="$(mktemp "$git_dir/workbench-setup.json.XXXXXX")"
          jq -n --arg status "$status" --arg step "$failed_step" \
            --arg warm "$warm_result" --argjson warmCode "$warm_status" \
            --arg start "$started_at" --arg finish "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg command "$setup_command" \
            '{status: $status, failedStep: (if $step == "" then null else $step end), warmUp: {status: $warm, exitCode: $warmCode}, startedAt: $start, finishedAt: $finish, setupCommand: $command}' > "$record_tmp"
          mv -f "$record_tmp" "$git_dir/workbench-setup.json"
          if [ "$result" != 0 ] && [ "$step" != submodule-stub ]; then echo "worktree $worktree: setup failed at $step; see $git_dir/workbench-setup.json" >&2; fi
          exit "$result"
        }
        trap finish EXIT

        # Probe before artifact placement: Nix may not discover linked submodules.
        if ! nix flake metadata --json >/dev/null 2>&1; then
          if [ -f .git ] && grep -q '\.git/modules/' .git 2>/dev/null; then
            echo "agentic: nix cannot initialize in this worktree of a SUBMODULE" >&2
            echo "  (gitdir indirection: .git -> parent/.git/modules/<sub>/worktrees/<name>)." >&2
            echo "  Dev-shell tools are unavailable here. Workaround: invoke tools via" >&2
            echo "    nix shell nixpkgs#<tool> --command <tool> ..." >&2
            echo "  Do NOT edit .envrc per-worktree." >&2
            exit 1
          fi
          echo "agentic: nix flake discovery failed in this worktree (not the submodule constraint) — investigate before continuing." >&2
          exit 1
        fi
        main_wt="$(git -c submodule.recurse=false worktree list --porcelain | head -1 | sed 's/^worktree //')"
        ${lib.optionalString cfg.traits.submodules ''
          # LAB-178: reset-before-init can leave config-only submodule gitdirs.
          # Detect without deleting, moving, or otherwise adopting their data.
          step='submodule-stub'
          reject_stub() {
            local candidate="$1" checkout="$2"
            if [ -f "$candidate/config" ] && [ ! -e "$candidate/HEAD" ] && [ ! -e "$candidate/objects" ]; then
              printf 'worktree %s: submodule-stub at %s (checkout %s); manual data-preserving repair: move the stub gitdir and submodule working directory to backups outside the worktree, then run git submodule update --init --recursive\n' "$worktree" "$candidate" "$checkout" >&2
              exit 1
            fi
          }
          if [ -d "$git_dir/modules" ]; then
            while IFS= read -r -d "" config_file; do
              candidate="$(dirname "$config_file")"
              checkout="$(git -c submodule.recurse=false config --file "$config_file" --get core.worktree || true)"
              if [ -n "$checkout" ] && [[ "$checkout" != /* ]]; then checkout="$(realpath -m "$candidate/$checkout")"; fi
              reject_stub "$candidate" "$checkout"
            done < <(find "$git_dir/modules" -type f -name config -print0)
          fi
          if [ -f .gitmodules ]; then
            while read -r _key subpath; do
              if [ -f "$subpath/.git" ]; then
                IFS= read -r gitfile < "$subpath/.git"
                if [[ "$gitfile" = 'gitdir: '* ]]; then
                  candidate="''${gitfile#gitdir: }"
                  if [[ "$candidate" != /* ]]; then candidate="$(realpath -m "$subpath/$candidate")"; fi
                  reject_stub "$candidate" "$worktree/$subpath"
                fi
              fi
            done < <(git -c submodule.recurse=false config --file .gitmodules --get-regexp '^submodule\..*\.path$' || true)
          fi
          step=submodules
          # Recurse explicitly, independent of the caller's submodule.recurse.
          git submodule update --init --recursive
        ''}
        step='copy-files'
        # The declared list may contain exactly one file.
        # shellcheck disable=SC2043
        for f in ${lib.escapeShellArgs (cfg.copyFiles ++ cfg.traits.secretDotfiles)}; do
          if [ ! -e "$f" ] && [ -e "$main_wt/$f" ]; then
            cp -R "$main_wt/$f" "$f"
          fi
        done
        step='state-isolation'
        for d in .direnv .devenv; do
          if [ -L "$d" ] && [ "$(readlink "$d")" = "$main_wt/$d" ]; then
            rm "$d"
          fi
        done
        step='git-hooks'
        ${hooksScript pkgs}/bin/agentic-worktree-hooks
        step=direnv
        command -v direnv >/dev/null 2>&1 && direnv allow || true
        step='warm-up'
        warm_result=skipped warm_status=0
        if [ -f devenv.nix ] && command -v devenv >/dev/null 2>&1; then
          warm_result=ok
          devenv shell -- true >/dev/null 2>&1 || warm_status=$?
        elif [ -f flake.nix ]; then
          warm_result=ok
          nix develop --impure -c true >/dev/null 2>&1 || warm_status=$?
        fi
        if [ "$warm_status" != 0 ]; then
          warm_result=failed
          echo "agentic: dev shell warm-up failed; sandboxed agents may be unable to enter it" >&2
          exit "$warm_status"
        fi
        ${lib.concatImapStringsSep "\n" (i: command: ''
            step='setupHooks[${toString (i - 1)}]'
            ${lib.getExe (hook pkgs "setup" i command)}
          '')
          cfg.setupHooks}
      '';
    }).overrideAttrs (old: {
      buildCommand =
        old.buildCommand
        + ''
          ln -s workbench-worktree-setup "$out/bin/agentic-worktree-setup"
        '';
    });

  teardownScript = pkgs:
    pkgs.writeShellApplication {
      name = "workbench-worktree-teardown";
      runtimeInputs = [pkgs.coreutils pkgs.gnugrep];
      text = ''
        ${arguments}
        ${
          if cfg.teardownHooks == []
          then ''
            echo "worktree $worktree: no teardown hooks declared; nothing to verify"
          ''
          else
            lib.concatImapStringsSep "\n" (i: command: ''
              output="$(mktemp)"
              trap 'rm -f "$output"' EXIT
              hook_status=0
              ${lib.getExe (hook pkgs "teardown" i command)} >"$output" || hook_status=$?
              cat "$output"
              reason=""
              if [ "$hook_status" != 0 ]; then reason="exit $hook_status"
              elif grep -qi 'skipped' "$output"; then reason='reported skipped cleanup'
              elif ! grep -q '^verified:' "$output"; then reason='missing verified: line on stdout'
              fi
              if [ -n "$reason" ]; then
                echo "worktree $worktree: teardownHooks[${toString (i - 1)}] failed: $reason; do not remove the worktree" >&2
                exit 1
              fi
              rm -f "$output"
              trap - EXIT
            '')
            cfg.teardownHooks
        }
      '';
    };
in {
  options.agentic.worktree = {
    traits = {
      submodules = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Initialize declared submodules recursively in each worktree.";
      };
      secretDotfiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [".env"];
        description = "Secret-bearing files copied per worktree, never shared.";
      };
    };
    copyFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [".envrc" ".claude"];
      description = "Files copied from the main worktree when absent.";
    };
    setupHooks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Ordered shell commands run in the worktree after setup. Each runs in its own strict Bash process; use store paths for dependencies. Failures are named setupHooks[zero-based-index].";
    };
    teardownHooks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Ordered shell commands run in the worktree before coordinator removal. Each must exit zero and print a verified: stdout line, without skipped. No removal is performed.";
    };
  };
  options.agentic.worktreeLib = lib.mkOption {
    type = lib.types.raw;
    readOnly = true;
    description = "Creator-neutral setupScript pkgs, hooksScript pkgs (isolated Git hooks), and teardownScript pkgs.";
  };
  config.agentic.worktreeLib = {inherit setupScript hooksScript teardownScript;};
}
