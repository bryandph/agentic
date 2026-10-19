# Fixture-consumer checks for the secret backend abstraction (task 2.1).
#
# Each fixture is a real flake-parts consumer importing the exported
# `flakeModules.default` — the same path an external repo takes — with a
# different backend selected. The check builds the rendered delivery
# artifacts (stdio wrapper, http exports script) and asserts the
# credential resolution goes through the selected CLI. The
# `onepassword`-shaped fixture proves a new secret manager is a preset
# supplied via options only — it defines its backend entirely in fixture
# config with no core module change.
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
    # A minimal consumer: import the conventional export, select a
    # backend, and render both delivery shapes as packages.
    mkFixture = fixtureModule:
      inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [config.flake.flakeModules.default fixtureModule];
      };

    # Org-neutral marker values — clearly example-shaped per the
    # agentic-layering spec.
    fixtureRefs = {
      FIXTURE_TOKEN = {
        env = "FIXTURE_TOKEN";
        path = "fixture/service";
        field = "token";
      };
      FIXTURE_API_KEY = {
        env = "FIXTURE_API_KEY";
        path = "fixture/api";
        field = "key";
      };
    };

    renderArtifacts = {config, ...}: {
      perSystem = {pkgs, ...}: {
        packages = {
          fixture-wrapped = config.agentic.secrets.lib.wrapServer pkgs {
            name = "fixture-mcp";
            bin = "${pkgs.hello}/bin/hello";
            secrets = fixtureRefs;
            extraEnv.FIXTURE_HOST = "https://forge.fixture.example";
          };
          fixture-exports = pkgs.writeText "fixture-exports.sh" (config.agentic.secrets.lib.exportsScript fixtureRefs);
        };
      };
    };

    vaultFixture = mkFixture {
      imports = [renderArtifacts];
      agentic.secrets = {
        backend = "vault";
        vault = {
          address = "https://vault.fixture.example:8200";
          mount = "fixture-kv";
        };
      };
    };

    envFixture = mkFixture {
      imports = [renderArtifacts];
      agentic.secrets.backend = "env";
    };

    # The modularity proof: a 1password-shaped CLI backend defined by the
    # CONSUMER as data. If this fixture ever needs a core edit to work,
    # the abstraction has failed its spec.
    onepasswordFixture = mkFixture {
      imports = [renderArtifacts];
      agentic.secrets = {
        backend = "onepassword";
        backends.onepassword.secretCommand = ref: ["op" "read" "op://fixture/${ref.path}/${ref.field}"];
      };
    };

    # SecretSpec scoped runners: an optional per-runner provider applies to that
    # runner only; omitting it keeps the configured provider. The stub stands in
    # for the CLI: only the generated runner text is inspected, nothing runs.
    secretspecStub = (pkgs.writeShellScriptBin "secretspec" "exit 1") // {version = "0.21.0";};
    secretspecFixture = mkFixture ({config, ...}: {
      agentic.secrets = {
        backend = "secretspec";
        secretspec = {
          provider = "openbao://vault.fixture.example:8200/fixture-kv";
          package = _: secretspecStub;
        };
        scopes.fixture.FIXTURE_TOKEN = {
          path = "fixture/service";
          field = "token";
        };
      };
      perSystem = {pkgs, ...}: {
        packages = {
          runner-default = config.agentic.secrets.lib.mkRunner pkgs {name = "fixture-runner";};
          runner-explicit = config.agentic.secrets.lib.mkRunner pkgs {
            name = "fixture-runner";
            provider = "openbao://vault.fixture.example:8200/fixture-kv";
          };
          runner-override = config.agentic.secrets.lib.mkRunner pkgs {
            name = "fixture-other-runner";
            provider = "openbao://vault.fixture.example:8200/other-kv";
          };
        };
      };
    });

    artifact = fixture: name: fixture.packages.${system}.${name};
  in {
    checks.secret-backends =
      pkgs.runCommand "agentic-secret-backends" {
        nativeBuildInputs = [pkgs.gnugrep];
      } ''
        set -euo pipefail

        expect() { grep -qF -- "$1" "$2" || { echo "MISSING [$1] in $2"; exit 1; }; }
        forbid() { ! grep -qF -- "$1" "$2" || { echo "FORBIDDEN [$1] in $2"; exit 1; }; }

        # vault backend: stdio wrapper resolves via the parameterized CLI
        # invocation; the address/mount arrive from options, and the
        # value is fetched at runtime (command substitution, no literal).
        wrapper=${artifact vaultFixture "fixture-wrapped"}/bin/fixture-mcp
        expect 'VAULT_ADDR=https://vault.fixture.example:8200' "$wrapper"
        expect "vault kv get '-mount=fixture-kv' '-field=token' fixture/service" "$wrapper"
        expect 'FIXTURE_TOKEN="$(' "$wrapper"
        expect '|| exit 1' "$wrapper"
        expect 'export FIXTURE_HOST=https://forge.fixture.example' "$wrapper"
        expect 'exec' "$wrapper"

        # http delivery: same backend, client-side ''${VAR} expansion —
        # the exports script carries the CLI invocation, never a value.
        exports=${artifact vaultFixture "fixture-exports"}
        expect 'FIXTURE_API_KEY="$(' "$exports"
        expect "vault kv get '-mount=fixture-kv' '-field=key' fixture/api" "$exports"

        # env backend: degenerate passthrough re-exports from the ambient
        # environment; no vault invocation may remain.
        envwrapper=${artifact envFixture "fixture-wrapped"}/bin/fixture-mcp
        expect 'FIXTURE_TOKEN="$(printenv FIXTURE_TOKEN)"' "$envwrapper"
        forbid 'vault' "$envwrapper"
        # Missing runtime credentials must stop before the wrapped command.
        if env -u FIXTURE_TOKEN -u FIXTURE_API_KEY "$envwrapper" > missing-output 2>/dev/null; then
          echo "missing credential incorrectly launched the server" >&2
          exit 1
        fi
        test ! -s missing-output
        FIXTURE_TOKEN=fixture-token FIXTURE_API_KEY=fixture-key "$envwrapper" > present-output
        grep -qF 'Hello, world!' present-output

        # secretspec runner provider: the default is exactly the configured
        # provider (same derivation as passing it explicitly); an override
        # changes only its own runner.
        default=${artifact secretspecFixture "runner-default"}
        explicit=${artifact secretspecFixture "runner-explicit"}
        override=${artifact secretspecFixture "runner-override"}/bin/fixture-other-runner
        test "$default" = "$explicit" || { echo "default provider changed the runner"; exit 1; }
        expect 'openbao://vault.fixture.example:8200/fixture-kv' "$default/bin/fixture-runner"
        forbid 'other-kv' "$default/bin/fixture-runner"
        expect 'openbao://vault.fixture.example:8200/other-kv' "$override"
        forbid 'fixture-kv' "$override"
        expect '--scope "$scope"' "$override"

        # consumer-defined preset: resolution goes through the op CLI with
        # zero core changes.
        opwrapper=${artifact onepasswordFixture "fixture-wrapped"}/bin/fixture-mcp
        expect 'op read op://fixture/fixture/service/token' "$opwrapper"
        forbid 'vault' "$opwrapper"

        touch $out
      '';
  };
}
