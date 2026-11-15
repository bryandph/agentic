# Knowledge memory plane (design D11, agentic-agents spec).
#
# Declared knowledge renders into per-repo serena memories: every
# fragment (and every declared deep-source document) becomes a memory
# under a generated topic namespace (default `knowledge/`), marked
# immutable via serena's `read_only_memory_patterns`. Agent-written
# memories live OUTSIDE the namespace and are never touched by
# regeneration — the place script replaces exactly the namespace
# directory, nothing else.
#
# `.serena/project.yml` is rendered from module options like every
# other artifact (project_name, languages, read-only patterns,
# freeform extras).
#
# Portability rule this plane resolves: a core fragment may reference
# `mem:knowledge/<name>` for a memory CORE ITSELF SHIPS (fragment or
# deep source), because generation places it in every consumer.
# Reference integrity is `serena memories check` (no language servers,
# no network) — exposed here for CI wiring and exercised by the core
# fixture check.
{
  lib,
  config,
  ...
}: let
  cfg = config.agentic.memoryPlane;
  acfg = config.agentic;

  # Canonical runtime ignore policy, shared by the CLI and template check.
  runtimeIgnoreLines = {
    whole = ["/.serena/"];
    shared = [".serena/cache/" ".serena/project.local.yml" ".serena/memories/knowledge/"];
    generatedProject = ".serena/project.yml";
  };

  ignoreCheckPackage = pkgs:
    pkgs.writeShellApplication {
      name = "workbench-serena-ignore";
      runtimeInputs = [pkgs.git];
      text = ''
        path=.
        if [ "$#" != 0 ]; then
          if [ "$#" != 2 ] || [ "$1" != --worktree ]; then
            echo 'usage: workbench-serena-ignore [--worktree <path>]' >&2
            exit 1
          fi
          path=$2
        fi
        root=$(git -C "$path" rev-parse --show-toplevel)
        cd "$root"
        lines=(${lib.escapeShellArgs runtimeIgnoreLines.whole})
        if [ -n "$(git ls-files -- .serena)" ]; then
          lines=(${lib.escapeShellArgs runtimeIgnoreLines.shared})
          if ! git ls-files --error-unmatch -- .serena/project.yml >/dev/null 2>&1; then
            lines+=(${lib.escapeShellArg runtimeIgnoreLines.generatedProject})
          fi
        fi
        failed=0
        for line in "''${lines[@]}"; do
          # Directory probes work even before Serena creates the directory.
          if ! git check-ignore -q -- "''${line#/}"; then
            failed=1
          fi
        done
        if [ -n "$(git ls-files --others --exclude-standard -- .serena)" ]; then
          failed=1
        fi
        if [ "$failed" != 0 ]; then
          printf 'Serena runtime is not ignored. Add to %s/.gitignore:\n' "$root"
          printf '%s\n' "''${lines[@]}"
          exit 1
        fi
      '';
    };

  ignoreWarningScript = pkgs: ''
    # Advisory only: never edit ignore policy or affect setup status.
    if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
      if ! serena_ignore_fix="$(${ignoreCheckPackage pkgs}/bin/workbench-serena-ignore 2>&1)"; then
        printf 'Warning: %s (run workbench-serena-ignore)\n' "''${serena_ignore_fix//$'\n'/; }" >&2
      fi
    fi
  '';

  memoryTexts =
    lib.mapAttrs' (name: f: lib.nameValuePair "${name}.md" f.text) acfg.knowledge
    // lib.mapAttrs' (name: path: lib.nameValuePair "${name}.md" (builtins.readFile path)) cfg.deepSources;

  memoriesDir = pkgs:
    pkgs.linkFarm "agentic-memories" (lib.mapAttrsToList (n: text: {
        name = n;
        path = pkgs.writeText n text;
      })
      memoryTexts);

  projectYml = pkgs:
    pkgs.writers.writeYAML "serena-project.yml" (
      lib.optionalAttrs (cfg.projectName != null) {project_name = cfg.projectName;}
      // {
        languages = cfg.languages;
        read_only_memory_patterns = ["${cfg.namespace}/.*"];
      }
      // cfg.extraProjectConfig
    );

  # Idempotent placement: replace ONLY the generated namespace and the
  # generated project.yml; every other memory path is agent-written
  # and untouched.
  placeScript = pkgs: ''
    mkdir -p .serena/memories
    rm -rf ${lib.escapeShellArg ".serena/memories/${cfg.namespace}"}
    cp -RL ${memoriesDir pkgs} ${lib.escapeShellArg ".serena/memories/${cfg.namespace}"}
    chmod -R u+w ${lib.escapeShellArg ".serena/memories/${cfg.namespace}"}
    install -m 644 ${projectYml pkgs} .serena/project.yml
  '';
