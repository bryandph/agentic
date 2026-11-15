# Knowledge semantic search (design D11, agentic-agents spec "Knowledge
# memory plane"): qmd over the committed knowledge markdown. Serena's
# retrieval is name-based by design; qmd fills the concept-query gap
# with hybrid BM25/vector/rerank over local models. The index is
# disposable and lives OUTSIDE the repo (qmd's user cache) — nothing to
# commit, nothing to drift.
#
# Collections are declared per consumer: a per-repo collection over the
# repo's committed knowledge markdown (the serena memory namespace) and
# an org collection over the shared fragment source supplied by the env
# layer. The wrapper (re)registers declared collections idempotently
# before serving, so MCP and CLI callers see the same corpus.
#
# Pi coverage: the same wrapper is the CLI equivalent (`qmd-knowledge
# search …`) — declared on the registry entry per agentic-mcp-registry's
# harness-coverage requirement.
{
  lib,
  config,
  agenticInputs,
  ...
}: let
  cfg = config.agentic.knowledgeSearch;

  # On darwin the sandboxed node-gyp rebuild (better-sqlite3) fails
  # with "No Xcode or CLT version detected" — upstream builds with CLT
  # receipts visible. xcbuild's xcodebuild shim satisfies gyp's probe.
  qmdPackage = pkgs: let
    base = agenticInputs.qmdBase pkgs;
  in
    if pkgs.stdenv.hostPlatform.isDarwin
    then
      base.overrideAttrs (o: {
        nativeBuildInputs = (o.nativeBuildInputs or []) ++ [pkgs.xcbuild];
      })
    else base;

  wrapper = pkgs: let
    qmd = "${qmdPackage pkgs}/bin/qmd";
  in
    pkgs.writeScriptBin "qmd-knowledge" ''
      #!${pkgs.runtimeShell}
      ${lib.optionalString (cfg.index == "local") ''
        # Project-local index: qmd uses the nearest .qmd/ above the cwd,
        # so a parent scope's index covers its children while a child
        # never sees its parent.
        [ -d .qmd ] || ${qmd} init >/dev/null
      ''}
      # Register declared collections (idempotent — add failures on
      # existing collections are expected), then pass through.
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (
          name: c: "${qmd} collection add ${lib.escapeShellArg c.path} --name ${lib.escapeShellArg name} >/dev/null 2>&1 || true"
        )
        cfg.collections)}
      exec ${qmd} "$@"
    '';
  # qmd update is text-only and content-hash incremental, but it also
  # executes user-configured update hooks. Never run those at shell entry.
  refreshScript = pkgs: let
    refresh = pkgs.writeShellScript "qmd-knowledge-refresh" ''
      set -euo pipefail
      export PATH=${lib.makeBinPath [pkgs.coreutils pkgs.findutils]}:$PATH
      config=
      ${lib.optionalString (cfg.index == "local") ''
        # The wrapper will initialise here, not use a parent index.
        if [ ! -d .qmd ]; then
          config="$PWD/.qmd/index.yml"
        fi
      ''}
      dir="$PWD"
      while [ -z "$config" ]; do
        for name in index.yaml index.yml; do
          if [ -f "$dir/.qmd/$name" ]; then
            config="$dir/.qmd/$name"
            break
          fi
        done
        [ -z "$config" ] || break
        [ "$dir" != / ] || break
        dir="''${dir%/*}"
        dir="''${dir:-/}"
      done
      if [ -z "$config" ]; then
        config="''${QMD_CONFIG_DIR:-''${XDG_CONFIG_HOME:-$HOME/.config}/qmd}/index.yml"
        db="''${INDEX_PATH:-''${XDG_CACHE_HOME:-$HOME/.cache}/qmd/index.sqlite}"
      else
        db="''${config%/*}/index.sqlite"
      fi
      case "$config" in /*) ;; *) config="$PWD/$config" ;; esac
      case "$db" in /*) ;; *) db="$PWD/$db" ;; esac
      stamp="''${db%/*}/.agentic-refresh.sha256"
      # Hash names and contents, not mtimes: preserved timestamps, removals,
      # renames and changed declarations must all invalidate the fast path.
      # Compute BEFORE updating so concurrent edits force another refresh.
      fingerprint=$(
        set -e
        {
          printf '%s\0' ${lib.escapeShellArg "${wrapper pkgs}"} "$PWD" "$config" "$db"
          sources=()
          if [ -f "$config" ]; then
            sources+=("$config")
          else
            printf 'missing-config\0'
          fi
          ${lib.concatMapStringsSep "\n" (c: ''
        printf '%s\0' ${lib.escapeShellArg c.path}
        collection=${lib.escapeShellArg c.path}
        case "$collection" in /*) ;; *) collection="$PWD/$collection" ;; esac
        if [ -e "$collection" ]; then
          sources+=("$collection")
        else
          printf 'missing-collection\0'
        fi
      '') (lib.attrValues cfg.collections)}
          if [ "''${#sources[@]}" -gt 0 ]; then
            find -L "''${sources[@]}" -type f -print0 | sort -z | xargs -0 -r sha256sum --zero --
          fi
        } | sha256sum
      )
      if [ -f "$db" ] && [ -f "$stamp" ] && [ "$(<"$stamp")" = "$fingerprint" ]; then
        exit 0
      fi
      if [ -f "$config" ]; then
        ${pkgs.yq-go}/bin/yq -e '[.collections[] | select(.update != null and .update != "")] | length == 0' "$config" >/dev/null
      fi
      ${wrapper pkgs}/bin/qmd-knowledge update
      temporary=$(mktemp "$stamp.XXXXXXXX")
      trap 'rm -f "$temporary"' EXIT
      printf '%s\n' "$fingerprint" > "$temporary"
      mv -f -- "$temporary" "$stamp"
    '';
  in ''
    # Best effort, offline BM25 refresh; bound startup even if qmd hangs.
    if ! ${pkgs.coreutils}/bin/timeout --kill-after=1s ${toString cfg.refreshTimeout}s ${refresh} </dev/null >/dev/null 2>&1; then
      printf '%s\n' 'agentic: qmd index refresh skipped or failed (update hook, error, or timeout).' >&2
    fi
  '';
in {
  options.agentic.knowledgeSearch = {
    index = lib.mkOption {
      type = lib.types.enum ["user" "local"];
      default = "user";
      description = ''
        `user`: collections register in qmd's user-wide index.
        `local`: the wrapper creates a project-local `.qmd/` index in the
        repository root (git-ignore it) and registers collections there,
        so searches from inside the repository see only its own scope.
      '';
    };

    refreshTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 10;
      description = "Timeout in seconds for the best-effort shell-entry qmd text index refresh.";
    };

    collections = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.path = lib.mkOption {
          type = lib.types.str;
          description = ''
            Directory of markdown to index. Relative paths resolve
            against the process cwd (the repo root under both the
            shell bootstrap and the MCP server).
          '';
        };
      });
      default = {};
      description = ''
        qmd collections, name -> source. Convention: a per-repo
        collection over the committed knowledge markdown
        (`.serena/memories`) plus an org collection over the shared
        fragment source (env layer).
      '';
    };

    lib = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = "Helpers: `wrapper pkgs` (collection-registering qmd passthrough), `package pkgs`, `refreshScript pkgs` (bounded, best-effort text index refresh).";
    };
  };

  config = {
    agentic.knowledgeSearch.lib = {
      inherit wrapper refreshScript;
      package = qmdPackage;
    };

    # Opt-in: a consumer that declares no collections gets no knowledge
    # server, no CLI, and never builds qmd.
    agentic.mcp.servers.knowledge = lib.mkIf (cfg.collections != {}) {
      tiers = ["project"];
      command = pkgs: "${wrapper pkgs}/bin/qmd-knowledge";
      args = ["mcp"];
      cliEquivalent = "qmd-knowledge search '<query>' (hybrid semantic search over the repo + org knowledge collections; qmd-knowledge vsearch/query for vector-only/reranked)";
    };
  };
}
