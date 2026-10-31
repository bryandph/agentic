# Both entrypoints share a parser; hooks are read as data, never executed.
pkgs:
pkgs.symlinkJoin {
  name = "agentic-hooks";
  meta.mainProgram = "agentic-hooks-doctor";
  paths =
    map
    (mode:
      pkgs.writeShellApplication {
        name = "agentic-hooks-${mode}";
        runtimeInputs = [pkgs.git pkgs.nix];
        text = ''
          exec ${pkgs.python3}/bin/python3 ${./hooks.py} ${mode} "$@"
        '';
      })
    ["doctor" "root"];
}
