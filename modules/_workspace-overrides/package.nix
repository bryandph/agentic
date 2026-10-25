# The `workspace-overrides` command, shared by the devenv module and its
# checks so both run the same build.
{pkgs}:
pkgs.writeShellApplication {
  name = "workspace-overrides";
  runtimeInputs = [pkgs.python3 pkgs.git];
  text = ''
    exec python3 ${./workspace_overrides.py} "$@"
  '';
}
