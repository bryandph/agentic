# Fixture check for the knowledge memory plane (task 3.4c): fragments +
# deep sources render into the read-only namespace, project.yml is
# generated from options, regeneration replaces only the namespace
# (agent-written memories survive), and `serena memories check` passes
# on the generated corpus — and fails on a stale mem: reference.
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
    fixture = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [system];
      imports = [
        config.flake.flakeModules.default
        ({config, ...}: {
          agentic.knowledge = {
            fixture-conventions.file = ./_fixtures/fixture-conventions.md;
            fixture-review.file = ./_fixtures/fixture-review.md;
          };

          agentic.memoryPlane = {
            projectName = "fixture";
            languages = ["nix"];
            deepSources.fixture-deep = ./_fixtures/fixture-review.md;
          };

          perSystem = {pkgs, ...}: {
            packages = {
              fixture-place = pkgs.writeShellScript "place" (config.agentic.memoryPlane.lib.placeScript pkgs);
              fixture-project-yml = config.agentic.memoryPlane.lib.projectYml pkgs;
              fixture-check = pkgs.writeShellScript "check" (config.agentic.memoryPlane.lib.checkScript pkgs);
            };
          };
        })
      ];
    };
  in {
    checks.memory-plane = let
      placeScript = fixture.packages.${system}.fixture-place;
      checkScript = fixture.packages.${system}.fixture-check;
    in
      pkgs.runCommand "agentic-memory-plane" {
        nativeBuildInputs = [pkgs.gnugrep];
      } ''
        set -euo pipefail
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME" "$TMPDIR/repo"
        cd "$TMPDIR/repo"

        # Agent-written memory that must survive regeneration.
        mkdir -p .serena/memories/infra
        echo "agent-written finding" > .serena/memories/infra/finding.md

        ${placeScript}

        [ -f .serena/memories/knowledge/fixture-conventions.md ]
        [ -f .serena/memories/knowledge/fixture-review.md ]
        [ -f .serena/memories/knowledge/fixture-deep.md ]
        [ "$(cat .serena/memories/infra/finding.md)" = "agent-written finding" ]
        grep -qF 'read_only_memory_patterns' .serena/project.yml
        grep -qF 'knowledge/.*' .serena/project.yml
        grep -qF 'project_name: fixture' .serena/project.yml

        # Regeneration is idempotent and namespace-scoped.
        ${placeScript}
        [ "$(cat .serena/memories/infra/finding.md)" = "agent-written finding" ]

        # Reference integrity over the generated corpus (the
        # fixture-conventions card links mem:knowledge/fixture-review),
        # through the same report-gated script consumers wire into CI.
        # The sandbox HOME has no serena project registry, so this also
        # covers the script's own registration.
        ${checkScript}

        # A stale reference must fail the gate and surface in the report.
        echo "see mem:knowledge/does-not-exist" > .serena/memories/infra/stale.md
        if stale_report="$(${checkScript})"; then
          echo "stale mem: reference unexpectedly passed" >&2
          exit 1
        fi
        printf '%s' "$stale_report" | grep -qF 'Stale references (1):'

        touch $out
      '';
  };
}
