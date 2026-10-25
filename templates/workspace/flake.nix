{
  description = "A workspace: one declared tree of independently versioned repositories";

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

    # Replace with the public flake URL of the workbench core you
    # consume, and pin a tag or rev, never an implicitly-tracked branch.
    workbench = {
      url = "github:OWNER/agentic";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      imports = [inputs.devenv.flakeModule];

      perSystem = _: {
        devenv.shells.default = {
          imports = [inputs.workbench.devenvModules.workspace];

          # The declaration: where repositories come from and which ones
          # this workspace checks out. Empty, it renders nothing. See the
          # core README, "Workspace", for remotes, repos, groups and
          # defaultPath. For example:
          #   remotes.team.url = "git@forge.example:team";
          #   repos.tool = { remote = "team"; groups = [ "apps" ]; };
          # The shell then writes mani.yaml; `mani sync` clones what is
          # missing and `workspace-audit` compares the tree with this.
          workbench.workspace = {
            remotes = {};
            repos = {};
          };
        };
      };
    };
}
