{
  lib,
  buildNpmPackage,
  fetchurl,
  stdenv,
  autoPatchelfHook,
  nodejs,
  keyutils,
  procps,
  zlib,
  ...
}:
buildNpmPackage {
  pname = "pi-mcp-adapter";
  version = "2.32.1";
  # npm gitHead: 10a45367e033a32026987a75d6f401e37340c86f.
  src = fetchurl {
    url = "https://registry.npmjs.org/pi-mcp-adapter/-/pi-mcp-adapter-2.32.1.tgz";
    hash = "sha512-GNLYa2U9T5ZqIhZmhx/RTenEjfakJTelq/z6Q+At5SIxyuYvrvobriDEVsnx+lqetVDizUCudTWLfdZytQu0rg==";
  };
  npmDepsHash = "sha256-OclrouYp9sHdomQtsaaV8Dv1cJzJtefJKmtFbI2uyJ0=";
  npmFlags = ["--legacy-peer-deps" "--ignore-scripts"];
  dontNpmBuild = true;
  patches = [./integration.patch];
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [autoPatchelfHook];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    zlib
  ];
  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
    substituteInPlace mcp-auth.ts \
      --replace-fail "|| 'node';" "|| '${nodejs}/bin/node';"
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      substituteInPlace mcp-auth.ts \
        --replace-fail "|| 'keyctl';" "|| '${keyutils}/bin/keyctl';"
      substituteInPlace request-headers-command.ts \
        --replace-fail 'spawnSync("ps",' 'spawnSync("${procps}/bin/ps",'
    ''}
  '';
  # Local Pi package root. Host peers are supplied by Pi's extension loader,
  # as required by Pi's package contract; all other runtime deps live here.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R . "$out/"
    cp ${./agentic.ts} "$out/agentic.ts"
    cp ${../../../docs/pi.md} "$out/AGENTIC.md"
    node -e 'const fs = require("node:fs"); const p = JSON.parse(fs.readFileSync(process.env.out + "/package.json")); p.pi.extensions = ["./agentic.ts"]; for (const name of ["pi-ai", "pi-tui", "pi-coding-agent"]) { const key = "@earendil-works/" + name; p.peerDependencies[key] = "*"; p.peerDependenciesMeta[key] = {optional: true}; } fs.writeFileSync(process.env.out + "/package.json", JSON.stringify(p, null, 2));'
    runHook postInstall
  '';
  meta = {
    description = "Pinned Pi MCP adapter with shared registry delivery and project trust guard";
    homepage = "https://github.com/nicobailon/pi-mcp-adapter";
    license = lib.licenses.mit;
    platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
  };
}
