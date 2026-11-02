{pkgs}:
pkgs.writeShellApplication {
  name = "agentic-attention-watch";
  runtimeInputs = [pkgs.python3];
  text = ''
    exec python3 ${./attention_watch.py} "$@"
  '';
}
