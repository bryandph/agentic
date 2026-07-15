# Fixture checks for the agent + knowledge registry (tasks 3.1-3.4):
# fragment schema (plain .md files, size bound, unknown-ref failure),
# agent composition (capability-derived platform grants, per-platform
# overrides, uniform scope language), and the AGENTS.md / CLAUDE.md
# generation (writer app, do-not-edit header, nested scopes,
# hand-written files outside scopes untouched).
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
    inherit (pkgs) lib;

    fixtureModule = {config, ...}: {
      agentic.knowledge = {
        fixture-conventions.file = ./_fixtures/fixture-conventions.md;
        fixture-review = {
          file = ./_fixtures/fixture-review.md;
          title = "Review discipline";
        };
      };

      agentic.agents = {
        builder = {
          description = "Fixture agent with full capabilities and overrides.";
          fragments = ["fixture-conventions" "fixture-review"];
          scope = {
            paths = ["modules/"];
            forbidden = ["secrets/"];
            delegateTo = ["reviewer"];
          };
          capabilities = {
            edit = true;
            exec = true;
            web = true;
          };
          mcp = ["serena"];
          claude.extraTools = ["TaskCreate" "AskUserQuestion"];
          opencode.permission.bash = "ask";
        };

        reviewer = {
          description = "Fixture read-only agent.";
          fragments = ["fixture-review"];
          scope.forbidden = ["secrets/"];
          mcp = ["serena"];
        };
      };

      agentic.instructions.scopes = {
        "." = {
          fragments = ["fixture-conventions" "fixture-review"];
        };
        "sub/dir".fragments = ["fixture-review"];
      };

      flake.agenticProbe = {
        builderClaude = config.agentic.agentsLib.renderClaude "builder" config.agentic.agents.builder;
        builderOpencode = config.agentic.agentsLib.renderOpencode "builder" config.agentic.agents.builder;
        reviewerClaude = config.agentic.agentsLib.renderClaude "reviewer" config.agentic.agents.reviewer;
        reviewerOpencode = config.agentic.agentsLib.renderOpencode "reviewer" config.agentic.agents.reviewer;
        renderedFiles = config.agentic.instructions.lib.renderedFiles;
      };
    };

    fixture = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [system];
      imports = [config.flake.flakeModules.default fixtureModule];
    };

    # Negative fixtures: oversized fragment and unknown references must
    # fail eval with a message naming the culprit.
    failing = module: probe:
      !(builtins.tryEval (builtins.deepSeq ((inputs.flake-parts.lib.mkFlake {inherit inputs;} {
          systems = [system];
          imports = [config.flake.flakeModules.default module];
        })
            .agenticProbe
            .${
          probe
        })
      true))
      .success;

    oversizedFails = failing ({config, ...}: {
      agentic.fragmentSizeBound = 16;
      agentic.knowledge.fixture-conventions.file = ./_fixtures/fixture-conventions.md;
      flake.agenticProbe.text = config.agentic.knowledge.fixture-conventions.text;
    }) "text";

    unknownFragmentFails = failing ({config, ...}: {
      agentic.agents.broken = {
        description = "references a fragment no layer defines";
        fragments = ["nonexistent-topic"];
      };
      flake.agenticProbe.body = config.agentic.agentsLib.renderClaude "broken" config.agentic.agents.broken;
    }) "body";

    p = fixture.agenticProbe;

    scopeLine = "Never read, modify, or act on: `secrets/`.";
  in {
    checks.agents-registry =
      # Capability-derived Claude grants + overrides win/augment.
      assert lib.hasInfix "Edit" p.builderClaude;
      assert lib.hasInfix "Bash" p.builderClaude;
      assert lib.hasInfix "WebFetch" p.builderClaude;
      assert lib.hasInfix "mcp__serena" p.builderClaude;
      assert lib.hasInfix "TaskCreate, AskUserQuestion" p.builderClaude;
      # Restricted agent: no edit/exec/web grants derived.
      assert !lib.hasInfix "Edit" p.reviewerClaude;
      assert !lib.hasInfix "Bash" p.reviewerClaude;
      assert !lib.hasInfix "WebFetch" p.reviewerClaude;
      # OpenCode: derived permission map, override wins (bash ask), V1
      # `permission:` frontmatter.
      assert lib.hasInfix ''"bash":"ask"'' p.builderOpencode;
      assert lib.hasInfix ''"edit":"allow"'' p.builderOpencode;
      assert lib.hasInfix ''"edit":"deny"'' p.reviewerOpencode;
      assert lib.hasInfix "permission: {" p.builderOpencode;
      # Uniform scope language from the structured field.
      assert lib.hasInfix scopeLine p.builderClaude;
      assert lib.hasInfix scopeLine p.reviewerClaude;
      # Fragments compose in order with titles.
      assert lib.hasInfix "## fixture-conventions" p.builderClaude;
      assert lib.hasInfix "## Review discipline" p.builderClaude;
      # Negative cases.
      assert oversizedFails;
      assert unknownFragmentFails;
      # Instruction projections exist for every declared scope + shim.
      assert lib.attrNames p.renderedFiles == ["AGENTS.md" "CLAUDE.md" "sub/dir/AGENTS.md"];
      assert lib.hasInfix "GENERATED FILE" p.renderedFiles."AGENTS.md";
      assert lib.hasInfix "@AGENTS.md" p.renderedFiles."CLAUDE.md";
      # CLI equivalents surface in the root file only (Pi coverage).
      assert lib.hasInfix "CLI equivalents" p.renderedFiles."AGENTS.md";
      assert !lib.hasInfix "CLI equivalents" p.renderedFiles."sub/dir/AGENTS.md";
        pkgs.runCommand "agentic-agents-registry" {
          nativeBuildInputs = [pkgs.gnugrep];
        } ''
          set -euo pipefail
          cd "$TMPDIR"

          # Hand-written nested AGENTS.md outside declared scopes must
          # survive the writer byte-identical.
          mkdir -p other
          echo "hand-written — do not clobber" > other/AGENTS.md

          ${fixture.apps.${system}.write-agent-instructions.program}

          [ -f AGENTS.md ] && [ -f CLAUDE.md ] && [ -f sub/dir/AGENTS.md ]
          grep -qF 'GENERATED FILE' AGENTS.md
          grep -qF 'Fixture conventions card' AGENTS.md
          grep -qF '@AGENTS.md' CLAUDE.md
          grep -qF 'Fixture review card' sub/dir/AGENTS.md
          [ "$(cat other/AGENTS.md)" = "hand-written — do not clobber" ]

          # Idempotency: a second run changes nothing.
          cp AGENTS.md before.md
          ${fixture.apps.${system}.write-agent-instructions.program}
          cmp AGENTS.md before.md

          touch $out
        '';
  };
}
