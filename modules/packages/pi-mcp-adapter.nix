{
  perSystem = {pkgs, ...}: {
    packages.pi-mcp-adapter = pkgs.callPackage ./_pi-mcp-adapter {};
  };
}
