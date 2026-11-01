# Real devenv flake-parts consumer, not a stub: forcing drvPath here makes
# `nix flake check --no-build` (which disallows IFD) cover shell evaluation.
{
  inputs,
  config,
  ...
}: {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    # Test-only pin, matching a qualified consumer. Core deliberately has no
    # devenv input: the adapter must use the CONSUMER's version and package.
    devenv = builtins.getFlake "github:cachix/devenv/cd3514786a91f245abac20fcdaff044cb3e2366f?narHash=sha256-nZdDCcSYpVAVFR%2FLv2sdToMYH9WIPbsolucA7qAQJ3k%3D";
    consumerInputs = inputs // {inherit devenv;};
    consumer = inputs.flake-parts.lib.mkFlake {inputs = consumerInputs;} {
      systems = [system];
      imports = [
        devenv.flakeModule
        config.flake.flakeModules.default
      ];
      perSystem = {config, ...}: {
        devenv.shells = {
          default = {};
          another = {};
          overridden.task.package = pkgs.hello;
        };
        # Avoid readDevenvRoot's impure PWD discovery in this pure fixture.
        devenv.modules = [{devenv.root = "/tmp/agentic-devenv-tasks-fixture";}];
        legacyPackages.fixtureShells = config.devenv.shells;
      };
    };
    shells = consumer.legacyPackages.${system}.fixtureShells;
    runner = devenv.packages.${system}.devenv-tasks;
    # Upstream does not publish devenv-tasks for x86_64-darwin. On that
    # system the adapter's skip behavior below is the supported contract.
    valid =
      !(lib.hasAttrByPath ["packages" system "devenv-tasks"] devenv)
      || (
        shells.default.task.package.drvPath
        == runner.drvPath
        && shells.another.task.package.drvPath == runner.drvPath
        && shells.overridden.task.package.drvPath == pkgs.hello.drvPath
        && lib.all (name: builtins.isString consumer.devShells.${system}.${name}.drvPath)
        ["default" "another" "overridden"]
      );

    # Missing inputs/outputs must skip without defining an unknown devenv
    # option or accessing a missing system/package. Force the whole config.
    skipped = devenvInputs: let
      result = inputs.flake-parts.lib.mkFlake {inputs = inputs // devenvInputs;} {
        systems = [system];
        imports = [config.flake.flakeModules.default];
      };
    in
      builtins.attrNames result.devShells.${system} == [];
  in {
    checks.devenv-tasks = assert valid;
    assert skipped {};
    assert skipped {devenv = {};};
    assert skipped {devenv.packages.${system} = {};};
    assert skipped {devenv.packages = {};};
    assert skipped {devenv.packages.unsupported-system.devenv-tasks = pkgs.hello;};
      pkgs.runCommand "agentic-devenv-tasks" {} ''
        touch "$out"
      '';
  };
}
