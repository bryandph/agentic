{
  # WORKFLOW-ONLY ADOPTION: this flake touches ONLY the dev shell — it
  # delivers the agentic workflow artifacts (MCP config, agent dirs,
  # knowledge memories, generated .workmux.yaml) and optionally extra
  # tools. Your existing build (cargo, make, whatever) is untouched and
  # keeps working for collaborators who never enter the shell.
  description = "Agentic workflow shell (adoption mode — build untouched)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pin a tag or rev — never an implicitly-tracked branch.
    agentic = {
      url = "github:bryandph/agentic";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} ({config, ...}: {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      imports = [
        inputs.devenv.flakeModule
        inputs.agentic.flakeModules.default
      ];

      agentic.memoryPlane.projectName = "CHANGE-ME";

      perSystem = _: {
        devenv.shells.default = {
          imports = [
            config.flake.modules.devenv.agentic
            # Optional: a language profile puts the toolchain on the
            # shell PATH without owning your build, e.g. for an
            # embedded cargo workspace:
            #   config.flake.modules.devenv.embedded-rust
          ];
        };
      };
    });
}
