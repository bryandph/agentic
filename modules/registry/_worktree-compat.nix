# Legacy consumer migration only; no configuration or runtime is generated.
{
  lib,
  config,
  options,
  ...
}: let
  renamed = [["traits" "submodules"] ["traits" "secretDotfiles"] ["copyFiles"]];
  retired = [
    "mainBranch"
    "mergeStrategy"
    "mode"
    "agent"
    "autoNameModel"
    "autoNamePrompt"
    "preMerge"
    "dashboard"
    "extraConfig"
  ];
  renameMessage = path: "agentic.workmux.${lib.concatStringsSep "." path} has been renamed to agentic.worktree.${lib.concatStringsSep "." path}.";
  ignoredMessage = name: "agentic.workmux.${name} is ignored: configuration generation has been retired. Remove this setting; the coordinator owns creation, launch and reviewed integration.";
  legacy = path: lib.getAttrFromPath (["agentic" "workmux"] ++ path) options;
  ignored = lib.filter (name: (legacy [name]).isDefined) retired;
in {
  options.agentic = {
    workmux =
      lib.foldl' lib.recursiveUpdate {} (map (path:
        lib.setAttrByPath path (lib.mkOption {
          type = (lib.getAttrFromPath (["agentic" "worktree"] ++ path) options).type;
          internal = true;
          description = "Legacy definition forwarded to the creator-neutral worktree option with a warning.";
        }))
      renamed)
      // lib.genAttrs retired (name:
        lib.mkOption {
          type = lib.types.unspecified;
          internal = true;
          description = "Retired configuration setting, accepted only for consumer pin compatibility.";
          apply = value: lib.warn (ignoredMessage name) value;
        });
    workmuxLib = lib.mkOption {
      type = lib.types.unspecified;
      internal = true;
      description = "Retired helper namespace; no helper implementation is exported.";
      apply = value: lib.warn "agentic.workmuxLib is ignored. Use agentic.worktreeLib.{setupScript,teardownScript,hooksScript}." value;
    };
    # Force diagnostics when canonical setup configuration is consumed, even
    # though no runner reads ignored legacy settings. Keep the value unchanged,
    # including defaults and override priorities; never create a dummy definition.
    worktree.copyFiles = lib.mkOption {
      apply = value:
        builtins.deepSeq (map (name: config.agentic.workmux.${name}) ignored)
        (builtins.deepSeq (lib.optional options.agentic.workmuxLib.isDefined config.agentic.workmuxLib) value);
    };
  };

  config.agentic.worktree = lib.mkMerge (map (path: let
    old = legacy path;
    definitions = map (lib.mkOverride (old.highestPrio or 100)) old.definitions;
  in
    lib.mkIf old.isDefined
    (lib.setAttrByPath path (lib.warn (renameMessage path) (lib.mkMerge definitions))))
  renamed);
}
