# Cache-profile contract checks. The fixture environment uses only
# *.fixture.example values; neutral fixtures deliberately request profiles
# without defining any, matching a template instantiated without an env layer.
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
    environmentProfiles = {
      nix = {
        readEndpoints = ["https://nix-cache.fixture.example"];
        protectedWriteEndpoint = "https://nix-upload.fixture.example";
        pullRequestWriteEndpoint = "s3://nix-quarantine-fixture";
        trustedPublicKeys = ["fixture-cache.example-1:PUBLIC-KEY-FIXTURE"];
        runtimeSecretEnv = ["NIX_CACHE_TOKEN"];
      };

      rust = {
        endpoint = "https://objects.fixture.example";
        bucket = "fixture-compiler-cache";
        region = "fixture-1";
        keyPrefix = "ci/fixture";
        runtimeSecretEnv = [
          "AWS_ACCESS_KEY_ID"
          "AWS_SECRET_ACCESS_KEY"
        ];
      };

      python = {
        endpoint = "https://objects.fixture.example";
        bucket = "fixture-python-cache";
        region = "fixture-1";
        keyPrefix = "ci/fixture";
        runtimeSecretEnv = [
          "AWS_ACCESS_KEY_ID"
          "AWS_SECRET_ACCESS_KEY"
        ];
      };
    };

    mkFixture = {
      requestedProfiles,
      profiles ? {},
    }:
      inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [
          config.flake.flakeModules.default
          ({config, ...}: {
            agentic = {
              secrets.backend = "env";
              ciCache = {inherit requestedProfiles profiles;};
            };

            flake.agenticCacheProbe = config.agentic.ciCache.lib.contract;

            # Cache selection is metadata for the repo-owned workflow. It
            # must not replace or wrap the repo's out-of-shell build.
            perSystem = {pkgs, ...}: {
              packages.consumer-build = pkgs.hello;
            };
          })
        ];
      };

    neutralRust = mkFixture {
      requestedProfiles = ["nix" "rust"];
    };
    neutralPython = mkFixture {
      requestedProfiles = ["nix" "python"];
    };
    environmentRust = mkFixture {
      requestedProfiles = ["nix" "rust"];
      profiles = environmentProfiles;
    };
    environmentPython = mkFixture {
      requestedProfiles = ["nix" "python"];
      profiles = environmentProfiles;
    };
    environmentPolyglot = mkFixture {
      requestedProfiles = ["nix" "rust" "python"];
      profiles = environmentProfiles;
    };

    contractFile = name: fixture:
      pkgs.writeText "agentic-ci-cache-${name}.json" (builtins.toJSON fixture.agenticCacheProbe);
  in {
    checks.ci-cache-contracts = assert neutralRust.agenticCacheProbe.profiles == {};
    assert neutralPython.agenticCacheProbe.profiles == {};
    assert builtins.attrNames environmentRust.agenticCacheProbe.profiles == ["nix" "rust"];
    assert builtins.attrNames environmentPython.agenticCacheProbe.profiles == ["nix" "python"];
    assert builtins.attrNames environmentPolyglot.agenticCacheProbe.profiles == ["nix" "python" "rust"];
    assert environmentRust.agenticCacheProbe.ownership == "consumer";
    assert environmentRust.agenticCacheProbe.failurePolicy == "report-and-continue";
    assert !environmentRust.agenticCacheProbe.trustPolicy.protectedReadsPullRequest;
    assert !environmentRust.agenticCacheProbe.trustPolicy.directPromotion;
    assert neutralRust.packages.${system}.consumer-build.drvPath == environmentRust.packages.${system}.consumer-build.drvPath;
    assert neutralPython.packages.${system}.consumer-build.drvPath == environmentPython.packages.${system}.consumer-build.drvPath;
      pkgs.runCommand "agentic-ci-cache-contracts" {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.jq
        ];
        templates = ../../templates;
        neutralRustContract = contractFile "neutral-rust" neutralRust;
        neutralPythonContract = contractFile "neutral-python" neutralPython;
        environmentRustContract = contractFile "environment-rust" environmentRust;
        environmentPythonContract = contractFile "environment-python" environmentPython;
        environmentPolyglotContract = contractFile "environment-polyglot" environmentPolyglot;
      } ''
        set -euo pipefail

        # The shipped variants request ecosystem metadata but carry no
        # environment endpoint, credential assignment, or CI pipeline.
        grep -qF 'agentic.ciCache.requestedProfiles = ["nix" "rust"];' "$templates/rust/flake.nix"
        grep -qF 'agentic.ciCache.requestedProfiles = ["nix" "python"];' "$templates/python/flake.nix"
        grep -qF 'agentic.ciCache.requestedProfiles = ["nix" "rust" "python"];' "$templates/polyglot/flake.nix"
        if grep -rniE 'ciCache\.profiles|readEndpoints|WriteEndpoint|runtimeSecretEnv' "$templates"; then
          echo "an environment-owned cache profile leaked into a project template"
          exit 1
        fi
        if grep -rniE 'AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)[[:space:]]*=' "$templates"; then
          echo "cache credential assignment leaked into a project template"
          exit 1
        fi
        if find "$templates" -type f \( -name '.woodpecker*' -o -path '*/.woodpecker/*' \) | grep -q .; then
          echo "a project template unexpectedly owns mandatory CI configuration"
          exit 1
        fi

        jq -e '.profiles == {}' "$neutralRustContract" >/dev/null
        jq -e '.profiles == {}' "$neutralPythonContract" >/dev/null
        jq -e '.profiles | keys == ["nix", "rust"]' "$environmentRustContract" >/dev/null
        jq -e '.profiles | keys == ["nix", "python"]' "$environmentPythonContract" >/dev/null
        jq -e '.profiles | keys == ["nix", "python", "rust"]' "$environmentPolyglotContract" >/dev/null

        jq -e '.profiles.nix.publicationMode == "completed-closures"' "$environmentRustContract" >/dev/null
        jq -e '.profiles.nix.protectedWriteEndpoint == "https://nix-upload.fixture.example"' "$environmentRustContract" >/dev/null
        jq -e '.profiles.nix.pullRequestWriteEndpoint == "s3://nix-quarantine-fixture"' "$environmentRustContract" >/dev/null
        jq -e '.trustPolicy.directPromotion == false' "$environmentRustContract" >/dev/null
        jq -e '.profiles.rust.kind == "sccache"' "$environmentRustContract" >/dev/null
        jq -e '.profiles.rust.keyInputs == ["repository", "architecture", "compiler-generation", "cache-generation", "trust-tier"]' "$environmentRustContract" >/dev/null
        jq -e '.profiles.python.kind == "uv"' "$environmentPythonContract" >/dev/null
        jq -e '.profiles.python.transport == "s3"' "$environmentPythonContract" >/dev/null
        jq -e '.profiles.python.cacheDir == ".ci-cache/uv"' "$environmentPythonContract" >/dev/null
        jq -e '.profiles.python.pruneCommand == "uv cache prune --ci"' "$environmentPythonContract" >/dev/null

        touch $out
      '';
  };
}
