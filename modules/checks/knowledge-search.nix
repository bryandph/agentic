# Fixture check for the knowledge search server (task 2.5b): the
# registry entry is project-tier with a CLI equivalent (Pi coverage),
# and the wrapper registers the declared per-repo + org collections
# before serving.
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
    mkFixture = index: refreshTimeout:
      inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [
          config.flake.flakeModules.default
          ({config, ...}: {
            agentic.knowledgeSearch.index = index;
            agentic.knowledgeSearch.refreshTimeout = refreshTimeout;
            agentic.knowledgeSearch.collections = {
              fixture-repo.path = ".serena/memories";
              fixture-org.path = "org";
            };

            flake.agenticProbe = {
              knowledgeTiers = config.agentic.mcp.servers.knowledge.tiers;
              knowledgeArgs = config.agentic.mcp.servers.knowledge.args;
              cliEquivalents = builtins.attrNames config.agentic.mcp.lib.cliEquivalents;
            };

            perSystem = {pkgs, ...}: {
              packages = {
                fixture-qmd-wrapper = config.agentic.knowledgeSearch.lib.wrapper pkgs;
                fixture-refresh = pkgs.writeShellScript "fixture-refresh" (config.agentic.knowledgeSearch.lib.refreshScript pkgs);
                # Exercise the real refresh with an unavailable wrapper, not qmd.
                fixture-broken-refresh = pkgs.writeShellScript "fixture-broken-refresh" (config.agentic.knowledgeSearch.lib.refreshScript (pkgs
                  // {
                    writeScriptBin = _: _: "/unavailable-qmd";
                  }));
                fixture-counted-refresh = pkgs.writeShellScript "fixture-counted-refresh" (config.agentic.knowledgeSearch.lib.refreshScript (pkgs
                  // {
                    writeScriptBin = _: _:
                      pkgs.writeShellScriptBin "qmd-knowledge" ''
                        printf 'invoked\n' >> "$PWD/qmd-invocations"
                        exec ${config.agentic.knowledgeSearch.lib.wrapper pkgs}/bin/qmd-knowledge "$@"
                      '';
                  }));
                fixture-hung-refresh = pkgs.writeShellScript "fixture-hung-refresh" (config.agentic.knowledgeSearch.lib.refreshScript (pkgs
                  // {
                    writeScriptBin = _: _: pkgs.writeShellScriptBin "qmd-knowledge" "exec ${pkgs.coreutils}/bin/sleep 30";
                  }));
                fixture-bootstrap = pkgs.writeText "fixture-bootstrap" (config.agentic.devenvLib.bootstrapScript pkgs);
              };
            };
          })
        ];
      };

    # Allow real qmd startup under load; test the bound separately.
    fixture = mkFixture "user" 120;
    localFixture = mkFixture "local" 120;
    hungFixture = mkFixture "user" 3;
    p = fixture.agenticProbe;

    # A consumer without collections opts out: no server, no CLI equivalent.
    optOut = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [system];
      imports = [
        config.flake.flakeModules.default
        ({config, ...}: {
          flake.agenticProbe = {
            hasKnowledge = config.agentic.mcp.servers ? knowledge;
            hasRefresh = inputs.nixpkgs.lib.hasInfix "qmd-knowledge-refresh" (config.agentic.devenvLib.bootstrapScript pkgs);
            cliEquivalents = builtins.attrNames config.agentic.mcp.lib.cliEquivalents;
          };
        })
      ];
    };
    q = optOut.agenticProbe;
  in {
    checks.knowledge-search = assert p.knowledgeTiers == ["project"];
    assert p.knowledgeArgs == ["mcp"];
    assert p.cliEquivalents == ["knowledge"];
    assert !q.hasKnowledge;
    assert !q.hasRefresh;
    assert !(builtins.elem "knowledge" q.cliEquivalents);
      pkgs.runCommand "agentic-knowledge-search" {
        nativeBuildInputs = [pkgs.gnugrep pkgs.yq-go];
      } ''
        set -euo pipefail
        w=${fixture.packages.${system}.fixture-qmd-wrapper}/bin/qmd-knowledge

        grep -qF "collection add .serena/memories --name fixture-repo" "$w"
        grep -qF "collection add org --name fixture-org" "$w"
        grep -qE 'exec /nix/store/.*/bin/qmd "\$@"' "$w"

        grep -qF 'qmd-knowledge-refresh' ${fixture.packages.${system}.fixture-bootstrap}

        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/.config"
        export XDG_CACHE_HOME="$HOME/.cache"
        unset INDEX_PATH QMD_CONFIG_DIR
        mkdir -p "$HOME"
        ${inputs.nixpkgs.lib.concatMapStringsSep "\n" (f: ''
            mkdir -p ${f.index}/.serena/memories ${f.index}/org
            cd ${f.index}
            printf '# Asterism\n\nAsterism baseline knowledge.\n' > .serena/memories/first.md
            ${f.packages.fixture-refresh} >refresh.out 2>refresh.err
            test ! -s refresh.out
            test ! -s refresh.err
            ${f.packages.fixture-qmd-wrapper}/bin/qmd-knowledge search asterism --json > results.json
            grep -q 'first.md' results.json
            printf '# Quasar\n\nQuasar newly added knowledge.\n' > .serena/memories/second.md
            printf '# Nebula\n\nNebula changed knowledge.\n' > .serena/memories/first.md
            ${f.packages.fixture-refresh} >refresh.out 2>refresh.err
            test ! -s refresh.err
            ${f.packages.fixture-qmd-wrapper}/bin/qmd-knowledge search quasar --json > results.json
            grep -q 'second.md' results.json
            ${f.packages.fixture-qmd-wrapper}/bin/qmd-knowledge search nebula --json > results.json
            grep -q 'first.md' results.json
            ${f.packages.fixture-refresh} >refresh.out 2>refresh.err
            test ! -s refresh.err

            stamp=${
              if f.index == "local"
              then ".qmd/.agentic-refresh.sha256"
              else ''"$XDG_CACHE_HOME/qmd/.agentic-refresh.sha256"''
            }
            before_failure=$(<"$stamp")
            ${f.packages.fixture-broken-refresh} >refresh.out 2>refresh.err
            test "$(<"$stamp")" = "$before_failure"
            test ! -s refresh.out
            test "$(wc -l < refresh.err)" -eq 1
            grep -q 'qmd index refresh skipped or failed' refresh.err

            # The second unchanged refresh must not start qmd at all.
            ${f.packages.fixture-counted-refresh} >refresh.out 2>refresh.err
            test ! -s refresh.err
            test "$(wc -l < qmd-invocations)" -eq 1
            ${f.packages.fixture-counted-refresh} >refresh.out 2>refresh.err
            test ! -s refresh.err
            test "$(wc -l < qmd-invocations)" -eq 1

            # Content changes still invalidate when the timestamp is preserved.
            cp -p .serena/memories/second.md old-timestamp
            printf '# Pulsar\n\nPulsar preserved timestamp.\n' > .serena/memories/second.md
            touch -r old-timestamp .serena/memories/second.md
            ${f.packages.fixture-counted-refresh} >refresh.out 2>refresh.err
            test ! -s refresh.err
            test "$(wc -l < qmd-invocations)" -eq 2
            ${f.packages.fixture-qmd-wrapper}/bin/qmd-knowledge search pulsar --json > results.json
            grep -q 'second.md' results.json
            printf '# Magnetar\n\nMagnetar additional file.\n' > .serena/memories/third.md
            ${f.packages.fixture-counted-refresh} >refresh.out 2>refresh.err
            test ! -s refresh.err
            test "$(wc -l < qmd-invocations)" -eq 3
            rm .serena/memories/third.md
            ${f.packages.fixture-counted-refresh} >refresh.out 2>refresh.err
            test ! -s refresh.err
            test "$(wc -l < qmd-invocations)" -eq 4

            # A configured hook must not execute, even in an existing user index.
            config=${
              if f.index == "local"
              then ".qmd/index.yml"
              else ''"$XDG_CONFIG_HOME/qmd/index.yml"''
            }
            yq -i '.collections.fixture-repo.update = "touch hook-ran"' "$config"
            before_failure=$(<"$stamp")
            ${f.packages.fixture-counted-refresh} >refresh.out 2>refresh.err
            test ! -e hook-ran
            test "$(wc -l < qmd-invocations)" -eq 4
            test "$(<"$stamp")" = "$before_failure"
            test "$(wc -l < refresh.err)" -eq 1
            grep -q 'qmd index refresh skipped or failed' refresh.err
            yq -i 'del(.collections.fixture-repo.update)' "$config"
            cd ..
          '') (map (index: {
            inherit index;
            packages =
              (
                if index == "local"
                then localFixture
                else fixture
              ).packages.${
                system
              };
          }) ["user" "local"])}
        # A stuck process is bounded and still succeeds with one warning.
        started=$SECONDS
        ${hungFixture.packages.${system}.fixture-hung-refresh} >refresh.out 2>refresh.err
        test "$((SECONDS - started))" -lt 10
        test ! -s refresh.out
        test "$(wc -l < refresh.err)" -eq 1
        grep -q 'qmd index refresh skipped or failed' refresh.err

        # No command on this path may download models.
        test -z "$(find "$HOME" -name '*.gguf' -print -quit)"
        touch $out
      '';
  };
}
