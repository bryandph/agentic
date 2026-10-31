{
  lib,
  config,
  ...
}: let
  cfg = config.agentic.secretScanning;
  package = pkgs:
    import ../_secret-scanning/package.nix {
      inherit pkgs;
      inherit (cfg) baseline ignoreFile;
      config = (pkgs.formats.toml {}).generate "agentic-secret-scanning.toml" cfg.config;
    };
in {
  options.agentic.secretScanning = {
    enable = lib.mkEnableOption "shared Betterleaks hook, CLI and source-tree check";
    config = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {};
      description = "Shared Betterleaks TOML settings. Environment layers may merge rules/allowlists or override this set; defaults extend upstream rules.";
    };
    baseline = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Repository-relative sanitized JSON baseline (Fingerprint fields); never store raw scanner reports.";
    };
    ignoreFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Repository-relative Betterleaks fingerprint ignore file.";
    };
    lib = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = "package pkgs, check pkgs source, and devenvModule share the configured scanner.";
    };
  };
  config.agentic.secretScanning.config.extend.useDefault = lib.mkDefault true;
  config.agentic.secretScanning.lib = {
    inherit package;
    check = pkgs: source:
      pkgs.runCommand "agentic-secret-scan" {} ''
        ${package pkgs}/bin/agentic-secret-scan --mode worktree --source ${source} --report "$out"
      '';
    devenvModule = {pkgs, ...}: {
      imports = [../_git-hooks/devenv.nix];
      config = import ../_secret-scanning/hook.nix {
        inherit lib pkgs;
        scanning = cfg;
      };
    };
  };
}
