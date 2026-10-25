# Local flake-input overrides (design D6): the workspace shell gains a
# `workspace-overrides` command that reads a consumer flake's flake.lock
# and the resolved declaration ($WORKBENCH_WORKSPACE_MANIFEST) and emits
# `--override-input <input> git+file://<checkout>` for every input whose
# locked or original URL is a declared repository's URL or alias, plus
# `--no-write-lock-file`. `workspace-overrides -- nix build .#x` runs the
# command with them; nothing applies overrides implicitly.
#
# `overrides.<input path> = "<key>"` maps inputs no URL can match, such as
# a relative `path:` input backed by a submodule. It reaches the command
# as the JSON file $WORKBENCH_WORKSPACE_OVERRIDES.
let
  devenvModule = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.agentic.workspace;
    keys = map (e: e.key) cfg.resolved;
    unknown = lib.filterAttrs (_: key: !(lib.elem key keys)) cfg.overrides;
  in {
    options.agentic.workspace.overrides = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {"core" = "agentic";};
      description = ''
        Flake inputs of a consumer, by slash-separated input path, that
        `workspace-overrides` points at a declared repository's checkout
        even though their URL does not match it, such as a relative
        `path:` input backed by a submodule. `--map` on the command line
        wins over an entry here.
      '';
    };

    config = lib.mkIf (cfg.repos != {}) {
      assertions =
        lib.mapAttrsToList (input: key: {
          assertion = false;
          message = "workspace.overrides.${input}: `${key}` is not a declared repository.";
        })
        unknown;
      packages = [(import ./_workspace-overrides/package.nix {inherit pkgs;})];
      env.WORKBENCH_WORKSPACE_OVERRIDES = lib.mkIf (cfg.overrides != {}) (pkgs.writeText "workbench-workspace-overrides.json" (builtins.toJSON cfg.overrides));
    };
  };
  devenv = {
    key = "agentic/workspace-overrides/devenv";
    imports = [devenvModule];
  };
in {
  flake.modules = {
    devenv.workspace.imports = [devenv];
    flake.agentic.flake.modules.devenv.workspace.imports = [devenv];
  };
}
