# Workspace layout: one declared tree of independently versioned repos
# plus a single worktree root, instead of submodule chains.
#
#   * devenv — the workspace repo's shell declares `agentic.workspace.repos`
#     (path relative to the workspace root, clone URL, tags) and gets a
#     generated mani.yaml; `mani sync` clones anything missing and
#     `mani run` fans tasks out across repos.
#   * homeManager — `agentic.workspace.root` points every worktree
#     creator at <root>/.worktrees: herdr creates <repo>/<branch-slug>
#     checkouts there, and git records worktree links as relative paths
#     so checkouts survive relocating the tree.
#
# Both halves are inert until a consumer sets them (no repos -> no
# mani.yaml; null root -> no tool config), so carrying them in the
# default exports costs nothing.
let
  devenvModule = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.agentic.workspace;
  in {
    options.agentic.workspace = {
      repos = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            path = lib.mkOption {
              type = lib.types.str;
              description = "Checkout location relative to the workspace root.";
            };
            url = lib.mkOption {
              type = lib.types.str;
              description = "Clone URL.";
            };
            tags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "mani tags, for `mani run -t <tag>` selection.";
            };
          };
        });
        default = {};
        description = "Repos in this workspace, keyed by mani project name.";
      };
      tasks = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {
          status = {
            desc = "short branch status";
            cmd = "git status -sb";
          };
          fetch = {
            desc = "fetch all remotes";
            cmd = "git fetch --all --prune";
          };
        };
        description = "mani tasks run across repos.";
      };
      extraConfig = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
        description = "Freeform mani.yaml settings merged over the generated ones.";
      };
    };

    config = lib.mkIf (cfg.repos != {}) {
      packages = [pkgs.git pkgs.mani];
      files."mani.yaml".yaml =
        {
          # Workspace repos typically allowlist what they track; mani
          # appending every project path to .gitignore fights that.
          sync_gitignore = false;
          projects = lib.mapAttrs (_: repo: {inherit (repo) path url tags;}) cfg.repos;
          inherit (cfg) tasks;
        }
        // cfg.extraConfig;
    };
  };

  homeModule = {
    config,
    lib,
    options,
    ...
  }: let
    cfg = config.agentic.workspace;
  in {
    options.agentic.workspace = {
      root = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = lib.literalExpression ''"''${config.home.homeDirectory}/src"'';
        description = "Absolute path of the workspace root; null leaves worktree tooling untouched.";
      };
      worktreeDir = lib.mkOption {
        type = lib.types.str;
        default = "${cfg.root}/.worktrees";
        defaultText = lib.literalExpression ''"''${config.agentic.workspace.root}/.worktrees"'';
        description = "Shared worktree root; tools create <repo>/<branch> checkouts beneath it.";
      };
    };

    config = lib.mkIf (cfg.root != null) (lib.mkMerge [
      {programs.git.settings.worktree.useRelativePaths = lib.mkDefault true;}
      # herdr's HM module is consumer-provided; configure it only where present.
      (lib.optionalAttrs (options ? programs.herdr) {
        programs.herdr.extraConfig.worktrees.directory = lib.mkDefault cfg.worktreeDir;
      })
    ]);
  };
  # Keyed so importing both `agentic` and the standalone `workspace`
  # export declares the options once.
  devenv = {
    key = "agentic/workspace/devenv";
    imports = [devenvModule];
  };
  homeManager = {
    key = "agentic/workspace/homeManager";
    imports = [homeModule];
  };
in {
  flake.modules = {
    # Core's own namespace (aliased by exports.nix)…
    devenv.workspace = devenv;
    homeManager = {
      workspace = homeManager;
      agentic.imports = [homeManager];
    };

    # …and the consumer's namespace via the exported flakeModule.
    flake.agentic.flake.modules = {
      devenv.workspace = devenv;
      homeManager = {
        workspace = homeManager;
        agentic.imports = [homeManager];
      };
    };
  };
}
