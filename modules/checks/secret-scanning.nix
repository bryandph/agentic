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
    consumer = enabled:
      inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [config.flake.flakeModules.default];
        agentic.secretScanning.enable = enabled;
      };
    # Expose the transport-neutral library via a tiny independent option harness.
    registry =
      (pkgs.lib.evalModules {
        modules = [../registry/_secret-scanning.nix {agentic.secretScanning.enable = true;}];
      }).config.agentic.secretScanning;
    shell =
      (pkgs.lib.evalModules {
        specialArgs = {inherit pkgs;};
        modules = [
          registry.lib.devenvModule
          ({lib, ...}: {
            options = {
              packages = lib.mkOption {type = lib.types.listOf lib.types.package;};
              tasks = lib.mkOption {
                type = lib.types.attrs;
                default = {};
              };
              git-hooks = lib.mkOption {
                type = lib.types.attrs;
                default = {};
              };
            };
          })
        ];
      }).config;
    package = registry.lib.package pkgs;
  in {
    checks.secret-scanning-source = registry.lib.check pkgs inputs.self;
    checks.secret-scanning = assert shell.git-hooks.hooks.agentic-secret-scan.pass_filenames == false;
    assert shell.git-hooks.hooks.agentic-secret-scan.stages == ["pre-commit"];
    assert !(consumer false).packages.${system} ? agentic-secret-scan;
    assert (consumer true).checks.${system} ? secret-scanning;
      pkgs.runCommand "agentic-secret-scanning-fixtures" {
        nativeBuildInputs = [pkgs.python3 pkgs.git];
      } ''
        export HOME=$TMPDIR
        python3 ${../_secret-scanning/test.py} ${package}/bin/agentic-secret-scan > "$out"
      '';
  };
}
