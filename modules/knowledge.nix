# Knowledge fragments (design D5/D11, agentic-agents spec).
#
# `agentic.knowledge.<topic>` are bounded-size markdown convention cards
# — reusable expertise composed into agents (modules/agents.nix),
# rendered into AGENTS.md and the serena memory plane. Format decision
# (design Open Question 2, resolved here): fragments are PLAIN `.md`
# FILES read via builtins.readFile — editable, reviewable, no nix noise
# in prose. Layers merge naturally: core ships org-neutral subject
# cards, env layers and repos contribute their own into the same
# attrset.
#
# Size bound: fragments point at deeper sources instead of inlining
# exhaustive detail. Deep-source references must be visible to every
# consumer of the fragment's layer — core fragments may reference
# `mem:` names only for memories core itself ships (the memory plane
# renders them into every consumer); env/repo fragments may reference
# their own layer's sources. `serena memories check` (CI) enforces
# reference integrity.
{
  flake.modules.flake.agentic = {
    lib,
    config,
    ...
  }: let
    cfg = config.agentic;

    fragmentType = lib.types.submodule ({
      name,
      config,
      ...
    }: {
      options = {
        file = lib.mkOption {
          type = lib.types.path;
          description = "Plain markdown fragment file.";
        };

        title = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Heading used when the fragment is rendered into composed documents.";
        };

        text = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = "Fragment content (size-bound enforced on read).";
        };
      };

      config.text = let
        raw = builtins.readFile config.file;
        len = builtins.stringLength raw;
      in
        if len > cfg.fragmentSizeBound
        then
          throw ''
            agentic.knowledge.${name}: fragment is ${toString len} bytes, exceeding the ${toString cfg.fragmentSizeBound}-byte bound.
            Fragments are convention cards — move depth into a serena memory / spec / doc and point at it.''
        else raw;
    });
  in {
    options.agentic = {
      knowledge = lib.mkOption {
        type = lib.types.attrsOf fragmentType;
        default = {};
        description = "Knowledge fragments, merged across layers (core + env + repo).";
      };

      fragmentSizeBound = lib.mkOption {
        type = lib.types.int;
        default = 8192;
        description = "Maximum fragment size in bytes (convention-card bound).";
      };

      knowledgeLib = lib.mkOption {
        type = lib.types.raw;
        readOnly = true;
        description = "Helpers: `fragment <name>` (resolve + validate a fragment reference, throws naming the missing fragment).";
      };
    };

    config.agentic.knowledgeLib = {
      fragment = name:
        cfg.knowledge.${name}
        or (throw "unknown knowledge fragment \"${name}\" — defined fragments: ${lib.concatStringsSep ", " (lib.attrNames cfg.knowledge)}");
    };
  };
}
