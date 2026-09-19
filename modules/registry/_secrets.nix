# CLI secret backend abstraction (design D4, agentic-mcp-registry spec).
#
# Every secret is sourced at runtime by invoking a CLI — never stored in
# rendered artifacts or the nix store. A backend is DATA: a package
# selector plus a command template (`secretCommand : ref -> argv`), so a
# new secret manager is a preset supplied through options, not a core
# change. Core wires `vault` (OpenBao-compatible; parameterized
# address/mount — generalizing the wrapWithVault pattern this replaces)
# and `env` (degenerate passthrough for environments without a CLI
# manager).
#
# Two delivery shapes, both derived from the same backend:
#   * stdio servers — `wrapServer` produces a binary that exports each
#     secret from the CLI before exec'ing the real server binary.
#   * http servers — configs cannot wrap a binary; they reference
#     `''${VAR}` expanded client-side, and `exportsScript` emits the
#     shell lines the bootstrap runs to export those vars from the same
#     backend.
{
  lib,
  config,
  ...
}: let
  cfg = config.agentic.secrets;

  # A secret requirement: the env var the consumer will read, plus the
  # backend-interpreted location. `path`/`field` are the conventional
  # location vocabulary (vault: kv path + field; 1password-style CLIs
  # map them into their own URI shapes; `env` ignores them entirely).
  refType = lib.types.submodule ({name, ...}: {
    options = {
      env = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z_][A-Za-z0-9_]*";
        default = name;
        description = "Environment variable the secret is delivered as (defaults to the attr name).";
      };
      path = lib.mkOption {
        type = lib.types.str;
        description = "Backend-specific secret path (e.g. the vault kv path).";
      };
      field = lib.mkOption {
        type = lib.types.str;
        description = "Field within the secret at `path`.";
      };
      asPath = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Deliver this value through a private temporary file managed by SecretSpec.";
      };
    };
  });

  selectedBackend =
    cfg.backends.${cfg.backend}
      or (throw "agentic.secrets.backend \"${cfg.backend}\" is not defined in agentic.secrets.backends (${lib.concatStringsSep ", " (lib.attrNames cfg.backends)})");

  # One `export VAR="$(cli …)"` line per requirement — shared by both
  # delivery shapes so they cannot drift.
  exportLine = ref: ''
    ${ref.env}="$(${lib.escapeShellArgs (selectedBackend.secretCommand ref)})" || exit 1
    [ -n "$${ref.env}" ] || { echo "Missing required credential: ${ref.env}" >&2; exit 1; }
    export ${ref.env}
  '';
