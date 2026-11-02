{
  perSystem = {pkgs, ...}: {
    packages.pi-seat-snapshot = pkgs.callPackage ./_pi-seat-snapshot {};
  };
}
