{
  inputs,
  config,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    lib,
    ...
  }: let
    fixture = extra:
      (inputs.flake-parts.lib.mkFlake {inherit inputs;} {
        systems = [system];
        imports = [config.flake.flakeModules.default extra ({config, ...}: {flake.lib.fixture = config.agentic.worktreeLib // {declarations = config.agentic.worktree.services;};})];
      }).lib.fixture;
    common = {
      agentic.worktree = {
        shell.kind = "none";
        services.database = {
          probe.run = ''python3 -c 'import os,socket; socket.create_connection(("127.0.0.1",int(os.environ["TEST_PORT"])),timeout=.2).close()' '';
          start = ''python3 "$TEST_LISTENER" "$TEST_PORT"'';
          startTimeout = 2;
          env.DATABASE_URL = "postgresql://localhost/fixture";
        };
        setupHooks = [
          {
            name = "database";
            needs = ["database"];
            run = ''printf '%s' "$DATABASE_URL" > hook-env'';
          }
          {
            name = "again";
            needs = ["database"];
            run = "true";
          }
        ];
      };
    };
    normal = fixture common;
    attachOnly = fixture {
      imports = [common];
      agentic.worktree.services.database.autostart = false;
    };
    invalidProbe = probe:
      !(builtins.tryEval (builtins.deepSeq
        (fixture {
          agentic.worktree.services.invalid = {inherit probe;};
        }).declarations
        true)).success;
    schemaChecks =
      invalidProbe {}
      && invalidProbe {
        tcp = "localhost:1";
        run = "true";
      }
      && normal.declarations.database.process == "database"
      && normal.declarations.database.autostart;
  in {
    checks.worktree-services = assert schemaChecks;
      pkgs.runCommand "worktree-services" {
        nativeBuildInputs = [pkgs.python3 pkgs.git pkgs.bash];
      } ''
        python3 ${./_worktree-services.py} \
          ${normal.setupScript pkgs}/bin/workbench-worktree-setup \
          ${attachOnly.setupScript pkgs}/bin/workbench-worktree-setup \
          ${normal.teardownScript pkgs}/bin/workbench-worktree-teardown \
          ${normal.servicesScript pkgs}/bin/workbench-services \
          ${../registry/_worktree-services.py} > "$out"
      '';
  };
}
