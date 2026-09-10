# A test-only HM pin exercises its real MCP writer, XDG conversion and file
# assertions. Consumers still own their Home Manager version; no production
# input or HM module is pinned/imported by core delivery.
{
  pkgs,
  coreModule,
  userServers,
}: let
  inherit (pkgs) lib;
  hmSource = builtins.fetchTree {
    type = "github";
    owner = "nix-community";
    repo = "home-manager";
    rev = "65258d5c65a250189fde2e35f490d15e064c4c62";
    narHash = "sha256-Sxu1NLTD/Ern6hFGLlZmtKCSct3YQXZI/lls8RE1XeM=";
  };
  homeDirectory = "/home/fixture";
  evaluate = extra:
    (import "${hmSource}/lib" {inherit lib;}).homeManagerConfiguration {
      inherit pkgs;
      modules = [
        coreModule
        {
          home = {
            username = "fixture";
            inherit homeDirectory;
            stateVersion = "26.05";
          };
          xdg.enable = true;
          programs.mcp.enable = true;
          agentic.mcp = {
            inherit userServers;
            sharedUserConfig.enable = true;
          };
        }
        extra
      ];
    };
  normal = evaluate {};
  custom = evaluate {xdg.configHome = "${homeDirectory}/custom-config";};
  retargeted = evaluate {
    xdg.configHome = "${homeDirectory}/custom-config";
    xdg.configFile."mcp/mcp.json".target = "${homeDirectory}/.config/mcp/mcp.json";
  };
  disabled = evaluate {programs.mcp.enable = lib.mkForce false;};
  fileDisabled = evaluate {xdg.configFile."mcp/mcp.json".enable = false;};
  empty = evaluate {agentic.mcp.userServers = lib.mkForce {};};
  optedOut = evaluate {agentic.mcp.sharedUserConfig.enable = lib.mkForce false;};
  files = hm: lib.filter (file: file.enable) (lib.attrValues hm.config.home.file);
  shared = hm: lib.filter (file: file.target == ".config/mcp/mcp.json") (files hm);
  unique = hm: let
    targets = map (file: file.target) (files hm);
  in
    builtins.length targets == builtins.length (lib.unique targets);
  scenarios = [normal custom retargeted disabled fileDisabled empty optedOut];
  valid =
    builtins.all (
      hm:
        builtins.all (item: item.assertion) hm.config.assertions
        && unique hm
        && builtins.length (shared hm) == 1
    )
    scenarios;
  source = hm: (builtins.head (shared hm)).source;
in
  assert valid;
  assert !(normal.config.home.file ? ".config/mcp/mcp.json");
  assert !(retargeted.config.home.file ? ".config/mcp/mcp.json");
  assert !(optedOut.config.home.file ? ".config/mcp/mcp.json");
  assert custom.config.home.file ? ".config/mcp/mcp.json";
  assert source custom == custom.config.xdg.configFile."mcp/mcp.json".source;
  assert source normal == source custom;
  assert source normal == source disabled;
  assert source normal == source fileDisabled; {
    user = source normal;
    inherit valid;
    # Building home-files also exercises HM's target-collision check, beyond
    # evaluating assertions and final flattened target uniqueness above.
    homeFiles = map (hm: hm.config.home-files) scenarios;
    emptyUser = source empty;
  }
