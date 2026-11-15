# Creator-neutral preparation and verified cleanup. Herdr owns creation/removal;
# this module owns only repository setup, its result, and repository hooks.
{
  lib,
  config,
  ...
}: let
  cfg = config.agentic.worktree;
  hookType = lib.types.either lib.types.str (lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9_-]+";
        description = "Unique hook name within this phase.";
      };
      run = lib.mkOption {
        type = lib.types.str;
        description = "Command run in its own strict Bash process.";
      };
      required = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether failure stops setup or vetoes removal.";
      };
      needs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Declared service dependencies; recorded but not yet acted on.";
      };
    };
  });
  validateHooks = phase: hooks: let
    named = lib.imap0 (index: value: {inherit index value;}) hooks;
    errors = lib.concatMap (entry:
      lib.optionals (builtins.isAttrs entry.value) (
        (lib.concatMap (other:
          lib.optional (builtins.isAttrs other.value && other.index < entry.index && other.value.name == entry.value.name)
          "${phase}[${toString other.index}] and ${phase}[${toString entry.index}] duplicate hook name '${entry.value.name}'")
        named)
        ++ (lib.concatMap (service:
          lib.optional (!(builtins.hasAttr service cfg.services))
          "${phase}[${entry.value.name}] needs unknown service '${service}'")
        entry.value.needs)
      ))
    named;
  in
    if errors == []
    then hooks
    else throw (lib.concatStringsSep "; " errors);
  normalizeHook = index: value:
    if builtins.isString value
    then {
      name = toString (index - 1);
      run = value;
      required = true;
      needs = null;
    }
    else value;
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
          check_json=false
          if [ "''${1:-}" = --json ]; then check_json=true; shift; fi
          if [ "''${1:-}" = --worktree ]; then shift; fi
          [ "$#" -le 1 ] || { echo 'expected --check [--json] [<path>]' >&2; exit 64; }
          worktree="''${1:-$PWD}"
          # Setup applies to linked worktrees only: a main checkout or a
          # directory outside any repository has no record by design.
          if ! git_dir="$(GIT_WORK_TREE="$PWD" git -C "$worktree" -c submodule.recurse=false rev-parse --absolute-git-dir 2>/dev/null)"; then
            printf 'worktree %s: not a git repository; worktree setup does not apply\n' "$worktree" >&2
            if "$check_json"; then jq -n '{status: "not-applicable", code: 4, digest: null, record: null}'; fi
            exit 4
          fi
          common_dir="$(GIT_WORK_TREE="$PWD" git -C "$worktree" -c submodule.recurse=false rev-parse --path-format=absolute --git-common-dir)"
          if [ "$git_dir" = "$common_dir" ]; then
            printf 'worktree %s: main checkout, not a linked worktree; worktree setup does not apply\n' "$worktree" >&2
            if "$check_json"; then jq -n '{status: "not-applicable", code: 4, digest: null, record: null}'; fi
            exit 4
          fi
          state=missing code=2
          digest="" record_json=null
          if [ -f "$git_dir/workbench-setup.json" ]; then
            record="$git_dir/workbench-setup.json"
            digest="$(sha256sum "$record" | cut -d " " -f 1)"
            record_json="$(jq -cs 'if length == 1 then .[0] else null end' "$record" 2>/dev/null || echo null)"
            if jq -e 'type == "object" and (has("schema") | not)' "$record" >/dev/null 2>&1; then
              state=stale code=3
            elif ! jq -e 'type == "object" and .schema == "workbench.worktree-setup/2" and (.steps | type == "array") and (.status == "ok" or .status == "degraded" or .status == "failed" or .status == "blocked") and (.setupCommand | type == "string")' "$record" >/dev/null 2>&1; then
              state=failed code=1
            elif [ "$(jq -r .setupCommand "$record")" != "$setup_command" ]; then
              state=stale code=3
            elif [ "$(jq -r .status "$record")" = ok ]; then
              state=ok code=0
            elif [ "$(jq -r .status "$record")" = degraded ]; then
              state=degraded code=5
            elif [ "$(jq -r .status "$record")" = blocked ]; then
              state=blocked code=6
            else
              state=failed code=1
            fi
          fi
          if "$check_json"; then
            jq -n --arg status "$state" --argjson code "$code" --arg digest "$digest" --argjson record "$record_json" \
              '{status: $status, code: $code, digest: (if $digest == "" then null else $digest end), record: $record}'
          fi
          if [ "$code" = 0 ]; then exit 0; fi
          printf 'worktree %s: setup %s; run workbench-worktree-setup --worktree %q\n' "$worktree" "$state" "$worktree" >&2
          exit "$code"
        fi
        ${arguments}
        # Metadata discovery must survive an invalid inherited core.worktree;
        # the helper below derives the actual checkout from its registration.
        git_dir="$(GIT_WORK_TREE="$PWD" git -c submodule.recurse=false rev-parse --absolute-git-dir)"
        started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        step="" steps='[]' degraded=false first_failure=""
        step_required=true step_needs=null blocker=null
        block_relative_worktrees() {
          local stderr="$1" code="$2" detail nix_version
          if ! grep -qiF 'unsupported extension name extensions.relativeworktrees' <<< "$stderr"; then return 0; fi
          detail="$(printf '%s\n' "$stderr" | tail -n 20 | tail -c 2048)"
          nix_version="$(nix --version 2>&1 || true)"
          blocker="$(jq -cn --arg step "$step" --arg version "$nix_version" --arg detail "$detail" \
            '{kind: "environment", code: "nix-relativeworktrees", step: $step, nixVersion: $version, detail: $detail,
              remediation: "The repository has extensions.relativeWorktrees set, so the nix on PATH cannot open it. Convert its worktrees to absolute links and unset the extension (operator cleanup), or use nix >= 2.34.9."}')"
          echo "$detail" >&2
          end_step blocked "$code" true "" "$detail"
          exit 6
        }
        end_step() {
          local outcome="$1" code="$2" applies="$3" reason="$4" message="''${5:-}"
          steps="$(jq -c --arg name "$step" --arg outcome "$outcome" --argjson code "$code" \
            --argjson required "$step_required" --argjson needs "$step_needs" --argjson applies "$applies" --arg reason "$reason" --arg message "$message" \
            '. + [{name: $name, applies: $applies, outcome: $outcome, required: $required}
              + (if $needs == null then {} else {needs: $needs} end)
              + (if $code == null then {} else {exitCode: $code} end)
              + (if $reason == "" then {} else {reason: $reason} end)
              + (if $message == "" then {} else {message: $message} end)]' <<< "$steps")"
          if [ "$outcome" = failed ]; then
            if [ -z "$first_failure" ]; then first_failure="$step"; fi
            if ! "$step_required"; then degraded=true; fi
          fi
          step=""
        }
        begin_step() {
          if [ -n "$step" ]; then end_step ok 0 true ""; fi
          step="$1" step_required=true step_needs=null
        }
        shell_kind=${lib.escapeShellArg cfg.shell.kind}
        shell_attr=${lib.escapeShellArg cfg.shell.attr}
        shell_required=${lib.boolToString cfg.shell.required}
        warm_result=not-run warm_status=null
        stale_socket_removed=""
        submodules_configured=${lib.boolToString cfg.traits.submodules}
        submodules_initialized='[]'
        submodules_excluded=${lib.escapeShellArg (builtins.toJSON cfg.submodules.exclude)}
        submodules_skipped=null
        finish() {
          result=$?
          trap - EXIT
          failed_step="$step"
          if [ -n "$step" ]; then
            if [ "$result" = 0 ]; then end_step ok 0 true ""; else end_step failed "$result" true ""; fi
          fi
          status=failed
          if [ "$result" = 0 ]; then
            status=ok failed_step=""
            if "$degraded"; then status=degraded failed_step="$first_failure"; fi
          elif [ -z "$failed_step" ]; then failed_step="$first_failure"
          fi
          if [ "$blocker" != null ]; then
            status=blocked failed_step="$(jq -r .step <<< "$blocker")"
          fi
          record_tmp="$(mktemp "$git_dir/workbench-setup.json.XXXXXX")"
          jq -n --arg status "$status" --arg step "$failed_step" --argjson steps "$steps" --argjson blocker "$blocker" \
            --arg warm "$warm_result" --argjson warmCode "$warm_status" \
            --arg start "$started_at" --arg finish "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg command "$setup_command" --arg staleSocket "$stale_socket_removed" \
            --argjson configured "$submodules_configured" --argjson initialized "$submodules_initialized" \
            --argjson excluded "$submodules_excluded" --argjson skipped "$submodules_skipped" \
            '{schema: "workbench.worktree-setup/2", steps: $steps, submodules: {configured: $configured, initialized: $initialized, excluded: $excluded, skipped: $skipped}, fsmonitor: {staleSocketRemoved: (if $staleSocket == "" then null else $staleSocket end)}, status: $status, failedStep: (if $step == "" then null else $step end), warmUp: {status: $warm, exitCode: $warmCode}, startedAt: $start, finishedAt: $finish, setupCommand: $command} + (if $blocker == null then {} else {blocker: $blocker} end)' > "$record_tmp"
          mv -f "$record_tmp" "$git_dir/workbench-setup.json"
          if [ "$result" != 0 ] && [ "$failed_step" != submodule-stub ]; then echo "worktree $worktree: setup $status at $failed_step; see $git_dir/workbench-setup.json" >&2; fi
          exit "$result"
        }
        trap finish EXIT

        # Repair Git's checkout resolution before Nix or submodule commands.
        begin_step 'worktree-config'
        ${hooksScript pkgs}/bin/agentic-worktree-hooks
        begin_step fsmonitor
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
        begin_step discovery
        step_required="$shell_required"
        if [ "$shell_kind" = auto ]; then
          if [ -f devenv.nix ] && command -v devenv >/dev/null 2>&1; then shell_kind=devenv
          elif [ -f flake.nix ]; then shell_kind=flake
          else shell_kind=none
          fi
        fi
        # Probe before artifact placement: Nix may not discover linked submodules.
        discovery_stderr="$(mktemp)"
        if [ "$shell_kind" != flake ]; then
          end_step not-applicable null false "resolved shell kind is $shell_kind"
        elif nix flake metadata --json >/dev/null 2>"$discovery_stderr"; then
          end_step ok 0 true ""
        else
          discovery_status=$?
          discovery_detail="$(< "$discovery_stderr")"
          rm -f "$discovery_stderr"
          block_relative_worktrees "$discovery_detail" "$discovery_status"
          if [ -f .git ] && grep -q '\.git/modules/' .git 2>/dev/null; then
            discovery_message="$(printf '%s\n' \
              "agentic: nix cannot initialize in this worktree of a SUBMODULE" \
              "  (gitdir indirection: .git -> parent/.git/modules/<sub>/worktrees/<name>)." \
              "  Dev-shell tools are unavailable here. Workaround: invoke tools via" \
              "    nix shell nixpkgs#<tool> --command <tool> ..." \
              "  Do NOT edit .envrc per-worktree.")"
          else
            discovery_message="agentic: nix flake discovery failed in this worktree (not the submodule constraint) — investigate before continuing."
          fi
          if [ -n "$discovery_detail" ]; then
            discovery_detail="$(printf '%s\n' "$discovery_detail" | tail -n 20 | tail -c 2048)"
            discovery_message="$discovery_message"$'\n'"$discovery_detail"
          fi
          echo "$discovery_message" >&2
          end_step failed "$discovery_status" true "" "$discovery_message"
          if "$shell_required"; then exit "$discovery_status"; fi
        fi
        rm -f "$discovery_stderr"
        begin_step submodule-discovery
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
          begin_step 'submodule-stub'
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
          begin_step submodules
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
        begin_step 'copy-files'
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
        begin_step 'state-isolation'
        for d in .direnv .devenv; do
          if [ -L "$d" ] && [ "$(readlink "$d")" = "$main_wt/$d" ]; then
            rm "$d"
          fi
        done
        begin_step 'git-hooks'
        ${hooksScript pkgs}/bin/agentic-worktree-hooks
        begin_step direnv
        command -v direnv >/dev/null 2>&1 && direnv allow || true
        begin_step warm-up
        step_required="$shell_required"
        warm_result=skipped warm_status=0
        warm_applies=true warm_reason=""
        probe_stderr="$(mktemp)"
        case "$shell_kind" in
          none) warm_applies=false; warm_reason="resolved shell kind is none" ;;
          devenv)
            devenv shell -- true >/dev/null 2>"$probe_stderr" || warm_status=$?
            ;;
          flake)
            # attrNames evaluates names, not shell derivations. A missing
            # system (or devShells output) is also an absent shell, not failure.
            if system="$(nix eval --impure --raw --expr builtins.currentSystem 2>"$probe_stderr")"; then
              if attrs="$(nix eval --json --impure --expr "let f = builtins.getFlake (toString ./.); in builtins.attrNames (f.devShells.$system or {})" 2>"$probe_stderr")"; then
                if jq -e --arg attr "$shell_attr" 'index($attr) != null' <<< "$attrs" >/dev/null; then
                  nix develop ".#$shell_attr" --impure -c true >/dev/null 2>"$probe_stderr" || warm_status=$?
                else
                  warm_applies=false; warm_reason="devShells.$system.$shell_attr is absent"
                fi
              else
                warm_status=1
                warm_reason="could not inspect devShells for the current system"
              fi
            else
              warm_status=1
              warm_reason="could not determine the current system"
            fi
            ;;
        esac
        warm_probe_message="$(< "$probe_stderr")"
        rm -f "$probe_stderr"
        if ! "$warm_applies"; then
          end_step not-applicable null false "$warm_reason"
        elif [ "$warm_status" != 0 ]; then
          warm_result=failed
          block_relative_worktrees "$warm_probe_message" "$warm_status"
          warm_message="agentic: dev shell warm-up failed; sandboxed agents may be unable to enter it"
          if [ -n "$warm_probe_message" ]; then
            warm_probe_message="$(printf '%s\n' "$warm_probe_message" | tail -n 20 | tail -c 2048)"
            warm_message="$warm_message"$'\n'"$warm_probe_message"
          fi
          echo "$warm_message" >&2
          end_step failed "$warm_status" true "$warm_reason" "$warm_message"
          if "$shell_required"; then exit "$warm_status"; fi
        else
          warm_result=ok
          end_step ok 0 true ""
        fi
        ${lib.concatImapStringsSep "\n" (i: value: let
            h = normalizeHook i value;
          in ''
            begin_step 'setupHooks[${h.name}]'
            step_required=${lib.boolToString h.required}
            step_needs=${lib.escapeShellArg (builtins.toJSON h.needs)}
            hook_status=0
            ${lib.getExe (hook pkgs "setup" i h.run)} || hook_status=$?
            if [ "$hook_status" != 0 ]; then
              if "$step_required"; then exit "$hook_status"; fi
              echo "worktree $worktree: $step failed: exit $hook_status; continuing (not required)" >&2
              end_step failed "$hook_status" true ""
            fi
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

  workerStartScript = pkgs:
    (import ./_worker-start.nix pkgs).override {setupScript = setupScript pkgs;};

  workerRecoverScript = pkgs:
    (import ./_seat-tools/package.nix pkgs "workbench-worker-recover").override {
      workerStartScript = workerStartScript pkgs;
    };

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
            lib.concatImapStringsSep "\n" (i: value: let
              h = normalizeHook i value;
            in ''
              output="$(mktemp)"
              trap 'rm -f "$output"' EXIT
              hook_status=0
              ${lib.getExe (hook pkgs "teardown" i h.run)} >"$output" || hook_status=$?
              cat "$output"
              reason=""
              if [ "$hook_status" != 0 ]; then reason="exit $hook_status"
              elif ${lib.boolToString h.required} && grep -qi 'skipped' "$output"; then reason='reported skipped cleanup'
              elif ${lib.boolToString h.required} && ! grep -q '^verified:' "$output"; then reason='missing verified: line on stdout'
              fi
              if [ -n "$reason" ]; then
                if ${lib.boolToString h.required}; then
                  echo "worktree $worktree: teardownHooks[${h.name}] failed: $reason; do not remove the worktree" >&2
                  exit 1
                fi
                echo "worktree $worktree: teardownHooks[${h.name}] failed: $reason; continuing (not required)" >&2
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
        export AGENTIC_WORKTREE_TEARDOWN=${lib.escapeShellArg "${teardownScript pkgs}/bin/workbench-worktree-teardown"}
        exec python3 ${./_worktree-remove.py} "$@"
      '';
    };
in {
  options.agentic.worktree = {
    shell = {
      kind = lib.mkOption {
        type = lib.types.enum ["auto" "none" "flake" "devenv"];
        default = "auto";
        description = "Shell selection: auto prefers available devenv, then a flake, otherwise none.";
      };
      attr = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Flake devShell attribute to warm when present for the current system.";
      };
      required = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Make applicable discovery and warm-up failures fatal rather than degraded.";
      };
    };
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
    services = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Services declared in step 5; not yet acted on. Hook needs must reference these names.";
    };
    setupHooks = lib.mkOption {
      type = lib.types.listOf hookType;
      default = [];
      apply = validateHooks "setupHooks";
      description = "Ordered strings or { name; run; required ? true; needs ? []; } hooks run after setup in separate strict Bash processes. Names are unique tokens; plain strings keep zero-based index names and are required. Non-required failures degrade setup and allow later hooks to run. Needs are validated and recorded, not started; use store paths for dependencies.";
    };
    teardownHooks = lib.mkOption {
      type = lib.types.listOf hookType;
      default = [];
      apply = validateHooks "teardownHooks";
      description = "Ordered strings or { name; run; required ? true; needs ? []; } hooks run before coordinator removal. Required hooks (including strings) must exit zero and print a verified: stdout line, without skipped; failure vetoes removal. Non-required hooks need no verification line; nonzero exits are reported but do not veto removal. Needs are only validated; no services or removal are performed.";
    };
  };
  options.agentic.worktreeLib = lib.mkOption {
    type = lib.types.raw;
    readOnly = true;
    description = "Creator-neutral setupScript pkgs, hooksScript pkgs (isolated Git hooks), teardownScript pkgs, workerStartScript pkgs, workerRecoverScript pkgs, and removeScript pkgs.";
  };
  config.agentic.worktreeLib = {inherit setupScript hooksScript teardownScript workerStartScript workerRecoverScript removeScript;};
}
