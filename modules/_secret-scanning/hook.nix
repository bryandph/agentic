{
  lib,
  pkgs,
  scanning,
}:
lib.mkIf scanning.enable {
  packages = [(scanning.lib.package pkgs)];
  git-hooks.hooks.agentic-secret-scan = {
    enable = true;
    name = "Betterleaks staged secrets";
    entry = "${scanning.lib.package pkgs}/bin/agentic-secret-scan --mode staged";
    pass_filenames = false;
    always_run = true;
    stages = ["pre-commit"];
  };
}
