# Runtime scenarios for the CI cache client (ci-cache-fabric spec): cold,
# warm, invalidation, trust separation, credential split, backend failure,
# bounded publication/restore, hostile archives, and the sccache fallback
# contract against a real crate with a .cargo/config.toml wrapper. Every
# backend is file-backed or deliberately unreachable; every credential is a
# fixture literal. The script lives in _fixtures/ci-cache-tools.sh.
{
  inputs,
  config,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    self',
    ...
  }: let
    # Synthetic content policy, never used by a consumer or remote endpoint.
    policy = pkgs.writeShellScript "fixture-ci-cache-policy" ''
      test "$1" = --closure-file && test -s "$2"
    '';
    environmentProfiles = import ./_fixtures/ci-cache-environment.nix;
    fixture = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [system];
      imports = [
        config.flake.flakeModules.default
        ({config, ...}: {
          agentic = {
            secrets.backend = "env";
            ciCache = {
              requestedProfiles = ["nix" "rust" "python"];
              profiles =
                environmentProfiles
                // {
                  nix =
                    environmentProfiles.nix
                    // {
                      publicationPolicy = {
                        executableBySystem.${system} = "${policy}";
                        identity = "fixture-policy";
                        revision = "fixture-revision";
                      };
                    };
                };
            };
          };
          perSystem = {pkgs, ...}: {
            packages = {
              ci-cache-wrapped = config.agentic.ciCache.lib.tools pkgs;
              ci-cache-contract = config.agentic.ciCache.lib.contractFile pkgs;
            };
          };
        })
      ];
    };
  in {
    checks.ci-cache-tools =
      pkgs.runCommandCC "agentic-ci-cache-tools" {
        nativeBuildInputs = [
          pkgs.cargo
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gnutar
          pkgs.jq
          pkgs.nix
          pkgs.python3
          pkgs.rustc
          pkgs.uv
          pkgs.zstd
        ];
        tool = self'.packages.ci-cache;
        wrapped = fixture.packages.${system}.ci-cache-wrapped;
        contract = fixture.packages.${system}.ci-cache-contract;
        inherit policy;
        denyPolicy = pkgs.writeShellScript "fixture-ci-cache-deny" "exit 1";
        errorPolicy = pkgs.writeShellScript "fixture-ci-cache-error" "exit 2";
        # Off PATH on purpose: the suite proves the config-file wrapper is
        # in force and that the fallback disables it.
        sccacheBin = "${pkgs.sccache}/bin";
        # The sccache server listens on loopback.
        __darwinAllowLocalNetworking = true;
      } ''
        bash ${./_fixtures/ci-cache-tools.sh}
        touch "$out"
      '';
  };
}
