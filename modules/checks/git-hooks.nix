# Exercise the public module's exact task commands, without collecting garbage.
{
  inputs,
  config,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    consumer = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [system];
      imports = [
        config.flake.flakeModules.default
        ({config, ...}: {flake.testDevenvLib = config.agentic.devenvLib;})
      ];
    };
    devenvLib = consumer.testDevenvLib;
    # A minimal devenv option harness proves this module does not depend on the
    # registry/bootstrap or MCP. Test both supported public import surfaces.
    evaluate = packages: module:
      pkgs.lib.evalModules {
        specialArgs.pkgs = packages;
        modules = [
          module
          ({lib, ...}: {
            options = {
              packages = lib.mkOption {type = lib.types.listOf lib.types.package;};
              tasks = lib.mkOption {type = lib.types.attrs;};
              git-hooks.enable = lib.mkOption {default = true;};
            };
          })
        ];
      };
    standalone = (evaluate pkgs config.flake.devenvModules.git-hooks).config;
    registry = (evaluate pkgs devenvLib.gitHooksModule).config;
    tools = import ../_git-hooks/package.nix pkgs;
    # Build sandboxes cannot register daemon GC roots. Model only that daemon
    # operation; a host-side smoke test exercises unprivileged registration.
    rootRecorder = pkgs.writeShellApplication {
      name = "nix-store";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        if [ "''${failRootRegistration:-0}" = 1 ]; then exit 1; fi
        test "$#" = 5
        test "$1" = --add-root
        test "$3" = --indirect
        test "$4" = --realise
        test -d "$5"
        printf '%s\n' "$2 -> $5" >> "''${registrationLog:?}"
        ln -sfn "$5" "$2"
      '';
    };
    sandbox = (evaluate (pkgs // {nix = rootRecorder;}) config.flake.devenvModules.git-hooks).config;
  in {
    checks.git-hooks = assert standalone.tasks == registry.tasks;
    assert standalone.tasks."agentic:worktree-hooks".before == ["devenv:git-hooks:install"];
    assert standalone.tasks."agentic:git-hooks-root".after == ["devenv:git-hooks:install"];
    assert builtins.elem tools (devenvLib.packages pkgs);
      pkgs.runCommand "agentic-git-hooks" {
        nativeBuildInputs = [pkgs.git pkgs.prek pkgs.python3 pkgs.coreutils];
        isolate = standalone.tasks."agentic:worktree-hooks".exec;
        root = sandbox.tasks."agentic:git-hooks-root".exec;
        doctor = "${tools}/bin/agentic-hooks-doctor";
        prekStore = "${pkgs.prek}";
      } ''
        bash ${./_git-hooks/fixture.sh}
        bash ${./_git-hooks/checkouts.sh}
        touch $out
      '';
  };
}
