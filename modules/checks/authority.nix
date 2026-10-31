# Authority is instruction data, shared by every renderer, not a runtime grant.
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
    inherit (pkgs) lib;
    fixture = authority: escalateTo:
      inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [
          config.flake.flakeModules.default
          ({config, ...}: {
            agentic.agents = {
              worker = {
                description = "Authority fixture.";
                inherit authority;
                platforms = ["claude" "codex" "opencode" "pi" "cotal"];
                cotal = {
                  role = "worker";
                  inherit escalateTo;
                };
              };
              seat = {
                description = "Decision contact.";
                platforms = ["cotal"];
                cotal.role = "coordinator";
              };
            };
            flake.authorityProbe = {
              inherit (config.agentic) agents agentsLib;
            };
          })
        ];
      };
    render = authority: target: renderer: let
      probe = (fixture authority target).authorityProbe;
    in
      probe.agentsLib.${renderer} "worker" probe.agents.worker;
    renderers = ["renderCotal" "renderClaude" "renderCodex" "renderOpencode" "renderPi"];
    fails = authority: renderer:
      !(builtins.tryEval (builtins.deepSeq (render authority null renderer) true)).success;
    authority = {
      autonomous = ["merge-own-repo" "push-own-branch"];
      decision = ["deploy-manual" "cluster-out-of-git" "secrets" "delete-remote" "cross-repo" "set-work-status-final"];
    };
    autonomousLine = "You may do these without asking: merge and push your own repository's branches; push your own working branch.";
    decisions = "deploy manually; change the cluster outside git; access or change secrets; delete or archive remote repositories; work across repositories; set final work-item statuses.";
    operatorLine = "These go to the operator as decisions: ${decisions}";
    contactLine = "These go to the peer with Cotal role `coordinator` (find that peer on the roster by role) as decisions: ${decisions}";
    body = target: let
      probe = (fixture authority target).authorityProbe;
    in
      probe.agentsLib.compileBody "worker" probe.agents.worker;
  in {
    checks.agents-authority = assert lib.all (renderer: let
      output = render authority "seat" renderer;
    in
      lib.hasInfix autonomousLine output && lib.hasInfix contactLine output)
    renderers;
    assert lib.hasInfix autonomousLine (body null);
    assert lib.hasInfix operatorLine (body null);
    assert lib.all (renderer: lib.hasInfix operatorLine (render authority null renderer)) renderers;
    assert !(lib.hasInfix "##" (render authority "seat" "renderCotal"));
    # Defaults add no text, including no blank lines (downstream byte-identity
    # comparisons also exercise existing definitions with the field omitted).
    assert lib.all (renderer: let
      empty = render {} null renderer;
    in
      empty
      == render {
        autonomous = [];
        decision = [];
      }
      null
      renderer
      && !(lib.hasInfix "You may do these" empty)
      && !(lib.hasInfix "as decisions:" empty))
    renderers;
    # Force every renderer, not just the option values: this catches bypasses
    # of validateAgent in either the shared compiler or the Cotal body.
    assert lib.all (fails {
      autonomous = ["secrets"];
      decision = ["secrets"];
    })
    renderers;
    assert lib.all (list: lib.all (fails {${list} = ["secrets" "secrets"];}) renderers) ["autonomous" "decision"];
    # Probe the option itself so failure proves enum validation, not a missing
    # prose lookup. Check both lists independently.
    assert lib.all (list: let
      probe = (fixture {${list} = ["unknown-action"];} null).authorityProbe;
    in
      !(builtins.tryEval (builtins.deepSeq probe.agents.worker.authority.${list} true)).success)
    ["autonomous" "decision"];
      pkgs.runCommand "agentic-agents-authority" {} ''
        touch "$out"
      '';
  };
}
