{pkgs}: let
  # nixpkgs' nats-py credentials support imports Python nkeys, but the
  # optional-dependency currently resolves to the unrelated Go CLI package.
  nkeys = pkgs.python3Packages.buildPythonPackage rec {
    pname = "nkeys";
    version = "0.2.1";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-OiAdzSA9i7BboohNRBsskpGLKlN6ENMk5zc4iH3enaM=";
    };
    build-system = [pkgs.python3Packages.setuptools];
    dependencies = [pkgs.python3Packages.pynacl];
    pythonImportsCheck = ["nkeys"];
  };
  python = pkgs.python3.withPackages (ps: [ps.nats-py nkeys]);
in
  pkgs.writeShellApplication {
    name = "agentic-attention-watch";
    runtimeInputs = [python];
    passthru = {inherit python;};
    text = ''
      exec python3 ${./attention_watch.py} "$@"
    '';
  }
