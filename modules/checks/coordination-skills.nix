# Opt-in coordination skills: canonical Claude bodies and Agent Skills wrappers,
# no legacy creator instructions, and no hook-bypass instructions.
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
    fixture = enabled:
      inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [
          config.flake.flakeModules.default
          ({config, ...}: {
            agentic.skills = {
              coordination = lib.mkIf (enabled != null) {enable = enabled;};
              driftCheck = false;
            };
            flake.skillsProbe = config.agentic.skills.lib.renderedFiles;
          })
        ];
      };
    enabled = fixture true;
    disabled = fixture false;
    default = fixture null;
    names = ["merge" "rebase" "worktree"];
    paths =
      lib.concatMap (name: [
        ".agents/skills/${name}/SKILL.md"
        ".claude/skills/${name}/SKILL.md"
      ])
      names;
    prohibition = "Never use `--no-verify` or any other hook or check bypass.";
    safeBody = body:
      lib.hasInfix prohibition body
      && !(lib.hasInfix "--no-verify" (lib.replaceStrings [prohibition] [""] body))
      && !(lib.hasInfix "workmux" (lib.toLower body));
    canonical = name: builtins.readFile (../../skills + "/${name}/SKILL.md");
  in {
    checks.coordination-skills = assert builtins.attrNames enabled.skillsProbe == lib.sort builtins.lessThan paths;
    assert disabled.skillsProbe == {};
    assert default.skillsProbe == {};
    assert !(disabled.apps.${system} ? write-agent-skills);
    assert lib.all (name: let
      body = enabled.skillsProbe.".claude/skills/${name}/SKILL.md";
      wrapper = enabled.skillsProbe.".agents/skills/${name}/SKILL.md";
    in
      body
      == canonical name
      && lib.hasPrefix "---\nname: ${name}\ndescription:" body
      && safeBody body
      && !(lib.hasInfix "workmux" (lib.toLower wrapper))
      && !(lib.hasInfix "--no-verify" wrapper)
      && lib.hasInfix "../../../.claude/skills/${name}/SKILL.md" wrapper)
    names;
    # Guard the guard: a prohibition elsewhere cannot excuse an instruction.
    assert !(safeBody "Use --no-verify.");
    assert !(safeBody (prohibition + "\nUse --no-verify."));
    assert !(safeBody (prohibition + "\nUse workmux."));
      pkgs.runCommand "agentic-coordination-skills" {} ''
        set -euo pipefail
        cd "$TMPDIR"
        ${enabled.apps.${system}.write-agent-skills.program}
        ${lib.concatMapStringsSep "\n" (name: ''
            cmp .claude/skills/${name}/SKILL.md ${../../skills}/${name}/SKILL.md
            test -f .agents/skills/${name}/SKILL.md
          '')
          names}
        touch $out
      '';
  };
}