in {
  options.agentic.memoryPlane = {
    namespace = lib.mkOption {
      type = lib.types.str;
      default = "knowledge";
      description = ''
        Topic directory the generated memories land in
        (`.serena/memories/<namespace>/`). Core fragments reference
        `mem:knowledge/<name>` — changing this breaks those links;
        only do so with a consumer-wide reference rewrite.
      '';
    };

    namespaces = {
      require = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Reject root-level Serena memories unless explicitly allowlisted; namespaced memories are always allowed.";
      };

      allowRoot = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["legacy-finding"];
        description = "Root memory names (without .md) allowed when namespaces.require is true.";
      };
    };

    projectName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "serena project_name (null omits the key).";
    };

    languages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Languages serena starts language servers for (full-shape deployments).";
    };

    deepSources = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      description = ''
        Deep-source documents shipped as memories alongside the
        fragments (name -> markdown file). This is how a bounded
        fragment's "see mem:knowledge/<name>" pointer stays valid in
        every consumer.
      '';
    };

    extraProjectConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Freeform extra keys merged into the generated .serena/project.yml.";
    };

    lib = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = ''
        `memoriesDir pkgs` (the generated namespace content),
        `projectYml pkgs`, `placeScript pkgs` (idempotent shell
        placement), `checkScript pkgs` (reference integrity gate),
        `namespaceCheckScript pkgs` (opt-in root memory namespace gate),
        `namespaceCheckPackage pkgs` (standalone CLI for the same gate),
        `runtimeIgnoreLines` (canonical Serena runtime ignore policy),
        `ignoreCheckPackage pkgs` (read-only workbench-serena-ignore CLI),
        `ignoreWarningScript pkgs` (best-effort shell-entry diagnostic).
        Check scripts run from the repository root.
      '';
    };
  };

  config.agentic.memoryPlane.lib = {
    inherit memoriesDir projectYml placeScript runtimeIgnoreLines ignoreCheckPackage ignoreWarningScript;
    namespaceCheckPackage = pkgs:
      pkgs.writeShellScriptBin "serena-memory-namespaces" ''
        set -euo pipefail
        ${cfg.lib.namespaceCheckScript pkgs}
      '';
    namespaceCheckScript = pkgs:
      if !cfg.namespaces.require
      then ":"
      else ''
        (
          shopt -s nullglob dotglob
          status=0
          for memory in .serena/memories/*.md; do
            [ -f "$memory" ] || continue
            name="''${memory##*/}"
            name="''${name%.md}"
            allowed=0
            for allowed_name in ${lib.escapeShellArgs cfg.namespaces.allowRoot}; do
              if [ "$name" = "$allowed_name" ]; then
                allowed=1
                break
              fi
            done
            [ "$allowed" = 0 ] || continue
            printf 'Un-namespaced Serena memory: %s\n' "$memory"
            status=1
          done
          if [ "$status" != 0 ]; then
            echo 'Fix: move into a namespace with serena rename_memory so mem: references stay valid.'
            exit 1
          fi
        )
      '';
    # `serena memories check` always exits 0 by design — CI must gate
    # on the report text instead. This script fails on any finding.
    #
    # The CLI resolves `.` only through the global project registry
    # (serena_config.yml `projects:`), never by auto-registering an
    # existing .serena/project.yml — so a fresh HOME (build sandbox,
    # CI) reports "No Serena project found". Register the cwd in a
    # throwaway SERENA_HOME so the operator's real registry is never
    # touched when this runs outside a sandbox.
    checkScript = pkgs: ''
      serena_home="$(mktemp -d)"
      printf 'projects:\n- %s\n' "$PWD" >"$serena_home/serena_config.yml"
      serena_report="$(SERENA_HOME="$serena_home" ${config.agentic.serena.lib.serenaPackage pkgs}/bin/serena memories check .)"
      rm -rf "$serena_home"
      printf '%s\n' "$serena_report"
      printf '%s' "$serena_report" | grep -qF '✓ No referential integrity issues found.'
    '';
  };
}
