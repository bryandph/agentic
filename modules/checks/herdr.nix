# Fixture checks for the core `programs.herdr` module, through the same
# test-only Home Manager pin as workspace-home. A stub package stands in
# for the consumer-supplied Herdr: it only reports the config path it was
# started with, so the launcher's reconciliation runs for real.
{
  inputs,
  config,
  ...
}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    hmSource = builtins.fetchTree {
      type = "github";
      owner = "nix-community";
      repo = "home-manager";
      rev = "65258d5c65a250189fde2e35f490d15e064c4c62";
      narHash = "sha256-Sxu1NLTD/Ern6hFGLlZmtKCSct3YQXZI/lls8RE1XeM=";
    };
    evalHome = modules:
      (import "${hmSource}/lib" {inherit lib;}).homeManagerConfiguration {
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
      };
    herdrStub = pkgs.writeShellScriptBin "herdr" ''
      echo "stub herdr: $HERDR_CONFIG_PATH"
    '';
    rooted = {agentic.workspace.root = "/home/fixture/ws";};
    enabled = {
      programs.herdr = {
        enable = true;
        package = herdrStub;
        extraConfig.ui.sidebar.width = 30;
      };
    };

    # Core-only consumers: the workspace guard sees core's programs.herdr.
    viaAgentic = (evalHome [config.flake.homeModules.agentic enabled rooted]).config;
    viaWorkbench = (evalHome [config.flake.homeModules.workbench enabled rooted]).config;
    # Standalone exports alongside the bundle dedupe by key.
    viaBoth = (evalHome [config.flake.homeModules.herdr config.flake.homeModules.agentic enabled rooted]).config;
    disabled = (evalHome [config.flake.homeModules.agentic rooted]).config;
    workspaceOnly = evalHome [config.flake.homeModules.workspace rooted];

    # A flake-parts consumer that carries its own herdr module in its own
    # namespace: core must not merge a second `programs.herdr` into it.
    consumer = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [system];
      imports = [
        config.flake.flakeModules.default
        {
          agentic.secrets.backend = "env";
          flake.modules.homeManager.herdr = {lib, ...}: {
            options.programs.herdr = {
              owner = lib.mkOption {default = "consumer";};
              extraConfig = lib.mkOption {
                type = (pkgs.formats.toml {}).type;
                default = {};
              };
            };
          };
        }
      ];
    };
    viaConsumer =
      (evalHome [
        consumer.modules.homeManager.agentic
        consumer.modules.homeManager.herdr
        rooted
      ]).config;

    mentionsHerdr = names: lib.any (lib.hasInfix "herdr") (map lib.toLower names);
    wrapped = lib.findFirst (p: (p.name or "") == "herdr-wrapped") null viaAgentic.home.packages;

    valid =
      viaAgentic.programs.herdr.extraConfig.worktrees.directory
      == "/home/fixture/ws/.worktrees"
      && viaWorkbench.programs.herdr.extraConfig.worktrees.directory == "/home/fixture/ws/.worktrees"
      && viaBoth.programs.herdr.extraConfig.worktrees.directory == "/home/fixture/ws/.worktrees"
      && wrapped != null
      # Disabled: the guard still fires (the option exists), but nothing is
      # installed, written or activated.
      && disabled.programs.herdr.extraConfig.worktrees.directory == "/home/fixture/ws/.worktrees"
      && !(lib.any (p: lib.hasInfix "herdr" (p.name or "")) disabled.home.packages)
      && !(mentionsHerdr (lib.attrNames disabled.home.file))
      && !(mentionsHerdr (lib.attrNames disabled.xdg.configFile))
      && !(mentionsHerdr (lib.attrNames disabled.home.activation))
      # homeModules.workspace alone: no programs.herdr, git still configured.
      && !(workspaceOnly.options ? programs.herdr)
      && workspaceOnly.config.programs.git.settings.worktree.useRelativePaths
      # Consumer namespace: its own programs.herdr, declared once.
      && viaConsumer.programs.herdr.owner == "consumer"
      && viaConsumer.programs.herdr.extraConfig.worktrees.directory == "/home/fixture/ws/.worktrees";
  in {
    checks.herdr-home = assert valid;
      pkgs.runCommand "agentic-herdr-home" {
        nativeBuildInputs = [wrapped pkgs.python3];
      } ''
        set -euo pipefail
        export HOME=$TMPDIR/home XDG_STATE_HOME=$TMPDIR/state
        export HERDR_CONFIG_PATH=$TMPDIR/config/herdr/config.toml
        mkdir -p "$HOME" "$(dirname "$HERDR_CONFIG_PATH")"

        # Live file as Herdr leaves it: runtime keys at the top level and
        # under [ui], plus a stale value for a key Nix owns.
        cat > "$HERDR_CONFIG_PATH" <<'EOF'
        onboarding = false

        [ui]
        status_indicators = "dots"

        [ui.sound]
        enabled = true

        [worktrees]
        directory = "/stale"
        EOF

        herdr | grep -qF "stub herdr: $HERDR_CONFIG_PATH"

        python3 - "$HERDR_CONFIG_PATH" <<'EOF'
        import sys, tomllib
        live = tomllib.load(open(sys.argv[1], "rb"))
        assert live["worktrees"]["directory"] == "/home/fixture/ws/.worktrees", live
        assert live["ui"]["sidebar"]["width"] == 30, live
        assert live["onboarding"] is False, live
        assert live["ui"]["status_indicators"] == "dots", live
        assert live["ui"]["sound"]["enabled"] is True, live
        EOF

        # Herdr rewrites the file at runtime; the next launch keeps it.
        sed -i '1i runtime_written = "kept"' "$HERDR_CONFIG_PATH"
        herdr > /dev/null
        python3 -c 'import sys, tomllib; assert tomllib.load(open(sys.argv[1], "rb"))["runtime_written"] == "kept"' "$HERDR_CONFIG_PATH"
        touch $out
      '';
  };
}
