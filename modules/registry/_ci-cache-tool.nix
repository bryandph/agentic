# Builder for the `agentic-ci-cache` package: the consumer-side
# implementation of the CI cache contract (modules/registry/_ci-cache.nix).
# Not a flake-parts module — imported by the registry module (contract baked
# in for flake-module consumers) and by modules/ci-cache.nix (standalone
# package for consumers that only pin this flake for the tool).
#
# Toolchains that populate a cache (uv + python, sccache + rustc) come from
# the consumer's PATH so the recorded cache generation matches the producer.
# Only transport tooling ships in the closure.
{lib}: {
  mkTool = pkgs:
    pkgs.writeShellApplication {
      name = "agentic-ci-cache";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.gnutar
        pkgs.jq
        pkgs.nix
        pkgs.s5cmd
        pkgs.zstd
      ];
      text = builtins.readFile ./_ci-cache/agentic-ci-cache.sh;
      meta.description = "Trust-tiered, observable, non-blocking CI cache client for the agentic cache contract";
    };

  # The same tool with a contract pre-wired (endpoints and variable names are
  # public metadata; no secret value can enter the contract). A runtime
  # AGENTIC_CI_CACHE_CONTRACT still wins so one image serves several repos.
  mkWrappedTool = pkgs: tool: contractFile:
    pkgs.writeShellApplication {
      name = "agentic-ci-cache";
      runtimeInputs = [tool];
      text = ''
        export AGENTIC_CI_CACHE_CONTRACT="''${AGENTIC_CI_CACHE_CONTRACT:-${contractFile}}"
        exec agentic-ci-cache "$@"
      '';
      meta.description = "agentic-ci-cache with the environment's cache contract pre-wired";
    };

  contractFile = pkgs: contract:
    pkgs.writeText "agentic-ci-cache-contract.json" (builtins.toJSON contract);

  inherit lib;
}