in {
  options.agentic.secrets = {
    scopes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf refType);
      default = {};
      description = "Named per-command credential requirements; values are resolved only at execution.";
    };
    managedEnvironment = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[A-Za-z_][A-Za-z0-9_]*");
      default = [];
      description = "Additional legacy credential variable names to exclude from scoped child environments.";
    };
    secretspec = {
      package = lib.mkOption {
        type = lib.types.functionTo lib.types.package;
        default = pkgs: pkgs.secretspec;
        description = "SecretSpec package (0.20 or newer).";
      };
      provider = lib.mkOption {
        type = lib.types.str;
        default = "env";
        description = "Provider URI; contains only routing information, never authentication bytes.";
      };
    };
    backend = lib.mkOption {
      type = lib.types.str;
      default = "env";
      description = "Selected secret backend: a key of `agentic.secrets.backends`.";
    };

    backends = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          package = lib.mkOption {
            type = lib.types.nullOr (lib.types.functionTo lib.types.package);
            default = null;
            description = ''
              Package selector (`pkgs: pkgs.<cli>`) providing the backend
              CLI, or null when the CLI is expected on PATH / no CLI is
              needed. A selector function (not a package) so one
              flake-level definition serves every system.
            '';
          };
          secretCommand = lib.mkOption {
            type = lib.types.functionTo (lib.types.listOf lib.types.str);
            description = ''
              Command template: a function from a secret ref
              (`{ env, path, field }`) to the argv that prints the
              secret value on stdout.
            '';
          };
        };
      });
      default = {};
      description = ''
        Available secret backends, as data. Adding a secret manager
        means adding a preset here (e.g. a 1password backend is
        `secretCommand = ref: ["op" "read" "op://vault/''${ref.path}/''${ref.field}"]`)
        — never a core change.
      '';
    };

    vault = {
      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Vault/OpenBao address for the `vault` backend, or null to use
          the ambient VAULT_ADDR.
        '';
      };
      mount = lib.mkOption {
        type = lib.types.str;
        default = "secret";
        description = "KV mount the `vault` backend reads from.";
      };
    };

    refType = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      internal = true;
      description = "The secret-requirement submodule type, for reuse by the server registry.";
    };

    lib = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = ''
        Delivery helpers derived from the selected backend:
        `secretCommand` (ref -> argv), `exportsScript` (refs -> shell
        text exporting each var), and `wrapServer` (pkgs -> { name,
        bin, secrets, extraEnv ? {} } -> drv) wrapping a stdio server
        binary so it resolves its secrets at startup.
      '';
    };
  };

  config.agentic.secrets = {
    backends = {
      secretspec = {
        package = cfg.secretspec.package;
        secretCommand = _: throw "SecretSpec uses scoped command execution; use mkRunner or wrapServer instead of secretCommand.";
      };
      # OpenBao/Vault kv — the wired backend. Address/mount are options
      # so no environment identity lands in core.
      vault = {
        package = pkgs: pkgs.openbao;
        secretCommand = ref:
          lib.optionals (cfg.vault.address != null) ["env" "VAULT_ADDR=${cfg.vault.address}"]
          ++ ["vault" "kv" "get" "-mount=${cfg.vault.mount}" "-field=${ref.field}" ref.path];
      };

      # Degenerate passthrough: the secret is expected in the ambient
      # environment already; re-export keeps both delivery shapes
      # uniform without a CLI manager.
      env = {
        secretCommand = ref: ["printenv" ref.env];
      };
    };

    inherit refType;

    lib = {
      inherit (selectedBackend) secretCommand;

      exportsScript = refs: lib.concatMapStringsSep "\n" exportLine (lib.attrValues refs);

      # One manifest carries all known names so --scope also removes stale
      # credentials inherited from an older shell. No provider is queried by Nix.
      mkRunner = pkgs: {
        name,
        scopes ? cfg.scopes,
      }: let
        allScopes =
          (lib.attrValues cfg.scopes)
          ++ (lib.mapAttrsToList (_: server: server.secrets) config.agentic.mcp.servers)
          ++ (lib.attrValues scopes);
        refs = lib.foldl' (acc: scope:
          lib.foldlAttrs (acc: key: ref: let
            env = ref.env or key;
          in
            if acc ? ${env} && acc.${env} != ref
            then throw "Conflicting secret references for ${env}"
            else acc // {${env} = ref;})
          acc
          scope) {}
        allScopes;
        manifest = (pkgs.formats.toml {}).generate "${name}-secretspec.toml" {
          project = {
            name =
              if config.agentic.memoryPlane.projectName == null
              then "agentic"
              else config.agentic.memoryPlane.projectName;
            revision = "1.0";
          };
          profiles.default =
            (lib.genAttrs cfg.managedEnvironment (_: {
              description = "Legacy credential excluded from unselected scopes";
              required = false;
            }))
            // lib.mapAttrs (env: ref: {
              description = "Runtime credential ${env}";
              required = true;
              ref = {item = ref.path;} // lib.optionalAttrs (ref.field != "") {inherit (ref) field;};
              as_path = ref.asPath or false;
            })
            refs;
          scopes = lib.mapAttrs (_: scope: {
            secrets = lib.mapAttrsToList (key: ref: ref.env or key) scope;
          }) (lib.filterAttrs (_: scope: scope != {}) scopes);
        };
        package = cfg.secretspec.package pkgs;
      in
        assert lib.assertMsg (lib.any (scope: scope != {}) (lib.attrValues scopes)) "Scoped runner requires at least one nonempty scope";
        assert lib.assertMsg (lib.versionAtLeast package.version "0.20") "Scoped delivery requires SecretSpec >= 0.20";
          pkgs.writeShellScriptBin name ''
            set -euo pipefail
            if [ "$#" -lt 4 ] || [ "$1" != --scope ] || [ "$3" != -- ]; then
              echo "usage: ${name} --scope NAME -- COMMAND [ARG...]" >&2
              exit 2
            fi
            scope="$2"
            shift 3
            case "$scope" in
              ${lib.concatMapStringsSep "|" lib.escapeShellArg (lib.attrNames (lib.filterAttrs (_: scope: scope != {}) scopes))}) ;;
              *) echo "${name}: unknown credential scope" >&2; exit 2 ;;
            esac
            exec ${lib.getExe package} --file ${manifest} run \
              --provider ${lib.escapeShellArg cfg.secretspec.provider} --profile default \
              --reason "''${SECRETSPEC_REASON:-Start ${name} for the agentic environment}" \
              --scope "$scope" -- "$@"
          '';

      wrapServer = pkgs: {
        name,
        bin,
        secrets,
        extraEnv ? {},
      }:
        if cfg.backend == "secretspec"
        then let
          runner = cfg.lib.mkRunner pkgs {
            name = "${name}-secrets";
            scopes.${name} = secrets;
          };
        in
          pkgs.writeShellScriptBin name ''
            set -euo pipefail
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (var: val: "export ${var}=${lib.escapeShellArg val}") extraEnv)}
            exec ${runner}/bin/${name}-secrets --scope ${lib.escapeShellArg name} -- ${bin} "$@"
          ''
        else
          pkgs.writeScriptBin name ''
            #!${pkgs.runtimeShell}
            set -eu
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (var: val: "export ${var}=${lib.escapeShellArg val}") extraEnv)}
            ${lib.concatMapStringsSep "\n" exportLine (lib.attrValues secrets)}
            exec ${bin} "$@"
          '';
    };
  };
}
