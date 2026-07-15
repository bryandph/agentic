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
  flake.modules.flake.agentic = {
    lib,
    config,
    ...
  }: let
    cfg = config.agentic.memoryPlane;
    acfg = config.agentic;

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
          placement), `checkCommand pkgs` (serena memories check argv
          for CI).
        '';
      };
    };

    config.agentic.memoryPlane.lib = {
      inherit memoriesDir projectYml placeScript;
      # `serena memories check` always exits 0 by design — CI must gate
      # on the report text instead. This script fails on any finding.
      checkScript = pkgs: ''
        serena_report="$(${config.agentic.serena.lib.serenaPackage pkgs}/bin/serena memories check .)"
        printf '%s\n' "$serena_report"
        printf '%s' "$serena_report" | grep -qF '✓ No referential integrity issues found.'
      '';
    };
  };
}
