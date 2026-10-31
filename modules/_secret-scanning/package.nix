{
  pkgs,
  config,
  baseline ? null,
  ignoreFile ? null,
}: let
  script = pkgs.writeText "agentic-secret-scan.py" ''
    SCANNER = ${builtins.toJSON "${pkgs.betterleaks}/bin/betterleaks"}
    GIT = ${builtins.toJSON "${pkgs.git}/bin/git"}
    CONFIG = ${builtins.toJSON (toString config)}
    BASELINE = ${
      if baseline == null
      then "None"
      else builtins.toJSON baseline
    }
    IGNORE = ${
      if ignoreFile == null
      then "None"
      else builtins.toJSON ignoreFile
    }
    ${builtins.readFile ./scan.py}
  '';
in
  pkgs.writeShellApplication {
    name = "agentic-secret-scan";
    text = ''
      exec ${pkgs.python3}/bin/python3 ${script} "$@"
    '';
  }
