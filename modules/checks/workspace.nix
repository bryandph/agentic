# Fixture checks for the workspace layout feature. devenv is not pinned
# by core, so the devenv half evaluates against stubs of the devenv
# options it writes and the rendered mani.yaml is validated by mani
# itself. The HM half uses the same test-only Home Manager pin as the
# pi-mcp fixture, with a stub `programs.herdr` standing in for the
# consumer-provided herdr module.
{config, ...}: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    devenvStubs = {
      options = {
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [];
        };
        files = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
          default = {};
        };
        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = {};
        };
        assertions = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [];
        };
        warnings = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
        };
      };
    };
    evalDevenv = extra:
      (lib.evalModules {
        modules = [
          devenvStubs
          {_module.args.pkgs = pkgs;}
          config.flake.devenvModules.workspace
          extra
        ];
      }).config;
    manifestOf = cfg: cfg.files."mani.yaml".yaml;
    yamlOf = name: cfg: (pkgs.formats.yaml {}).generate "${name}-mani.yaml" (manifestOf cfg);
    failedMessages = cfg: map (a: a.message) (lib.filter (a: !a.assertion) cfg.assertions);
    # A refused declaration names every entry involved and renders nothing.
    refuses = keys: cfg: let
      messages = failedMessages cfg;
    in
      messages
      != []
      && lib.all (key: lib.any (lib.hasInfix key) messages) keys
      && !(builtins.tryEval (builtins.deepSeq (manifestOf cfg) true)).success;

    # The milestone fixture, unchanged: explicit path, URL and tags.
    milestoneRepos = {
      core = {
        path = "src/core";
        url = "https://forge.fixture.example/core.git";
        tags = ["nix"];
      };
      docs = {
        path = "docs";
        url = "https://forge.fixture.example/docs.git";
      };
    };
    populated = evalDevenv {agentic.workspace.repos = milestoneRepos;};
    # mani.yaml project entries the milestone rendered for that fixture
    # (task 1.3, recorded before the schema change).
    milestoneProjects = {
      core = {
        path = "src/core";
        tags = ["nix"];
        url = "https://forge.fixture.example/core.git";
      };
      docs = {
        path = "docs";
        tags = [];
        url = "https://forge.fixture.example/docs.git";
      };
    };

    # A non-Gitea forge: scp-style base on a nested group, with an HTTPS
    # mirror alias, next to a plain HTTPS remote with no suffix.
    forge = evalDevenv {
      workbench.workspace = {
        remotes = {
          lab = {
            url = "git@gitlab.fixture.example:group/subgroup";
            aliases = ["https://mirror.fixture.example/group/subgroup/"];
          };
          plain = {
            url = "https://code.fixture.example/scm/team";
            suffix = "";
          };
        };
        repos = {
          tool = {
            remote = "lab";
            groups = ["nix"];
          };
          renamed = {
            remote = "plain";
            name = "upstream-name";
            aliases = ["ssh://git@other.fixture.example/upstream-name.git"];
          };
        };
      };
    };
    forgeExpected = [
      {
        key = "renamed";
        url = "https://code.fixture.example/scm/team/upstream-name";
        aliases = ["ssh://git@other.fixture.example/upstream-name.git"];
        path = "upstream-name";
        groups = [];
      }
      {
        key = "tool";
        url = "git@gitlab.fixture.example:group/subgroup/tool.git";
        aliases = ["https://mirror.fixture.example/group/subgroup/tool.git"];
        path = "tool";
        groups = ["nix"];
      }
    ];

    # A flat list by full URL: no remotes, paths or groups.
    flat = evalDevenv {
      workbench.workspace.repos = {
        alpha.url = "https://alpha.fixture.example/alpha.git";
        beta.url = "ssh://git@beta.fixture.example:2222/beta.git";
        gamma.url = "git@gamma.fixture.example:gamma.git";
      };
    };

    # Area layout as configuration: area repositories under a folder
    # named after their area group, the rest at the root.
    area = evalDevenv ({lib, ...}: {
      workbench.workspace = {
        remotes.home.url = "https://forge.fixture.example/team";
        defaultPath = r: let
          found = lib.findFirst (g: lib.elem g ["infra" "apps"]) null r.groups;
        in
          if found == null
          then r.name
          else "${found}/${r.name}";
        repos = {
          instance.remote = "home";
          cluster = {
            remote = "home";
            groups = ["infra" "nix"];
          };
          web = {
            remote = "home";
            groups = ["apps"];
          };
          pinned = {
            remote = "home";
            groups = ["apps"];
            path = "elsewhere/pinned";
          };
        };
      };
    });
    pathsOf = cfg: lib.listToAttrs (map (e: lib.nameValuePair e.key e.path) cfg.workbench.workspace.resolved);

    # Both namespaces feed one declaration.
    mixed = evalDevenv {
      imports = [
        {workbench.workspace.repos.alpha.url = "https://alpha.fixture.example/alpha.git";}
        {agentic.workspace.repos.beta.url = "https://beta.fixture.example/beta.git";}
      ];
    };
    single = evalDevenv {
      agentic.workspace.repos = {
        alpha.url = "https://alpha.fixture.example/alpha.git";
        beta.url = "https://beta.fixture.example/beta.git";
      };
    };

    withRepos = repos: extra: evalDevenv {imports = [{workbench.workspace.repos = repos;} extra];};
    oneRepo = {a.url = "https://forge.fixture.example/a.git";};
    refusals = {
      both = refuses ["dual"] (withRepos {
          dual = {
            remote = "home";
            url = "https://forge.fixture.example/dual.git";
          };
        } {
          workbench.workspace.remotes.home.url = "https://forge.fixture.example";
        });
      neither = refuses ["bare"] (withRepos {bare = {};} {});
      undeclaredRemote = refuses ["lost"] (withRepos {lost.remote = "nowhere";} {});
      collision = refuses ["dup-one" "dup-two"] (withRepos {
        dup-one = {
          url = "https://forge.fixture.example/one.git";
          path = "same";
        };
        dup-two = {
          url = "https://forge.fixture.example/two.git";
          path = "same";
        };
      } {});
      nestedExplicit = refuses ["outer" "inner"] (withRepos {
        outer = {
          url = "https://forge.fixture.example/outer.git";
          path = "a";
        };
        inner = {
          url = "https://forge.fixture.example/inner.git";
          path = "a/b";
        };
      } {});
      nestedDefault = refuses ["outer" "inner"] (withRepos {
          outer.url = "https://forge.fixture.example/a.git";
          inner = {
            url = "https://forge.fixture.example/b.git";
            groups = ["a"];
          };
        } {
          workbench.workspace.defaultPath = r:
            if r.groups == []
            then "a"
            else "a/${r.key}";
        });
      unnormalised = lib.all (path:
        refuses ["odd"] (withRepos {
          odd = {
            url = "https://forge.fixture.example/odd.git";
            inherit path;
          };
        } {})) ["" "." "/abs" "x/" "x//y" "x/./y" "../up"];
      syncRemotes = refuses ["sync_remotes"] (withRepos oneRepo {workbench.workspace.extraConfig.sync_remotes = true;});
      orphans = refuses ["remove_orphaned_worktrees"] (withRepos oneRepo {workbench.workspace.extraConfig.remove_orphaned_worktrees = true;});
      gitignore = refuses ["sync_gitignore"] (withRepos oneRepo {workbench.workspace.extraConfig.sync_gitignore = true;});
      projectWorktrees = refuses ["projects.a.worktrees"] (withRepos oneRepo {
        workbench.workspace.extraConfig.projects.a.worktrees = [{path = "wt";}];
      });
      projectRemotes = refuses ["projects.a.remotes"] (withRepos oneRepo {
        workbench.workspace.extraConfig.projects.a.remotes = [{name = "up";}];
      });
    };

    empty = evalDevenv {};
    maniOff = evalDevenv {
      workbench.workspace = {
        repos = oneRepo;
        renderers.mani.enable = false;
      };
    };
    # Freeform settings merge over, not replace, the generated projects.
    extraMerged = manifestOf (withRepos oneRepo {
      workbench.workspace.extraConfig = {
        shell = "bash -c";
        projects.a.desc = "first";
      };
    });

    # Every project agrees with its resolved entry, none is missing, and
    # nothing that lets mani change existing checkouts is enabled.
    agrees = cfg: let
      m = manifestOf cfg;
    in
      lib.all (e:
        m.projects ? ${e.key}
        && m.projects.${e.key}.url == e.url
        && m.projects.${e.key}.path == e.path
        && m.projects.${e.key}.tags == e.groups)
      cfg.agentic.workspace.resolved
      && m.sync_gitignore == false
      && m.sync_remotes == false
      && m.remove_orphaned_worktrees == false
      && lib.all (p: !(p ? worktrees) && !(p ? remotes)) (lib.attrValues m.projects);
    renderedFixtures = {inherit populated forge flat area mixed;};

    devenvValid =
      empty.files
      == {}
      && empty.packages == []
      && empty.env == {}
      && empty.warnings == []
      && lib.all (cfg: failedMessages cfg == [] && agrees cfg) (lib.attrValues renderedFixtures)
      # Milestone compatibility: identical projects plus a deprecation
      # warning for `tags`, and no warning without them.
      && (manifestOf populated).projects == milestoneProjects
      && populated.warnings == ["workspace.repos.core.tags is deprecated; use groups."]
      && flat.warnings == []
      && forge.workbench.workspace.resolved == forgeExpected
      && pathsOf flat
      == {
        alpha = "alpha";
        beta = "beta";
        gamma = "gamma";
      }
      && pathsOf area
      == {
        cluster = "infra/cluster";
        instance = "instance";
        pinned = "elsewhere/pinned";
        web = "apps/web";
      }
      && area.agentic.workspace.repos.web.path == "apps/web"
      && manifestOf mixed == manifestOf single
      && mixed.workbench.workspace.resolved == single.agentic.workspace.resolved
      && lib.all lib.id (lib.attrValues refusals)
      && !(maniOff.files ? "mani.yaml")
      && !(lib.elem pkgs.mani maniOff.packages)
      && extraMerged.projects.a.url == "https://forge.fixture.example/a.git"
      && extraMerged.projects.a.desc == "first"
      && extraMerged.shell == "bash -c";

    # Sync safety: local bare repositories stand in for the forge; the
    # manifest is rendered by the module with a placeholder for the
    # sandbox directory they live in.
    syncFixture = evalDevenv {
      workbench.workspace = {
        remotes.local.url = "file://@REMOTES@";
        repos = {
          kept.remote = "local";
          fresh.remote = "local";
        };
      };
    };

    hmSource = builtins.fetchTree {
      type = "github";
      owner = "nix-community";
      repo = "home-manager";
      rev = "65258d5c65a250189fde2e35f490d15e064c4c62";
      narHash = "sha256-Sxu1NLTD/Ern6hFGLlZmtKCSct3YQXZI/lls8RE1XeM=";
    };
    herdrStub = {
      options.programs.herdr.extraConfig = lib.mkOption {
        type = (pkgs.formats.toml {}).type;
        default = {};
      };
    };
    evalHome = modules:
      ((import "${hmSource}/lib" {inherit lib;}).homeManagerConfiguration {
        inherit pkgs;
        modules =
          [
            {
              home = {
                username = "fixture";
                homeDirectory = "/home/fixture";
                stateVersion = "26.05";
              };
            }
          ]
          ++ modules;
      }).config;
    rooted = {agentic.workspace.root = "/home/fixture/ws";};
    withHerdr = evalHome [config.flake.homeModules.workspace herdrStub rooted];
    withoutHerdr = evalHome [config.flake.homeModules.workspace rooted];
    unset = evalHome [config.flake.homeModules.workspace herdrStub];
    # Same feature through both exports: the key must dedupe the options.
    both = evalHome [config.flake.homeModules.workspace config.flake.homeModules.agentic rooted];
    # The workbench name resolves to the same options, standalone and
    # next to the user adapter's alias of the whole tree.
    byWorkbench = evalHome [config.flake.homeModules.workspace herdrStub {workbench.workspace.root = "/home/fixture/ws";}];
    bothByWorkbench = evalHome [config.flake.homeModules.workspace config.flake.homeModules.workbench {workbench.workspace.root = "/home/fixture/ws";}];

    hmValid =
      withHerdr.programs.herdr.extraConfig.worktrees.directory
      == "/home/fixture/ws/.worktrees"
      && withHerdr.programs.git.settings.worktree.useRelativePaths
      && withoutHerdr.programs.git.settings.worktree.useRelativePaths
      && unset.programs.herdr.extraConfig == {}
      && !(unset.programs.git.settings ? worktree)
      && both.agentic.workspace.worktreeDir == "/home/fixture/ws/.worktrees"
      && byWorkbench.programs.herdr.extraConfig.worktrees.directory == "/home/fixture/ws/.worktrees"
      && byWorkbench.agentic.workspace.root == "/home/fixture/ws"
      && bothByWorkbench.agentic.workspace.worktreeDir == "/home/fixture/ws/.worktrees"
      && bothByWorkbench.programs.git.settings.worktree.useRelativePaths;
  in {
    checks.workspace-devenv = assert devenvValid;
      pkgs.runCommand "agentic-workspace-devenv" {nativeBuildInputs = [pkgs.mani pkgs.git];} ''
        set -euo pipefail
        export HOME=$TMPDIR
        ${lib.concatStrings (lib.mapAttrsToList (name: cfg: ''
            mkdir -p $TMPDIR/${name}
            cp ${yamlOf name cfg} $TMPDIR/${name}/mani.yaml
            (cd $TMPDIR/${name} && mani check)
          '')
          renderedFixtures)}
        cd $TMPDIR/populated
        mani list projects --color=false --output markdown > projects.md
        grep -qE '^\| *core *\| *nix *\|' projects.md
        grep -qE '^\| *docs *\|' projects.md
        grep -q 'sync_gitignore: false' mani.yaml
        # The resolved form reaches scripts as JSON.
        test "$(cat ${populated.env.WORKBENCH_WORKSPACE_MANIFEST})" = ${lib.escapeShellArg (builtins.toJSON populated.agentic.workspace.resolved)}
        touch $out
      '';

    checks.workspace-sync = pkgs.runCommand "agentic-workspace-sync" {nativeBuildInputs = [pkgs.mani pkgs.git];} ''
      set -euo pipefail
      export HOME=$TMPDIR
      git config --global user.name fixture
      git config --global user.email fixture@fixture.example
      git config --global init.defaultBranch main
      remotes=$TMPDIR/remotes
      mkdir -p $remotes
      for repo in kept fresh; do
        git init -q --bare $remotes/$repo.git
        git clone -q $remotes/$repo.git $TMPDIR/seed-$repo
        echo "$repo" > $TMPDIR/seed-$repo/README
        git -C $TMPDIR/seed-$repo add README
        git -C $TMPDIR/seed-$repo commit -qm init
        git -C $TMPDIR/seed-$repo push -q origin main
      done

      ws=$TMPDIR/ws
      mkdir -p $ws
      substitute ${yamlOf "sync" syncFixture} $ws/mani.yaml --replace-fail @REMOTES@ $remotes
      git clone -q $remotes/kept.git $ws/kept
      cd $ws/kept
      # A local commit, a staged change, an uncommitted edit, an
      # untracked file and an extra worktree, all of which sync must keep.
      echo local > local; git add local; git commit -qm local
      echo staged > staged; git add staged
      echo edited >> README
      echo untracked > untracked
      git worktree add -q -b side $TMPDIR/side-wt
      git remote add mirror $remotes/fresh.git

      snapshot() {
        git -C $ws/kept rev-parse HEAD
        git -C $ws/kept for-each-ref
        git -C $ws/kept ls-files -s
        git -C $ws/kept diff
        git -C $ws/kept diff --cached
        git -C $ws/kept status --porcelain --untracked-files=all
        git -C $ws/kept remote -v
        git -C $ws/kept worktree list --porcelain
        cat $ws/kept/.git/config
        (cd $ws/kept && find . -path ./.git -prune -o -type f -print0 | sort -z | xargs -0 sha256sum)
      }
      snapshot > $TMPDIR/before
      cd $ws
      mani sync
      snapshot > $TMPDIR/after
      diff -u $TMPDIR/before $TMPDIR/after

      test "$(git -C $ws/fresh log -1 --format=%s)" = init
      test "$(git -C $ws/fresh remote get-url origin)" = "file://$remotes/fresh.git"
      test ! -e $ws/.gitignore
      touch $out
    '';

    checks.workspace-home = assert hmValid;
      pkgs.runCommand "agentic-workspace-home" {} "touch $out";
  };
}
