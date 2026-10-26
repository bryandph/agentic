# Fixture check for work tracking and the knowledge bundle: the placed Backlog.md
# config makes upstream `backlog` accept exactly the configured
# lifecycle, extra frontmatter survives CLI edits (bundle links and migration
# metadata rely on it), core skills join the library only for enabled
# capabilities, and the bundle switches knowledge search to a local index.
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
    enabled = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [system];
      imports = [
        config.flake.flakeModules.default
        ({config, ...}: {
          agentic.workTracking = {
            prefix = "fix";
            projectName = "fixture";
            labels = ["fixture-subsystem"];
          };
          agentic.bundle = {
            root = ".okf";
            children = ["child/.okf"];
          };
          flake.agenticProbe = {
            skills = builtins.attrNames config.agentic.skills.library;
            renderedSkills = builtins.attrNames config.agentic.skills.lib.renderedFiles;
            index = config.agentic.knowledgeSearch.index;
            collections = config.agentic.knowledgeSearch.collections;
          };
          perSystem = {pkgs, ...}: {
            packages.fixture-place = pkgs.writeShellScript "fixture-place" (config.agentic.workTracking.lib.placeScript pkgs);
            packages.fixture-qmd-wrapper = config.agentic.knowledgeSearch.lib.wrapper pkgs;
            packages.fixture-backlog = config.agentic.workTracking.lib.package pkgs;
          };
        })
      ];
    };
    p = enabled.agenticProbe;

    disabled = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [system];
      imports = [
        config.flake.flakeModules.default
        ({config, ...}: {
          flake.agenticProbe = {
            skills = builtins.attrNames config.agentic.skills.library;
            index = config.agentic.knowledgeSearch.index;
            packages = config.agentic.devenvLib.packages pkgs;
          };
        })
      ];
    };
    q = disabled.agenticProbe;

    backlog = enabled.packages.${system}.fixture-backlog;
  in {
    checks.work-tracking = assert p.skills == ["memory" "work-tracking"];
    assert builtins.elem ".agents/skills/work-tracking/SKILL.md" p.renderedSkills;
    assert p.index == "local";
    assert p.collections.okf.path == ".okf";
    assert p.collections.child.path == "child/.okf";
    assert q.skills == [];
    assert q.index == "user";
    # Only the two always-present worktree commands; no optional tracking/search.
    assert map (p: p.name) q.packages == ["workbench-worktree-setup" "workbench-worktree-teardown"];
      pkgs.runCommand "agentic-work-tracking" {
        nativeBuildInputs = [pkgs.git pkgs.gnugrep backlog];
      } ''
        set -euo pipefail
        export HOME=$TMPDIR/home
        mkdir -p $HOME repo && cd repo
        git init -q && git -c user.name=f -c user.email=f@fixture.example commit -q --allow-empty -m init

        ${enabled.packages.${system}.fixture-place}
        grep -qF 'task_prefix: "fix"' backlog/config.yml

        # The configured lifecycle is enforced by upstream.
        backlog task create "Probe" -s Planning --priority major -l fixture-subsystem --type Epic --plain >/dev/null
        backlog task view FIX-1 --plain | grep -q "Planning"
        grep -qi '^type: epic' backlog/tasks/*.md
        if backlog task create "Wrong type" --type chore --plain >/dev/null 2>&1; then
          echo "an unconfigured type was accepted"; exit 1
        fi
        if backlog task edit FIX-1 -s "To Do" --plain >/dev/null 2>&1; then
          echo "an unconfigured status was accepted"; exit 1
        fi

        # Extra frontmatter survives a CLI edit.
        f=$(ls backlog/tasks/*.md)
        awk 'NR > 1 && /^---$/ && !done { print "fixture_ref: kept"; done = 1 } { print }' "$f" > "$f.new"
        mv "$f.new" "$f"
        grep -q '^fixture_ref: kept' "$f"
        backlog task edit FIX-1 -s Implementing --plain >/dev/null
        grep -q '^fixture_ref: kept' "$f"
        grep -q '^status: Implementing' "$f"

        # Bundle search uses a project-local index.
        grep -qF 'init >/dev/null' ${enabled.packages.${system}.fixture-qmd-wrapper}/bin/qmd-knowledge

        touch $out
      '';
  };
}
