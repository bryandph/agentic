# Standalone delivery of the CI cache client (ci-cache-fabric spec, tool-aware
# cache profiles): `packages.<system>.ci-cache` / `apps.<system>.ci-cache`.
# A consumer that does not import the agentic flake module (hand-written
# workflows, a runner image) pins this flake for the package alone and hands
# the tool its environment's contract JSON at runtime through
# AGENTIC_CI_CACHE_CONTRACT. Flake-module consumers get the same binary with
# the contract pre-wired via `config.agentic.ciCache.lib.tools pkgs`.
{lib, ...}: let
  tool = import ./registry/_ci-cache-tool.nix {inherit lib;};
in {
  perSystem = {pkgs, ...}: let
    package = tool.mkTool pkgs;
  in {
    packages.ci-cache = package;
    apps.ci-cache = {
      type = "app";
      program = "${package}/bin/agentic-ci-cache";
      meta.description = "Trust-tiered, observable, non-blocking CI cache client (nix publish, sccache env/run/stats, uv restore/publish)";
    };
  };
}
