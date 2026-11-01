# Flake-parts publication of the devenv shell module (design D6/D9).
# The actual bootstrap lives transport-neutral in
# modules/registry/_bootstrap.nix (`agentic.devenvLib.shellModule`);
# the devenv-native transport wires that shellModule via /devenv.nix and
# resolves its task runner itself, without this flake-parts adapter.
{
  flake.modules.flake.agentic = {
    config,
    inputs,
    lib,
    ...
  }: {
    flake.modules.devenv.agentic = config.agentic.devenvLib.shellModule;

    perSystem = {
      system,
      options,
      ...
    }: {
      # A package-only/native devenv input does not opt into flake-parts.
      # Keep the option-dependent condition inside config so collecting the
      # module's option declarations does not depend on the option schema.
      config =
        if !(inputs ? devenv) || !(options ? devenv && options.devenv ? modules)
        then {}
        else if !(lib.hasAttrByPath ["devenv" "packages" system "devenv-tasks"] inputs)
        then lib.warn "agentic: consumer devenv lacks packages.${system}.devenv-tasks; skipping the non-IFD task.package default" {}
        else {
          # Use the consumer's input, not an agentic pin: the task runner must
          # match the version of devenv's modules evaluating the consumer shells.
          # devenv.modules is the flake-parts hook applied to EVERY shell, even
          # shells which do not import flake.modules.devenv.agentic themselves.
          devenv.modules = [
            {task.package = lib.mkDefault inputs.devenv.packages.${system}.devenv-tasks;}
          ];
        };
    };
  };
}
