# Read-only ignore diagnostics in real repositories, including linked worktrees.
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
          flake.lib.memoryPlane = config.agentic.memoryPlane.lib;
        })
      ];
    };
    plane = fixture.lib.memoryPlane;
    cli = "${plane.ignoreCheckPackage pkgs}/bin/workbench-serena-ignore";
    warning = pkgs.writeShellScript "serena-ignore-warning" (plane.ignoreWarningScript pkgs);
  in {
    checks.serena-ignore =
      pkgs.runCommand "workbench-serena-ignore-fixtures" {
        nativeBuildInputs = [pkgs.git pkgs.gnugrep pkgs.coreutils];
      } ''
        set -euo pipefail
        export HOME="$TMPDIR/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
        mkdir -p "$HOME" repo
        ${warning} >warning.out 2>warning.err
        test ! -s warning.out
        test ! -s warning.err
        PATH=/nonexistent ${warning} >warning.out 2>warning.err
        test ! -s warning.out
        test ! -s warning.err
        cd repo
        git init -b main
        git config user.name Fixture
        git config user.email fixture@example.invalid
        touch tracked
        git add tracked
        git commit -m fixture
        git worktree add -b worker '../linked tree'
        cd '../linked tree'
        root=$PWD

        # Future runtime paths must be ignored before Serena has even run.
        if ${cli} > report; then exit 1; fi
        ${warning} >warning.out 2>warning.err
        test ! -s warning.out
        test "$(wc -l <warning.err)" -eq 1
        grep -qF '/.serena/' warning.err
        grep -qF 'workbench-serena-ignore' warning.err
        grep -qxF '/.serena/' report
        grep -qF "$root/.gitignore" report
        mkdir -p .serena/cache
        touch .serena/.gitignore .serena/project.yml .serena/cache/runtime
        if ${cli} > report; then exit 1; fi
        cat report
        printf '%s\n' ${inputs.nixpkgs.lib.escapeShellArgs plane.runtimeIgnoreLines.whole} > .gitignore
        ${cli}
        ${warning} >warning.out 2>warning.err
        test ! -s warning.out
        test ! -s warning.err
        test -f .serena/cache/runtime
        cd ..
        ${cli} --worktree "$root"
        cd "$root"

        # Tracked memories are not runtime, and must remain visible to Git.
        rm .gitignore .serena/.gitignore
        mkdir -p .serena/memories/infra
        echo finding > .serena/memories/infra/finding.md
        git add .serena/memories/infra/finding.md
        if ${cli} > report; then exit 1; fi
        grep -qxF '.serena/cache/' report
        grep -qxF '.serena/project.yml' report
        if grep -qxF '/.serena/' report; then exit 1; fi
        printf '%s\n' ${inputs.nixpkgs.lib.escapeShellArgs (plane.runtimeIgnoreLines.shared ++ [plane.runtimeIgnoreLines.generatedProject])} > .gitignore
        ${cli}
        if git check-ignore -q .serena/memories/infra/new.md; then exit 1; fi
        # A tracked project.yml is never demanded as an ignore entry.
        git add -f .serena/project.yml
        printf '%s\n' ${inputs.nixpkgs.lib.escapeShellArgs plane.runtimeIgnoreLines.shared} > .gitignore
        ${cli}
        # Existing unexpected untracked content still fails, even with the policy.
        touch .serena/memories/infra/new.md
        if ${cli} > report; then exit 1; fi
        test -f .serena/memories/infra/new.md
        rm .serena/memories/infra/new.md
        # Exceptions that expose cache files also fail the untracked check.
        printf '!/.serena/cache/\n' >> .gitignore
        if ${cli} > report; then exit 1; fi
        touch "$out"
      '';
  };
}
