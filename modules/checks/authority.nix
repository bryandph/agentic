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
    # Empty-authority fixture bytes captured from main at 637476d, before
    # standing rules existed; compare every renderer, not only substrings.
    emptyHashes = {
      renderClaude = "491bd2fd351173a6d17ca73f18741863f4fe1d8ffae6371b6bcdf72e615114dc";
      renderCodex = "33da83f9169fa6f408792bfa6fd3f71a6d21515c2a265c4cb13d1a9e84021350";
      renderCotal = "7ed23a93f031edae9912abb2123f1934d90ade77e154a2afdb33686b0ae565a4";
      renderOpencode = "a7ee062a95950e8276e5d5de68a01c0f7a55577440929fa4c5739ff81b25aa29";
      renderPi = "370851c536e78b9491534957bd2a725bb2cf0e385957f036fe5aee4c7d26f66b";
    };
    standingRule = {
      id = "local-checks";
      rule = "Merge this repository after its local checks pass.";
      source = "decision:local-checks BPH-11";
      grantedBy = "human:fixture";
      grantedAt = "2026-11-15T08:00:00Z";
    };
    standingAuthority = authority // {standing = [standingRule];};
    standingLine = "Standing rules (apply without asking, only exactly as written): ${standingRule.rule} (${standingRule.id})";
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
    assert lib.all (renderer: let
      output = render standingAuthority "seat" renderer;
    in
      lib.hasInfix standingLine output && lib.hasInfix autonomousLine output && lib.hasInfix contactLine output)
    renderers;
    assert lib.all (fails {standing = [standingRule standingRule];}) renderers;
    assert lib.all (entry: let
      probe = (fixture {standing = [entry];} null).authorityProbe;
    in
      !(builtins.tryEval (builtins.deepSeq probe.agents.worker.authority.standing true)).success)
    [
      (standingRule // {id = "Bad ID";})
      (standingRule // {grantedAt = "2026-11-15";})
      (standingRule // {grantedAt = "2026-02-29T00:00:00Z";})
      (standingRule // {grantedAt = "2026-04-31T00:00:00Z";})
    ];
    assert lib.all (date: !(fails {standing = [(standingRule // {grantedAt = date;})];} "renderClaude"))
    ["2024-02-29T00:00:00Z" "2026-11-15t08:00:00.123+05:30" "2026-12-31T23:59:60z"];
    assert lib.hasInfix autonomousLine (body null);
    assert lib.hasInfix operatorLine (body null);
    assert lib.all (renderer: lib.hasInfix operatorLine (render authority null renderer)) renderers;
    assert !(lib.hasInfix "##" (render authority "seat" "renderCotal"));
    assert lib.all (renderer: builtins.hashString "sha256" (render {} null renderer) == emptyHashes.${renderer}) renderers;
    # Defaults add no text, including no blank lines (downstream byte-identity
    # comparisons also exercise existing definitions with the field omitted).
    assert lib.all (renderer: let
      empty = render {} null renderer;
    in
      empty
      == render {
        autonomous = [];
        decision = [];
        standing = [];
      }
      null
      renderer
      && !(lib.hasInfix "You may do these" empty)
      && !(lib.hasInfix "as decisions:" empty)
      && !(lib.hasInfix "Standing rules" empty))
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
