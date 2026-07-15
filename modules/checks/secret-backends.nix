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
        expect 'export FIXTURE_TOKEN="$(' "$wrapper"
        expect 'export FIXTURE_HOST=https://forge.fixture.example' "$wrapper"
        expect 'exec' "$wrapper"

        # http delivery: same backend, client-side ''${VAR} expansion —
        # the exports script carries the CLI invocation, never a value.
        exports=${artifact vaultFixture "fixture-exports"}
        expect 'export FIXTURE_API_KEY="$(' "$exports"
        expect "vault kv get '-mount=fixture-kv' '-field=key' fixture/api" "$exports"

        # env backend: degenerate passthrough re-exports from the ambient
        # environment; no vault invocation may remain.
        envwrapper=${artifact envFixture "fixture-wrapped"}/bin/fixture-mcp
        expect 'export FIXTURE_TOKEN="$(printenv FIXTURE_TOKEN)"' "$envwrapper"
        forbid 'vault' "$envwrapper"

        # consumer-defined preset: resolution goes through the op CLI with
        # zero core changes.
        opwrapper=${artifact onepasswordFixture "fixture-wrapped"}/bin/fixture-mcp
        expect 'op read op://fixture/fixture/service/token' "$opwrapper"
        forbid 'vault' "$opwrapper"

        touch $out
      '';
  };
}
