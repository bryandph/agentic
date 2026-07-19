# Fixture check for forge instance templating (task 2.3): one public
# GitHub instance and one private Gitea instance coexist, each expanding
# to a distinct registry entry with its own endpoint and credential.
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
    fixture = inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [system];
      imports = [
        config.flake.flakeModules.default
        ({config, ...}: {
          agentic.forges = {
            github = {
              kind = "github";
              secret = {
                path = "fixture/github";
                field = "token";
              };
            };
            private-forge = {
              kind = "gitea";
              endpoint = "https://forge.fixture.example";
              secret = {
                path = "fixture/forge";
                field = "token";
              };
            };
          };

          flake.agenticProbe = {
            servers = config.agentic.mcp.servers;
            userTier = builtins.attrNames (config.agentic.mcp.lib.serversForTier "user");
          };
        })
      ];
    };

    p = fixture.agenticProbe;
  in {
    # Serena is supplied by the core memory-plane module in both tiers.
    checks.forges = assert p.userTier == ["github" "private-forge" "serena"];
    assert p.servers.private-forge.env.GITEA_HOST == "https://forge.fixture.example";
    assert p.servers.private-forge.secrets ? GITEA_ACCESS_TOKEN;
    assert p.servers.private-forge.secrets.GITEA_ACCESS_TOKEN.env == "GITEA_ACCESS_TOKEN";
    assert p.servers.private-forge.secrets.GITEA_ACCESS_TOKEN.path == "fixture/forge";
    assert p.servers.github.secrets ? GITHUB_PERSONAL_ACCESS_TOKEN;
    assert !(p.servers.github.env ? GITHUB_HOST);
      pkgs.runCommand "agentic-forges" {} "touch $out";
  };
}
