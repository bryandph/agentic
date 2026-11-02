pkgs: name:
pkgs.writeShellApplication {
  inherit name;
  text = ''
    ${pkgs.python3}/bin/python3 ${./.}/${
      if name == "agentic-seat-snapshot"
      then "snapshots.py"
      else "recover.py"
    } "$@"
  '';
}
