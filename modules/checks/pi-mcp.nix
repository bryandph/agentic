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
    adapter = pkgs.callPackage ../packages/_pi-mcp-adapter {};
    fixtureServer = pkgs.writeShellScript "pi-mcp-fixture-server" ''
      exec ${pkgs.nodejs}/bin/node ${./_fixtures/pi-mcp-stdio.mjs} "$@"
    '';
    registry =
      (lib.evalModules {
        modules = [
          ../registry/_secrets.nix
          ../registry/_mcp.nix
          {
            agentic.mcp.servers = {
              both = {
                tiers = ["user" "project"];
                command = _: "${fixtureServer}";
                args = ["both"];
                secrets.MCP_FIXTURE_TOKEN = {
                  path = "fixture/token";
                  field = "token";
                };
              };
              userOnly = {
                tiers = ["user"];
                command = _: "${fixtureServer}";
                args = ["userOnly"];
              };
              projectOnly = {
                tiers = ["project"];
                command = _: "${fixtureServer}";
                args = ["projectOnly"];
              };
              remote = {
                tiers = ["user" "project"];
                type = "http";
                url = "\${MCP_FIXTURE_URL}";
                headers = {
                  Authorization = "Bearer \${MCP_FIXTURE_TOKEN}";
                  "X-Api-Key" = "\${MCP_FIXTURE_KEY}";
                };
              };
              external.external = true;
            };
          }
        ];
      }).config;
    # Core does not pin HM. Evaluate its real exported module with only the
    # two HM destination options stubbed; upstream bridge/rendering is real.
    hm =
      (lib.evalModules {
        specialArgs = {inherit pkgs;};
        modules = [
          config.flake.homeModules.default
          ({lib, ...}: {
            options.home.file = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = {};
            };
            options.programs.mcp.servers = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = {};
            };
            config.agentic.mcp.userServers = registry.agentic.mcp.lib.renderTier pkgs "user";
            config.agentic.mcp.sharedUserConfig.enable = true;
          })
        ];
      }).config;
    project =
      ((import "${inputs.mcp-servers-nix}/lib").evalModule pkgs {
        flavor = "claude-code";
        settings.servers = registry.agentic.mcp.lib.renderTier pkgs "project";
      }).config.configFile;
    user = pkgs.writeText "pi-shared-user-mcp.json" hm.home.file.".config/mcp/mcp.json".text;
    runtimeExtension = pkgs.writeText "pi-mcp-runtime.ts" (
      lib.replaceStrings ["@adapter@" "@user@" "@project@"] ["${adapter}" "${user}" "${project}"]
      (builtins.readFile ./_fixtures/pi-mcp-runtime.ts)
    );
    runner = pkgs.writeText "pi-mcp-runtime-runner.py" (
      lib.replaceStrings ["@adapter@" "@extension@" "@user@" "@project@"]
      ["${adapter}" "${runtimeExtension}" "${user}" "${project}"]
      (builtins.readFile ./_fixtures/pi-mcp-runtime-runner.py)
    );
  in {
    checks.pi-mcp = pkgs.runCommand "pi-mcp-config-parity" {nativeBuildInputs = [pkgs.nodejs];} ''
      export HOME="$TMPDIR/home"
      export PI_CODING_AGENT_DIR="$HOME/.pi/agent"
      mkdir -p "$HOME/.config/mcp" "$PI_CODING_AGENT_DIR" "$TMPDIR/project"
      cp ${user} "$HOME/.config/mcp/mcp.json"
      cp ${project} "$TMPDIR/project/.mcp.json"
      cd "$TMPDIR/project"
      node ${pkgs.writeText "pi-mcp-config.mjs" (lib.replaceStrings ["@adapter@"] ["${adapter}"] (builtins.readFile ./_fixtures/pi-mcp-config.mjs))}
      touch "$out"
    '';
    # The consuming environment owns the Pi executable/version. This app tests
    # that actual host (including bundled peers), without another Pi pin here.
    apps.pi-mcp-runtime-check.program = pkgs.writeShellApplication {
      name = "pi-mcp-runtime-check";
      runtimeInputs = [pkgs.python3 pkgs.nodejs];
      text = ''
        if [ "$#" != 1 ]; then
          echo 'usage: pi-mcp-runtime-check /absolute/path/to/pi (0.85.1+)'
          exit 2
        fi
        exec python ${runner} "$1"
      '';
    };
  };
}
