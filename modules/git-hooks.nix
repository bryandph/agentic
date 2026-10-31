# Public CLI for operators who want diagnostics without entering a dev shell.
{
  perSystem = {pkgs, ...}: {
    packages.agentic-hooks-doctor = import ./_git-hooks/package.nix pkgs;
  };
}
