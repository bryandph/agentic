{
  flake.modules.flake.agentic = {
    config,
    lib,
    inputs,
    ...
  }: {
    perSystem = {pkgs, ...}:
      lib.mkIf config.agentic.secretScanning.enable {
        packages.agentic-secret-scan = config.agentic.secretScanning.lib.package pkgs;
        checks.secret-scanning = config.agentic.secretScanning.lib.check pkgs inputs.self;
      };
  };
  perSystem = {pkgs, ...}: {
    packages.agentic-secret-scan = import ./_secret-scanning/package.nix {
      inherit pkgs;
      config = (pkgs.formats.toml {}).generate "agentic-secret-scanning.toml" {extend.useDefault = true;};
    };
  };
}
