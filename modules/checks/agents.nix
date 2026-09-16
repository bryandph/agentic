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
          description = ''Fixture: "quoted" description with full capabilities.'';
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
          claude.model = "haiku";
          claude.maxTurns = 8;
          codex = {
            model = "fixture-small";
            reasoningEffort = "low";
          };
          opencode.model = "fixture/small";
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
        builderCodex = builtins.fromTOML (config.agentic.agentsLib.renderCodex "builder" config.agentic.agents.builder);
        builderOpencode = config.agentic.agentsLib.renderOpencode "builder" config.agentic.agents.builder;
        builderPi = config.agentic.agentsLib.renderPi "builder" config.agentic.agents.builder;
        builderBody = config.agentic.agentsLib.compileBody "builder" config.agentic.agents.builder;
        reviewerPi = config.agentic.agentsLib.renderPi "reviewer" config.agentic.agents.reviewer;
        reviewerClaude = config.agentic.agentsLib.renderClaude "reviewer" config.agentic.agents.reviewer;
        reviewerCodex = builtins.fromTOML (config.agentic.agentsLib.renderCodex "reviewer" config.agentic.agents.reviewer);
        reviewerOpencode = config.agentic.agentsLib.renderOpencode "reviewer" config.agentic.agents.reviewer;
        renderedFiles = config.agentic.instructions.lib.renderedFiles;
        placeAgents = config.agentic.agentsLib.placeScript pkgs;
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
      # Codex roles parse as native TOML and carry the exact shared body.
      assert p.builderCodex.name == "builder";
      assert p.builderCodex.developer_instructions == p.builderBody;
      assert p.builderCodex.model == "fixture-small";
      assert p.builderCodex.model_reasoning_effort == "low";
      # The supported Codex role overrides inherit the parent's sandbox.
      assert !(p.builderCodex ? sandbox_mode);
      assert !(p.reviewerCodex ? model);
      assert !(p.reviewerCodex ? model_reasoning_effort);
      assert !(p.reviewerCodex ? sandbox_mode);
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
      # Pi consumes the same compiled body as an ordinary prompt template.
      assert lib.hasInfix p.builderBody p.builderPi;
      assert lib.hasInfix scopeLine p.builderPi;
      assert lib.hasInfix "File edits: permitted" p.builderPi;
      assert lib.hasInfix "File edits: not permitted" p.reviewerPi;
      assert lib.hasInfix "workmux owns" p.builderPi;
      assert lib.hasInfix "$ARGUMENTS" p.builderPi;
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
          nativeBuildInputs = [pkgs.gnugrep (pkgs.python3.withPackages (ps: [ps.pyyaml]))];
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

          roles=${fixture.packages.${system}.pi-agent-roles}
          test -f "$roles/package.json"
          grep -qF 'Fixture conventions card' "$roles/prompts/role-builder.md"
          grep -qF 'Shell commands: not permitted' "$roles/prompts/role-reviewer.md"

          # Real parsers catch quoting/newline errors in generated files.
          mkdir placement
          cd placement
          ${fixture.apps.${system}.write-agent-roles.program}
          ${p.placeAgents}
          python - <<'PY'
          import os
          import pathlib
          import tomllib
          import yaml

          def frontmatter(path):
              return yaml.safe_load(pathlib.Path(path).read_text().split('---', 2)[1])

          claude = frontmatter('.claude/agents/builder.md')
          opencode = frontmatter('.opencode/agents/builder.md')
          codex = tomllib.loads(pathlib.Path('.codex/agents/builder.toml').read_text())
          assert claude['description'] == codex['description'] == opencode['description']
          assert claude['model'] == 'haiku'
          assert claude['maxTurns'] == 8
          assert opencode['model'] == 'fixture/small'
          assert 'model' not in frontmatter('.claude/agents/reviewer.md')
          assert 'model' not in frontmatter('.opencode/agents/reviewer.md')
          assert set(p.stem for p in pathlib.Path('.codex/agents').glob('*.toml')) == {'builder', 'reviewer'}
          # Match Codex's launch-time loader, not just its discovery parser.
          # Directory symlinks are supported; final-component symlinks are not.
          for path in pathlib.Path('.codex/agents').glob('*.toml'):
              assert not path.is_symlink(), path
              fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
              with os.fdopen(fd) as handle:
                  assert tomllib.loads(handle.read())['name'] == path.stem
          PY

          # Collision refusal must leave user files and other destinations intact.
          mkdir -p ../collision/.codex/agents
          cd ../collision
          echo 'keep me' > .codex/agents/personal.toml
          if ( ${p.placeAgents} ); then
            echo 'unmanaged agent directory unexpectedly replaced' >&2
            exit 1
          fi
          test "$(cat .codex/agents/personal.toml)" = 'keep me'
          test ! -e .claude
          rm .codex/agents/personal.toml
          ${p.placeAgents}
          test -L .codex/agents

          touch $out
        '';
  };
}
