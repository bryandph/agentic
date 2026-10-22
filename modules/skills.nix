# Agent skills (Agent Skills format): canonical SKILL.md bodies rendered
# into `.claude/skills/<name>/SKILL.md`, with a `.agents/skills/<name>`
# wrapper pointing at it for harnesses that discover the Agent Skills
# location (Pi, Codex). Like AGENTS.md, the rendered files are COMMITTED
# and drift-checked, so every harness and forge view sees the same
# skills without a shell.
#
# Core ships skills for the capabilities it wires (work tracking,
# memory); they join the library when the capability is enabled.
# Consumers add their own entries to the same attrset.
{
  flake.modules.flake.agentic = {
    lib,
    config,
    ...
  }: let
    cfg = config.agentic.skills;
    acfg = config.agentic;

    skillType = lib.types.submodule ({name, ...}: {
      options = {
        canonical = lib.mkOption {
          type = lib.types.path;
          description = "Canonical SKILL.md (with name/description frontmatter) for ${name}.";
        };
        description = lib.mkOption {
          type = lib.types.str;
          description = "Short description used in the .agents/skills/${name}/SKILL.md wrapper.";
        };
        title = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Markdown heading for the .agents wrapper.";
        };
      };
    });

    renderAgentWrapper = name: skill: ''
      ---
      name: ${name}
      description: ${builtins.toJSON skill.description}
      ---

      # ${skill.title}

      Read and follow the canonical workflow in
      `../../../.claude/skills/${name}/SKILL.md` completely.
    '';

    renderedFiles =
      lib.concatMapAttrs (name: skill: {
        ".claude/skills/${name}/SKILL.md" = builtins.readFile skill.canonical;
        ".agents/skills/${name}/SKILL.md" = renderAgentWrapper name skill;
      })
      cfg.library;
  in {
    options.agentic.skills = {
      library = lib.mkOption {
        type = lib.types.attrsOf skillType;
        default = {};
        description = "Skills rendered into .claude and .agents skill directories.";
      };

      selfPath = lib.mkOption {
        type = lib.types.path;
        default = acfg.instructions.selfPath;
        defaultText = lib.literalExpression "config.agentic.instructions.selfPath";
        description = "Committed source tree the drift check compares against.";
      };

      driftCheck = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enforce committed-vs-rendered skill drift checks.";
      };

      lib = lib.mkOption {
        type = lib.types.raw;
        readOnly = true;
        description = "`renderedFiles`: repo-relative path -> text.";
      };
    };

    config = lib.mkMerge [
      {agentic.skills.lib = {inherit renderedFiles;};}

      (lib.mkIf (acfg.workTracking.prefix != null) {
        agentic.skills.library.work-tracking = {
          canonical = ../skills/work-tracking/SKILL.md;
          title = "Work tracking";
          description = "Track this repository's work as Backlog.md tasks: find, shape, plan, execute and hand over work under the shared lifecycle. Use before creating, changing or finishing a task, and when work needs planning, a decision or review.";
        };
      })

      (lib.mkIf (acfg.bundle.root != null) {
        agentic.skills.library.memory = {
          canonical = ../skills/memory/SKILL.md;
          title = "Memory";
          description = "Search, propose and curate this repository's knowledge bundle (Open Knowledge Format): specs, decisions and memory. Use before designing or answering why something is the way it is, when a change touches a contract, and when a session learns something a later session should know.";
        };
      })

      (lib.mkIf (cfg.library != {}) {
        perSystem = {pkgs, ...}: let
          renderedDir = pkgs.linkFarm "agent-skills" (lib.mapAttrsToList (path: text: {
              name = path;
              path = pkgs.writeText (builtins.baseNameOf path) text;
            })
            renderedFiles);
        in {
          apps.write-agent-skills.program = pkgs.writeShellApplication {
            name = "write-agent-skills";
            text = lib.concatStringsSep "\n" (lib.mapAttrsToList (path: _: ''
                mkdir -p "$(dirname ${lib.escapeShellArg path})"
                install -m 644 ${renderedDir}/${lib.escapeShellArg path} ${lib.escapeShellArg path}
                echo "wrote ${path}"
              '')
              renderedFiles);
          };

          checks = lib.mkIf cfg.driftCheck {
            agent-skills-drift =
              pkgs.runCommand "agent-skills-drift" {
                nativeBuildInputs = [pkgs.diffutils];
              } ''
                set -euo pipefail
                status=0
                ${lib.concatStringsSep "\n" (lib.mapAttrsToList (path: _: ''
                    if [ ! -f ${cfg.selfPath}/${lib.escapeShellArg path} ]; then
                      echo "MISSING: ${path} is not committed. Generate it with: nix run .#write-agent-skills"
                      status=1
                    elif ! diff -u ${cfg.selfPath}/${lib.escapeShellArg path} ${renderedDir}/${lib.escapeShellArg path}; then
                      echo "DRIFT: ${path} differs from the rendered projection. Regenerate with: nix run .#write-agent-skills"
                      status=1
                    fi
                  '')
                  renderedFiles)}
                [ "$status" = 0 ] && touch $out
              '';
          };
        };
      })
    ];
  };
}
