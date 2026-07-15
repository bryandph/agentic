{
  description = "A workflow-complete python/uv project on the agentic core";

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

    # Optional: add your organization's env layer input here and import
    # its module below — it supplies forge endpoints, the secret
    # backend, and org knowledge. Without one, this repo is fully
    # org-neutral (env backend, core fragments only).
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

      # Repo-level agentic config: declare workmux traits, knowledge
      # fragments, agents, and instruction scopes here (see the agentic
      # README).
      agentic.memoryPlane.projectName = "CHANGE-ME";

      perSystem = _: {
        devenv.shells.default = {
          imports = [config.flake.modules.devenv.agentic config.flake.modules.devenv.python];
          # Your project's own shell config (packages, languages,
          # services) composes here — or import a language profile:
          #   imports = [ config.flake.modules.devenv.agentic
          #               config.flake.modules.devenv.rust ];
        };
      };
    });
}
