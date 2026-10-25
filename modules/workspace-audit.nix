# `workspace-audit`: a read-only comparison of the resolved workspace
# declaration ($WORKBENCH_WORKSPACE_MANIFEST) with the tree under the
# workspace root. It reports declared checkouts that are missing, declared
# paths that are not git repositories, origins that match neither the
# declared URL nor an alias, and top-level directories nobody declared.
# It changes nothing and exits non-zero only with `--strict`.
#
# Published by appending to the workspace devenv module, so it ships
# wherever that module does and, like it, adds nothing to a shell with no
# repositories declared.
let
  devenvModule = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.agentic.workspace;
    ignoreFile = pkgs.writeText "workspace-audit-ignore.json" (builtins.toJSON cfg.audit.ignore);
    audit = pkgs.writeShellApplication {
      name = "workspace-audit";
      runtimeInputs = [pkgs.python3 pkgs.git];
      text = ''
        exec python3 -B ${./_workspace-audit/workspace-audit.py} --ignore-file ${ignoreFile} "$@"
      '';
    };
  in {
    options.agentic.workspace.audit.ignore = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[^/]+");
      default = [];
      example = ["scratch" "result"];
      description = ''
        Top-level names under the workspace root that `workspace-audit`
        does not report as undeclared. Parents of declared paths and
        dot-directories (`.git`, `.direnv`, `.devenv`, `.worktrees`, ...)
        are never reported and need no entry.
      '';
    };

    # Same gate as the manifest itself: no repositories, no command.
    config = lib.mkIf (cfg.repos != {}) {
      packages = [audit];
    };
  };
  devenv = {
    key = "agentic/workspace-audit/devenv";
    imports = [devenvModule];
  };
in {
  flake.modules = {
    devenv.workspace.imports = [devenv];
    flake.agentic.flake.modules.devenv.workspace.imports = [devenv];
  };
}
