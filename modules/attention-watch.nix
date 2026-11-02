# Observation only: executable delivery does not install a service or credentials.
{...}: {
  perSystem = {pkgs, ...}: {
    packages.agentic-attention-watch = import ./_attention-watch/package.nix {inherit pkgs;};
    checks.attention-watch =
      pkgs.runCommand "agentic-attention-watch-sandbox" {
        nativeBuildInputs = [pkgs.python3];
      } ''
        export HOME=$TMPDIR/home
        mkdir -p "$HOME"
        python3 -I ${./_attention-watch/test.py} ${./_attention-watch}
        touch $out
      '';
  };
}
