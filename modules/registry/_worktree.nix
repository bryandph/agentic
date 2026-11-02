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

  hooksScript = import ../_git-hooks/isolate.nix;

  setupScript = pkgs:
    (pkgs.writeShellApplication {
      name = "workbench-worktree-setup";
      runtimeInputs = [pkgs.git pkgs.jq pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.findutils pkgs.python3];
      text = ''
        setup_command="${builtins.placeholder "out"}/bin/workbench-worktree-setup"
        if [ "''${1:-}" = --check ]; then
          shift
          if [ "''${1:-}" = --worktree ]; then shift; fi
          [ "$#" -le 1 ] || { echo 'expected --check [<path>]' >&2; exit 64; }
          worktree="''${1:-$PWD}"
          # Setup applies to linked worktrees only: a main checkout or a
          # directory outside any repository has no record by design.
          if ! git_dir="$(GIT_WORK_TREE="$PWD" git -C "$worktree" -c submodule.recurse=false rev-parse --absolute-git-dir 2>/dev/null)"; then
            printf 'worktree %s: not a git repository; worktree setup does not apply\n' "$worktree" >&2
            exit 4
          fi
          common_dir="$(GIT_WORK_TREE="$PWD" git -C "$worktree" -c submodule.recurse=false rev-parse --path-format=absolute --git-common-dir)"
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
        # Metadata discovery must survive an invalid inherited core.worktree;
        # the helper below derives the actual checkout from its registration.
        git_dir="$(GIT_WORK_TREE="$PWD" git -c submodule.recurse=false rev-parse --absolute-git-dir)"
        started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        step=discovery
        warm_result=not-run warm_status=null
        stale_socket_removed=""
        submodules_configured=${lib.boolToString cfg.traits.submodules}
        submodules_initialized='[]'
        submodules_excluded=${lib.escapeShellArg (builtins.toJSON cfg.submodules.exclude)}
        submodules_skipped=null
        finish() {
          result=$?
          trap - EXIT
          status=failed failed_step="$step"
          if [ "$result" = 0 ]; then status=ok failed_step=""; fi
          record_tmp="$(mktemp "$git_dir/workbench-setup.json.XXXXXX")"
          jq -n --arg status "$status" --arg step "$failed_step" \
            --arg warm "$warm_result" --argjson warmCode "$warm_status" \
            --arg start "$started_at" --arg finish "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg command "$setup_command" --arg staleSocket "$stale_socket_removed" \
            --argjson configured "$submodules_configured" --argjson initialized "$submodules_initialized" \
            --argjson excluded "$submodules_excluded" --argjson skipped "$submodules_skipped" \
            '{submodules: {configured: $configured, initialized: $initialized, excluded: $excluded, skipped: $skipped}, fsmonitor: {staleSocketRemoved: (if $staleSocket == "" then null else $staleSocket end)}, status: $status, failedStep: (if $step == "" then null else $step end), warmUp: {status: $warm, exitCode: $warmCode}, startedAt: $start, finishedAt: $finish, setupCommand: $command}' > "$record_tmp"
          mv -f "$record_tmp" "$git_dir/workbench-setup.json"
          if [ "$result" != 0 ] && [ "$step" != submodule-stub ]; then echo "worktree $worktree: setup failed at $step; see $git_dir/workbench-setup.json" >&2; fi
          exit "$result"
        }
        trap finish EXIT

        # Repair Git's checkout resolution before Nix or submodule commands.
        step='worktree-config'
        ${hooksScript pkgs}/bin/agentic-worktree-hooks
        step=fsmonitor
        common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
        if [ "$git_dir" != "$common_dir" ]; then
          # worktree-config enabled extensions.worktreeConfig above. Address
          # this gitdir directly, never the common or global fsmonitor setting.
          file_config() { git config --file "$@"; }
          ${import ../_git-hooks/_fsmonitor-config.nix}
          # Status is a probe: not-running and Git builds without the builtin
          # are both harmless. Stop only this checkout's running daemon.
          if git -C "$worktree" fsmonitor--daemon status >/dev/null 2>&1; then
            if ! stop_output="$(git -C "$worktree" fsmonitor--daemon stop 2>&1)"; then
              # The daemon may exit between status and stop after the pin.
              if [[ "$stop_output" != *'not running'* ]]; then
                printf 'worktree %s: fsmonitor stop failed: %s\n' "$worktree" "$stop_output" >&2
                exit 1
              fi
            fi
          fi
          for ((attempt = 0; attempt < 50; attempt++)); do
            if ! git -C "$worktree" fsmonitor--daemon status >/dev/null 2>&1; then break; fi
            sleep 0.1
          done
          if git -C "$worktree" fsmonitor--daemon status >/dev/null 2>&1; then
            printf 'worktree %s: fsmonitor daemon still running after 5 seconds\n' "$worktree" >&2
            exit 1
          fi
          socket="$git_dir/fsmonitor--daemon.ipc"
          stale_socket_removed="$(python3 ${./_fsmonitor-socket.py} "$socket")"
          if [ -e "$socket" ] || [ -L "$socket" ]; then
            printf 'worktree %s: fsmonitor socket remains at %s\n' "$worktree" "$socket" >&2
            exit 1
          fi
        fi
        step=discovery
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
        # Git's -z config output separates key and value with a newline and
        # entries with NUL, preserving whitespace and glob characters in paths.
        submodule_paths=() selected_paths=() excluded_paths=()
        declared_exclusions=(${lib.escapeShellArgs cfg.submodules.exclude})
        if [ -f .gitmodules ]; then
          # A malformed file must not look like a repository with no entries.
          git -c submodule.recurse=false config --file .gitmodules --list >/dev/null
          while IFS= read -r -d "" entry; do
            subpath="''${entry#*$'\n'}"
            submodule_paths+=("$subpath")
            excluded=false
            for exclusion in "''${declared_exclusions[@]}"; do
              if [ "$subpath" = "$exclusion" ]; then excluded=true; break; fi
            done
            if "$excluded"; then excluded_paths+=("$subpath"); else selected_paths+=("$subpath"); fi
          done < <(git -c submodule.recurse=false config -z --file .gitmodules --get-regexp '^submodule\..*\.path$' || true)
        else
          submodules_skipped='"no-gitmodules"'
        fi
        observe_submodules() {
          local subpath state
          submodules_initialized='[]'
          missing_paths=() unexpected_paths=()
          for subpath in "''${submodule_paths[@]}"; do
            state="$(git -c submodule.recurse=false submodule status -- ":(literal)$subpath")"
            if [[ "$state" != -* ]] && [ -n "$state" ]; then
              submodules_initialized="$(jq -c --arg path "$subpath" '. + [$path]' <<< "$submodules_initialized")"
            fi
          done
          for subpath in "''${selected_paths[@]}"; do
            if ! jq -e --arg path "$subpath" 'index($path) != null' <<< "$submodules_initialized" >/dev/null; then missing_paths+=("$subpath"); fi
          done
          for subpath in "''${excluded_paths[@]}"; do
            if jq -e --arg path "$subpath" 'index($path) != null' <<< "$submodules_initialized" >/dev/null; then unexpected_paths+=("$subpath"); fi
          done
        }
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
          for subpath in "''${submodule_paths[@]}"; do
            if [ -f "$subpath/.git" ]; then
              IFS= read -r gitfile < "$subpath/.git"
              if [[ "$gitfile" = 'gitdir: '* ]]; then
                candidate="''${gitfile#gitdir: }"
                if [[ "$candidate" != /* ]]; then candidate="$(realpath -m "$subpath/$candidate")"; fi
                reject_stub "$candidate" "$worktree/$subpath"
              fi
            fi
          done
          step=submodules
          update_status=0
          if [ "''${#selected_paths[@]}" -gt 0 ]; then
            # Never pass an empty path list (Git would initialize everything).
            # Literal pathspecs also prevent exclusions being matched by globs.
            selected_specs=()
            for subpath in "''${selected_paths[@]}"; do selected_specs+=(":(literal)$subpath"); done
            git submodule update --init --recursive -- "''${selected_specs[@]}" || update_status=$?
          fi
          observe_submodules
          if [ "''${#missing_paths[@]}" -gt 0 ]; then
            printf 'worktree %s: submodules not initialized: ' "$worktree" >&2
            printf '%q ' "''${missing_paths[@]}" >&2
            printf '\n' >&2
          fi
          if [ "''${#unexpected_paths[@]}" -gt 0 ]; then
            printf 'worktree %s: excluded submodules initialized: ' "$worktree" >&2
            printf '%q ' "''${unexpected_paths[@]}" >&2
            printf '\n' >&2
          fi
          if [ "$update_status" != 0 ]; then exit "$update_status"; fi
          if [ "''${#missing_paths[@]}" -gt 0 ] || [ "''${#unexpected_paths[@]}" -gt 0 ]; then exit 1; fi
        ''}
        ${lib.optionalString (!cfg.traits.submodules) ''
          if [ "''${#submodule_paths[@]}" -gt 0 ]; then
            submodules_skipped='"trait-off"'
            printf 'WARNING: worktree %s has submodules but agentic.worktree.traits.submodules is off; submodule initialization skipped\n' "$worktree" >&2
            observe_submodules
          fi
        ''}
        step='copy-files'
        (
          cd -- "$main_wt"
          shopt -s nullglob dotglob
          # Expand patterns, but never split paths containing whitespace.
          IFS=
          # The declared list may contain exactly one pattern.
          # shellcheck disable=SC2043
          for pattern in ${lib.escapeShellArgs (cfg.copyFiles ++ cfg.traits.secretDotfiles)}; do
            # shellcheck disable=SC2086
            for f in $pattern; do
              if [ -e "$f" ] && [ ! -e "$worktree/$f" ]; then
                mkdir -p -- "$(dirname -- "$worktree/$f")"
                cp -R -- "$f" "$worktree/$f"
              fi
            done
          done
        )
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

  workerStartScript = import ./_worker-start.nix;

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
  removeScript = pkgs:
    pkgs.writeShellApplication {
      name = "workbench-worktree-remove";
      runtimeInputs = [pkgs.python3];
      text = ''
        exec python3 ${./_worktree-remove.py} "$@"
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
        description = "Secret-bearing paths or shell glob patterns copied from the main worktree when absent, never shared. Unmatched patterns are ignored; relative paths are preserved.";
      };
    };
    submodules.exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["secrets"];
      description = "Top-level submodule paths exactly as declared in .gitmodules to leave uninitialized. Setup never initializes or recurses into these paths, and fails if any is already initialized.";
    };
    copyFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [".envrc" ".claude"];
      description = "Paths or shell glob patterns copied from the main worktree when absent. Unmatched patterns are ignored; relative paths are preserved with parent directories created.";
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
    description = "Creator-neutral setupScript pkgs, hooksScript pkgs (isolated Git hooks), teardownScript pkgs, workerStartScript pkgs, and removeScript pkgs.";
  };
  config.agentic.worktreeLib = {inherit setupScript hooksScript teardownScript workerStartScript removeScript;};
}
