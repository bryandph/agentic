# Knowledge bundle: an Open Knowledge Format (OKF 0.2) bundle committed
# in the repository, holding its specs, decisions and agent memory. Each
# concept is one markdown file with frontmatter
# (`type`, provenance in `generated`, review in `verified`, lifecycle in
# `status` / `stale_after`); the `memory` skill carries the curation
# rules. Plain files: git is the durability and history, any OKF or
# markdown tool can read them.
#
# Search is qmd over a project-local index, which gives the scoping:
# a scope's index covers its own bundle plus the bundles of the child
# scopes it declares, and a child never sees its parent.
#
# Inert until `root` is set.
{
  lib,
  config,
  ...
}: let
  cfg = config.agentic.bundle;

  collectionName = path: lib.replaceStrings ["/"] ["-"] (lib.removeSuffix "/.okf" path);
in {
  options.agentic.bundle = {
    root = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = ".okf";
      description = "Repository-relative OKF bundle (specs, decisions, memory). Setting it enables bundle search.";
    };

    children = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["finance/.okf"];
      description = ''
        Bundles of child scopes (paths relative to this
        repository), searchable from here. A parent lists its children;
        children never list a parent.
      '';
    };
  };

  config = lib.mkIf (cfg.root != null) {
    agentic.knowledgeSearch = {
      index = "local";
      collections =
        {okf.path = cfg.root;}
        // lib.listToAttrs (map (p: lib.nameValuePair (collectionName p) {path = p;}) cfg.children);
    };
  };
}
