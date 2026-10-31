# Exercise the consumer-facing check, not a duplicate namespace scanner.
{
  inputs,
  config,
  lib,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    source = roots:
      pkgs.runCommand "memory-namespace-fixture" {} ''
        mkdir -p "$out/.serena/memories/infra/nested" "$out/.serena/memories/knowledge"
        echo finding > "$out/.serena/memories/infra/nested/finding.md"
        echo generated > "$out/.serena/memories/knowledge/card.md"
        # Directories ending in .md and non-markdown files aren't memories.
        mkdir -p "$out/.serena/memories/directory.md"
        touch "$out/.serena/memories/notes.txt"
        ${lib.concatMapStringsSep "\n" (name: ''
            echo finding > "$out/.serena/memories/"${lib.escapeShellArg "${name}.md"}
          '')
          roots}
      '';
    fixture = require: allowRoot: roots:
      inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [
          config.flake.flakeModules.default
          ({config, ...}: {
            agentic.instructions.selfPath = source roots;
            agentic.memoryPlane.namespaces =
              lib.optionalAttrs (require != null) {inherit require;}
              // lib.optionalAttrs (allowRoot != null) {inherit allowRoot;};
            flake.lib.namespaceCliDelivered = pkgs:
              lib.any (package: package.outPath == (config.agentic.memoryPlane.lib.namespaceCheckPackage pkgs).outPath)
              (config.agentic.devenvLib.packages pkgs);
            perSystem = {pkgs, ...}: {
              packages = {
                namespace-cli = config.agentic.memoryPlane.lib.namespaceCheckPackage pkgs;
                namespace-place = pkgs.writeShellScript "place" (config.agentic.memoryPlane.lib.placeScript pkgs);
                namespace-off = pkgs.writeShellScript "off" (config.agentic.memoryPlane.lib.namespaceCheckScript pkgs);
              };
            };
          })
        ];
      };
    rootNames = ["legacy" "other finding" ".hidden"];
    off = fixture null null rootNames;
    violations = fixture true null rootNames;
    allowlisted = fixture true rootNames rootNames;
    namespaced = fixture true [] [];
    check = f: f.checks.${system}.serena-memory-namespaces;
    failingCheck = pkgs.writeShellScript "violating-consumer-check" (check violations).buildCommand;
  in {
    checks.memory-namespaces = assert !(off.checks.${system} ? serena-memory-namespaces);
    assert !(off.lib.namespaceCliDelivered pkgs);
    assert namespaced.lib.namespaceCliDelivered pkgs;
      pkgs.runCommand "agentic-memory-namespaces" {
        nativeBuildInputs = [pkgs.gnugrep];
        # These build the actual consumer checks with allowed/namespaced memories.
        passedChecks = [(check allowlisted) (check namespaced)];
      } ''
        set -euo pipefail
        mkdir repo
        cd repo
        mkdir -p .serena/memories
        echo legacy > .serena/memories/legacy.md
        ${off.packages.${system}.namespace-off}

        if report="$(${failingCheck} 2>&1)"; then
          echo "un-namespaced memories unexpectedly passed" >&2
          exit 1
        fi
        printf '%s\n' "$report"
        ${lib.concatMapStringsSep "\n" (name: ''
            printf '%s\n' "$report" | grep -qxF ${lib.escapeShellArg "Un-namespaced Serena memory: .serena/memories/${name}.md"}
          '')
          rootNames}
        printf '%s\n' "$report" | grep -qF 'move into a namespace with serena rename_memory so mem: references stay valid'

        # The CLI uses the same gate on the live checkout.
        if ${namespaced.packages.${system}.namespace-cli}/bin/serena-memory-namespaces; then
          echo "CLI unexpectedly accepted a root memory" >&2
          exit 1
        fi
        rm .serena/memories/legacy.md
        # No memory directory is also valid.
        rmdir .serena/memories .serena
        ${namespaced.packages.${system}.namespace-cli}/bin/serena-memory-namespaces

        # Placement and regeneration retain the same generated, read-only namespace.
        ${namespaced.packages.${system}.namespace-place}
        grep -qF 'knowledge/.*' .serena/project.yml
        [ -f .serena/memories/knowledge/serena-usage.md ]
        mkdir -p .serena/memories/infra
        echo finding > .serena/memories/infra/finding.md
        ${namespaced.packages.${system}.namespace-cli}/bin/serena-memory-namespaces
        ${namespaced.packages.${system}.namespace-place}
        [ -f .serena/memories/infra/finding.md ]
        ${namespaced.packages.${system}.namespace-cli}/bin/serena-memory-namespaces
        touch "$out"
      '';
  };
}
