pkgs:
pkgs.writeShellApplication {
  name = "workbench-worker-start";
  text = ''
    ${pkgs.python3}/bin/python3 ${./_worker-start.py} "$@"
  '';
}
