# Org-neutral `programs.herdr` Home Manager module: `enable`, a
# consumer-supplied `package`, and `extraConfig` rendered to Herdr's
# `config.toml`. Core pins no Herdr; importing the module with `enable`
# false writes nothing.
#
# Herdr writes runtime state into its own config.toml, so the file is not
# a store symlink. Nix renders the desired projection and the wrapped
# `herdr` launcher reconciles the Nix-owned keys into the writable live
# file before Herdr starts, keeping every key Herdr wrote itself. Herdr
# keeps its own settings under `[ui]`, so Nix owns `ui.<table>` entries
# rather than the whole section.
#
# Plugins, agent-detection overrides, key bindings, commands and SSH host
# handling are consumer choices: plain `extraConfig` values, or the
# consumer's own module next to this one.
let
  homeModule = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.programs.herdr;
    tomlFormat = pkgs.formats.toml {};
    desiredConfig = tomlFormat.generate "herdr-config-desired.toml" cfg.extraConfig;
    reconcileConfig = pkgs.writeShellApplication {
      name = "herdr-config-reconcile";
      runtimeInputs = [(pkgs.python3.withPackages (ps: [ps.tomlkit]))];
      text = ''
        exec python3 ${./_herdr/config-reconcile.py} "$@"
      '';
    };
    wrappedPackage = pkgs.symlinkJoin {
      name = "herdr-wrapped";
      paths = [cfg.package];
      nativeBuildInputs = [pkgs.makeWrapper];
      postBuild = ''
        wrapProgram "$out/bin/herdr" \
          --run ${lib.escapeShellArg "${lib.getExe reconcileConfig} ${desiredConfig} --shared-table ui || exit $?"}
      '';
    };
  in {
    options.programs.herdr = {
      enable = lib.mkEnableOption "Herdr";

      package = lib.mkOption {
        type = lib.types.package;
        description = "The Herdr package; consumer-supplied, core pins none.";
      };

      extraConfig = lib.mkOption {
        inherit (tomlFormat) type;
        default = {};
        example = {worktrees.directory = "/home/user/src/.worktrees";};
        description = ''
          Herdr settings in Herdr's own key names, rendered to TOML and
          reconciled into the live config.toml at launch. Top-level keys are
          owned whole, except `ui`, where each `ui.<table>` is owned; keys
          not set here stay as Herdr wrote them.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [wrappedPackage];
    };
  };
  # Keyed so importing both `agentic` and the standalone `herdr` export
  # declares the options once.
  homeManager = {
    key = "agentic/herdr/homeManager";
    imports = [homeModule];
  };
in {
  # Core's own namespace only (aliased by exports.nix as homeModules.herdr,
  # and carried by homeModules.agentic/workbench). Unlike workspace.nix this
  # is deliberately not published into the consumer's namespace through the
  # exported flakeModule: a consumer's `flake.modules.homeManager` may already
  # carry its own herdr module, and merging core's in would declare
  # `programs.herdr` twice. Flake-parts consumers opt in with
  # `inputs.<core>.homeModules.herdr`.
  flake.modules.homeManager = {
    herdr = homeManager;
    agentic.imports = [homeManager];
  };
}
