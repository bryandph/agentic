{stdenvNoCC, ...}:
stdenvNoCC.mkDerivation {
  pname = "pi-seat-snapshot";
  version = "1.0.0";
  src = ./.;
  dontBuild = true;
  installPhase = ''
    mkdir -p "$out"
    cp index.js package.json "$out/"
  '';
}
