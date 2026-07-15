# Generated AGENTS.md + CLAUDE.md shim (design D5, agentic-agents spec).
#
# AGENTS.md is the cross-tool instruction channel — it reaches Codex,
# Pi, Gemini, OpenCode, and any platform without a subagent format. It
# is GENERATED from the repo's declared fragment set and COMMITTED (not
# a shell-entry symlink): non-nix consumers (forge web UIs, cloud
# agents, CI, collaborators without direnv) must see it. CI fails on
# drift between the committed file and the rendered projection.
#
# Claude Code does not read AGENTS.md natively — CLAUDE.md is a
# generated shim containing an `@AGENTS.md` import.
#
# Directory-scoped sets: `agentic.instructions.scopes.<dir>` renders a
# nested <dir>/AGENTS.md (nearest-file-wins per the standard).
# Generation only ever touches the declared scopes — hand-written
# nested AGENTS.md files outside them are never written or checked.
#
# Deliberately NOT built on mightyiam/files: its internals require the
# `pipe-operators` experimental feature, which core must not impose on
# every consumer. The writer app + drift check below are the same
# pattern, self-contained.
{
  flake.modules.flake.agentic = {
    lib,
    config,
    inputs,
    ...
  }: let
    cfg = config.agentic.instructions;
    acfg = config.agentic;

    header = fragments: ''
      <!-- GENERATED FILE — DO NOT EDIT.
           Rendered from agentic.knowledge fragments: ${lib.concatStringsSep ", " fragments}.
           Durable additions belong in fragments (or serena memories) — never here.
           Regenerate: nix run .#write-agent-instructions -->
    '';

    renderFragments = fragments:
      lib.concatMapStrings (fname: let
        f = acfg.knowledgeLib.fragment fname;
      in ''

        ## ${f.title}

        ${f.text}
      '')
      fragments;

    cliSection = let
      clis = acfg.mcp.lib.cliEquivalents;
    in
      lib.optionalString (clis != {}) ''

        ## CLI equivalents (harnesses without MCP)

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: c: "- `${n}`: ${c}") clis)}
      '';

    renderAgentsMd = scopeDir: scope: ''
      ${header scope.fragments}
      # AGENTS.md

      ${scope.intro}${renderFragments scope.fragments}${lib.optionalString (scopeDir == ".") cliSection}'';

    claudeMd = ''
      <!-- GENERATED FILE — DO NOT EDIT. Claude Code shim: the shared
           instructions live in AGENTS.md (imported below).
           Regenerate: nix run .#write-agent-instructions -->
      @AGENTS.md
    '';

    scopeType = lib.types.submodule {
      options = {
        fragments = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Ordered fragment references rendered into this scope's AGENTS.md.";
        };
        intro = lib.mkOption {
          type = lib.types.str;
          default = "This file provides guidance to AI coding assistants working in this repository.\n";
          description = "Lead-in text before the fragment sections.";
        };
      };
    };
  in {
    options.agentic.instructions = {
      scopes = lib.mkOption {
        type = lib.types.attrsOf scopeType;
        default = {};
        description = ''
          Directory-scoped fragment sets ("." = repo root). Each scope
          renders <dir>/AGENTS.md; the root scope also renders the
          CLAUDE.md @AGENTS.md shim. Hand-written AGENTS.md files
          outside declared scopes are never touched.
        '';
      };

      selfPath = lib.mkOption {
        type = lib.types.path;
        default = "${inputs.self}";
        defaultText = lib.literalExpression "inputs.self";
        description = "Committed source tree the drift check compares against.";
      };

      lib = lib.mkOption {
        type = lib.types.raw;
        readOnly = true;
        description = "Rendered projections: `renderedScopes` (dir -> text), `claudeMd`, `renderedFiles` (repo-relative path -> text).";
      };
    };

    config = lib.mkIf (cfg.scopes != {}) {
      agentic.instructions.lib = {
        renderedScopes = lib.mapAttrs renderAgentsMd cfg.scopes;
        inherit claudeMd;
        renderedFiles =
          lib.mapAttrs' (dir: scope: {
            name =
              if dir == "."
              then "AGENTS.md"
              else "${dir}/AGENTS.md";
            value = renderAgentsMd dir scope;
          })
          cfg.scopes
          // lib.optionalAttrs (cfg.scopes ? ".") {"CLAUDE.md" = claudeMd;};
      };

      perSystem = {pkgs, ...}: let
        renderedFiles = cfg.lib.renderedFiles;

        renderedDir = pkgs.linkFarm "agent-instructions" (lib.mapAttrsToList (path: text: {
            name = path;
            path = pkgs.writeText (builtins.baseNameOf path) text;
          })
          renderedFiles);
      in {
        # Writer: (re)generate every declared scope in the working tree.
        # Idempotent — output is a pure projection of the fragment set.
        apps.write-agent-instructions.program = pkgs.writeShellApplication {
          name = "write-agent-instructions";
          text = lib.concatStringsSep "\n" (lib.mapAttrsToList (path: _: ''
              mkdir -p "$(dirname ${lib.escapeShellArg path})"
              install -m 644 ${renderedDir}/${lib.escapeShellArg path} ${lib.escapeShellArg path}
              echo "wrote ${path}"
            '')
            renderedFiles);
        };

        # Drift check: committed files must equal the rendered projection.
        checks.agent-instructions-drift =
          pkgs.runCommand "agent-instructions-drift" {
            nativeBuildInputs = [pkgs.diffutils];
          } ''
            set -euo pipefail
            status=0
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: _: ''
                if [ ! -f ${cfg.selfPath}/${lib.escapeShellArg path} ]; then
                  echo "MISSING: ${path} is not committed. Generate it with: nix run .#write-agent-instructions"
                  status=1
                elif ! diff -u ${cfg.selfPath}/${lib.escapeShellArg path} ${renderedDir}/${lib.escapeShellArg path}; then
                  echo "DRIFT: ${path} differs from the rendered projection. Regenerate with: nix run .#write-agent-instructions"
                  status=1
                fi
              '')
              renderedFiles)}
            [ "$status" = 0 ] && touch $out
          '';
      };
    };
  };
}
