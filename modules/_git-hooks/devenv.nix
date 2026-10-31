# Standalone: no registry, MCP, organization, or shell-bootstrap dependencies.
{
  pkgs,
  config,
  lib,
  ...
}: let
  tools = import ./package.nix pkgs;
  isolate = import ./isolate.nix pkgs;
in {
  packages = [tools isolate];
  tasks = lib.mkIf (config.git-hooks.enable or false) {
    "agentic:worktree-hooks" = {
      exec = "${isolate}/bin/agentic-worktree-hooks";
      before = ["devenv:git-hooks:install"];
    };
    "agentic:git-hooks-root" = {
      exec = "${tools}/bin/agentic-hooks-root";
      after = ["devenv:git-hooks:install"];
      before = ["devenv:enterShell"];
    };
  };
}
