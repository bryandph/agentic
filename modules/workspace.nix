# Workspace layout: one declared tree of independently versioned repos
# plus a single worktree root, instead of submodule chains.
#
#   * devenv — the workspace repo's shell declares `workbench.workspace`
#     (alias `agentic.workspace`): named `remotes` on any forge, `repos`
#     given as remote + name or a full URL, and a `defaultPath` function
#     for repos without an explicit path. The declaration is resolved
#     once into `resolved` (a JSON-serialisable list of
#     `{ key, url, aliases, path, groups }`, also exported to scripts as
#     $WORKBENCH_WORKSPACE_MANIFEST); renderers and helpers read only
#     that. mani is the first renderer: the shell gets a generated
#     mani.yaml, `mani sync` clones anything missing and `mani run` fans
#     tasks out across repos. Rendering writes the manifest only.
#   * homeManager — `workbench.workspace.root` points every worktree
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
    inherit (lib) types;

    remoteModule = {
      options = {
        url = lib.mkOption {
          type = types.str;
          example = "git@forge.example:team";
          description = "Base URL that repository names are joined to, in any git URL form (scp-style SSH, `ssh://`, HTTPS).";
        };
        aliases = lib.mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Base URLs of mirrors serving the same repositories; joined with each name like `url`.";
        };
        suffix = lib.mkOption {
          type = types.str;
          default = ".git";
          description = "Appended to `<url>/<name>` to form a clone URL.";
        };
      };
    };

    repoModule = {
      name,
      config,
      ...
    }: {
      options = {
        remote = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Remote in `remotes` this repository is cloned from; set this or `url`.";
        };
        name = lib.mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalMD "the attribute name";
          description = "Repository name joined to the remote's base URL.";
        };
        url = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Full clone URL; set this or `remote`.";
        };
        aliases = lib.mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Further URLs that identify this repository, such as a mirror not declared as a remote.";
        };
        path = lib.mkOption {
          type = types.str;
          default = cfg.defaultPath {
            key = name;
            inherit (config) name remote;
            groups = effectiveGroups config;
          };
          defaultText = lib.literalMD "`defaultPath` applied to `{ key, name, remote, groups }`";
          description = "Checkout location relative to the workspace root.";
        };
        groups = lib.mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Selection groups, rendered as mani tags and used to pick repositories for tasks and overrides.";
        };
        tags = lib.mkOption {
          type = types.listOf types.str;
          default = [];
          visible = false;
          description = "Deprecated synonym of `groups`.";
        };
      };
    };

    # `tags` is the milestone spelling; both lists count, groups first.
    effectiveGroups = repo: lib.unique (repo.groups ++ repo.tags);

    joinRemote = remote: name: "${lib.removeSuffix "/" remote}/${name}";

    # Declaration errors, as messages naming the entries involved. Kept
    # apart from `assertions` so the renderers can refuse to render too.
    entryErrors = lib.concatLists (lib.mapAttrsToList (key: repo:
      lib.optional (repo.remote != null && repo.url != null)
      "workspace.repos.${key}: set exactly one of `remote` or `url`, not both."
      ++ lib.optional (repo.remote == null && repo.url == null)
      "workspace.repos.${key}: set exactly one of `remote` or `url`."
      ++ lib.optional (repo.remote != null && !(cfg.remotes ? ${repo.remote}))
      "workspace.repos.${key}: remote `${repo.remote}` is not declared in workspace.remotes."
      ++ lib.optional (!normalisedPath repo.path)
      "workspace.repos.${key}: path `${repo.path}` must be a normalised path below the workspace root (relative, no empty, `.` or `..` segments, no trailing slash).")
    cfg.repos);

    normalisedPath = path: let
      segments = lib.splitString "/" path;
    in
      path != "" && lib.all (s: s != "" && s != "." && s != "..") segments;

    byPath = lib.groupBy (e: e.path) (lib.mapAttrsToList (key: repo: {
        inherit key;
        inherit (repo) path;
      })
      cfg.repos);
    collisionErrors = lib.concatLists (lib.mapAttrsToList (path: entries:
      lib.optional (lib.length entries > 1)
      "workspace.repos: ${lib.concatMapStringsSep ", " (e: e.key) entries} all resolve to path `${path}`.")
    byPath);
    # A checkout beneath another one would show up as untracked content
    # of the outer repository after `mani sync`.
    paths = lib.attrNames byPath;
    nestingErrors = lib.concatMap (outer:
      lib.concatMap (inner:
        lib.optional (lib.hasPrefix "${outer}/" inner)
        "workspace.repos: ${(lib.head byPath.${inner}).key} (`${inner}`) lies inside ${(lib.head byPath.${outer}).key} (`${outer}`); nested checkouts are refused.")
      paths)
    paths;

    # Settings that let mani rewrite .gitignore, remotes or worktrees of
    # existing checkouts. Rendering must never enable them.
    guardedKeys = ["sync_gitignore" "sync_remotes" "remove_orphaned_worktrees"];
    maniErrors =
      map (k: "workspace.extraConfig.${k}: enabling it would let mani change existing checkouts; it must stay false.")
      (lib.filter (k: (cfg.extraConfig.${k} or false) != false) guardedKeys)
      ++ lib.concatLists (lib.mapAttrsToList (project: attrs:
        map (k: "workspace.extraConfig.projects.${project}.${k}: per-project ${k} are refused; worktrees belong to the worktree tool and remotes to git.")
        (lib.filter (k: attrs ? ${k}) ["worktrees" "remotes"]))
      (cfg.extraConfig.projects or {}));

    errors = entryErrors ++ collisionErrors ++ nestingErrors;
    refuse = value:
      if errors == []
      then value
      else throw "workspace declaration is invalid:\n${lib.concatStringsSep "\n" errors}";

    resolveEntry = key: repo: let
      remote = cfg.remotes.${repo.remote};
      url =
        if repo.url != null
        then repo.url
        else joinRemote remote.url (repo.name + remote.suffix);
      remoteAliases = lib.optionals (repo.remote != null) (map (base: joinRemote base (repo.name + remote.suffix)) remote.aliases);
    in {
      inherit key url;
      aliases = lib.filter (a: a != url) (lib.unique (remoteAliases ++ repo.aliases));
      inherit (repo) path;
      groups = effectiveGroups repo;
    };

    resolvedFile = pkgs.writeText "workbench-workspace.json" (builtins.toJSON cfg.resolved);

    maniYaml =
      lib.recursiveUpdate {
        # Workspace repos typically allowlist what they track; mani
        # appending every project path to .gitignore fights that.
        sync_gitignore = false;
        # Remote and worktree management stay with git and the worktree
        # tool; spelled out so the manifest is safe whatever mani defaults.
        sync_remotes = false;
        remove_orphaned_worktrees = false;
        projects = lib.listToAttrs (map (entry: {
            name = entry.key;
            value = {
              inherit (entry) path url;
              tags = entry.groups;
            };
          })
          cfg.resolved);
        inherit (cfg) tasks;
      }
      cfg.extraConfig;
  in {
    imports = [(lib.mkAliasOptionModule ["workbench" "workspace"] ["agentic" "workspace"])];

    options.agentic.workspace = {
      remotes = lib.mkOption {
        type = types.attrsOf (types.submodule remoteModule);
        default = {};
        description = "Named places repositories are cloned from, on any forge.";
      };
      repos = lib.mkOption {
        type = types.attrsOf (types.submodule repoModule);
        default = {};
        description = "Repos in this workspace, keyed by mani project name.";
      };
      defaultPath = lib.mkOption {
        type = types.functionTo types.str;
        default = entry: entry.name;
        defaultText = lib.literalExpression "entry: entry.name";
        example = lib.literalExpression ''
          r: let area = lib.findFirst (g: lib.elem g [ "infra" "apps" ]) null r.groups;
            in if area == null then r.name else "''${area}/''${r.name}"
        '';
        description = ''
          Checkout path of a repository without an explicit `path`, given
          exactly `{ key, name, remote, groups }`. The default puts every
          repository at its name under the workspace root; express an area
          layout through groups.
        '';
      };
      resolved = lib.mkOption {
        type = types.listOf (types.submodule {
          options = {
            key = lib.mkOption {type = types.str;};
            url = lib.mkOption {type = types.str;};
            aliases = lib.mkOption {type = types.listOf types.str;};
            path = lib.mkOption {type = types.str;};
            groups = lib.mkOption {type = types.listOf types.str;};
          };
        });
        readOnly = true;
        description = ''
          The declaration with remotes joined, paths computed and aliases
          expanded: one `{ key, url, aliases, path, groups }` per repository,
          sorted by key. JSON-serialisable; renderers and workspace helpers
          read only this. Evaluating it fails while the declaration is
          invalid. The dev shell exports it as a JSON file at
          `$WORKBENCH_WORKSPACE_MANIFEST`.
        '';
      };
      renderers.mani.enable = lib.mkOption {
        type = types.bool;
        default = cfg.repos != {};
        defaultText = lib.literalMD "true when any repository is declared";
        description = "Render `mani.yaml` from the resolved declaration.";
      };
      tasks = lib.mkOption {
        type = types.attrsOf types.anything;
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
        type = types.attrsOf types.anything;
        default = {};
        description = ''
          Freeform mani.yaml settings merged recursively over the generated
          ones. Settings that let mani change existing checkouts
          (`sync_gitignore`, `sync_remotes`, `remove_orphaned_worktrees`,
          per-project `worktrees` and `remotes`) are refused.
        '';
      };
    };

    config = lib.mkMerge [
      {agentic.workspace.resolved = refuse (lib.mapAttrsToList resolveEntry cfg.repos);}
      (lib.mkIf (cfg.repos != {}) {
        assertions =
          map (message: {
            assertion = false;
            inherit message;
          })
          (errors ++ maniErrors);
        warnings = lib.concatLists (lib.mapAttrsToList (key: repo:
          lib.optional (repo.tags != [])
          "workspace.repos.${key}.tags is deprecated; use groups.")
        cfg.repos);
        packages = [pkgs.git] ++ lib.optional cfg.renderers.mani.enable pkgs.mani;
        env.WORKBENCH_WORKSPACE_MANIFEST = resolvedFile;
      })
      # Rendering writes the manifest and nothing else: no clone, fetch or
      # move happens at shell entry; `mani sync` is run by hand.
      (lib.mkIf cfg.renderers.mani.enable {
        files."mani.yaml".yaml =
          if maniErrors == []
          then maniYaml
          else throw "workspace mani renderer refused:\n${lib.concatStringsSep "\n" maniErrors}";
      })
    ];
  };

  homeModule = {
    config,
    lib,
    options,
    ...
  }: let
    cfg = config.agentic.workspace;
  in {
    imports = [workbenchAliasHome];

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
  # The whole `workbench` tree, not just `workbench.workspace`: the user
  # adapter (adapters/user.nix) aliases the whole tree in the same Home
  # Manager evaluation, and the shared key makes the two one module.
  workbenchAliasHome = {
    key = "agentic/workbench-alias/homeManager";
    imports = [({lib, ...}: {imports = [(lib.mkAliasOptionModule ["workbench"] ["agentic"])];})];
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
