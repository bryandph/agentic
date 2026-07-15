# Org-neutrality check (task 2.6, agentic-layering spec): core carries
# no environment identity. Two layers of assertion:
#
#   * source scan — modules/ must not name BPH-specific identifiers
#     (forge hosts, the .bph domain, fleet host names). Documentation
#     (README, docs/) may show clearly-marked examples; code may not.
#     The fixture vocabulary is *.fixture.example / fixture-* by
#     convention.
#   * artifacts — the secret-backends and adapter fixtures already
#     assert rendered outputs contain only fixture values and CLI
#     invocations (no plaintext); this check re-greps their rendered
#     project config for org identifiers as a belt-and-braces sweep.
#
# The org-identifier list is a deny-list of known BPH markers, not an
# allow-list — extend it when a new environment-specific vocabulary
# appears.
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
          agentic.secrets.backend = "env";
          perSystem = {config, ...}: {
            packages.fixture-claude-config = config.mcp-servers.configs.claude-code;
          };
        })
      ];
    };
  in {
    checks.org-neutral =
      pkgs.runCommand "agentic-org-neutral" {
        nativeBuildInputs = [pkgs.gnugrep];
        src = ../../modules;
        fragments = ../../fragments;
      } ''
        set -euo pipefail

        # Source scan: no BPH identity in code or shipped fragments.
        # This file is excluded — it necessarily spells the deny-list.
        if grep -rniE '\.bph\b|git\.bph|blackdc|mandala-bph|bryandph' --exclude=org-neutral.nix "$src" "$fragments"; then
          echo "org-specific identifier found in core sources (see matches above)"
          exit 1
        fi

        # Rendered artifact sweep under the env backend.
        if grep -niE '\.bph\b|blackdc' ${fixture.packages.${system}.fixture-claude-config}; then
          echo "org-specific identifier leaked into a rendered artifact"
          exit 1
        fi

        touch $out
      '';
  };
}
