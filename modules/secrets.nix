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
  flake.modules.flake.agentic = {
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
          type = lib.types.str;
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
      };
    });

    selectedBackend =
      cfg.backends.${cfg.backend}
      or (throw "agentic.secrets.backend \"${cfg.backend}\" is not defined in agentic.secrets.backends (${lib.concatStringsSep ", " (lib.attrNames cfg.backends)})");

    # One `export VAR="$(cli …)"` line per requirement — shared by both
    # delivery shapes so they cannot drift.
    exportLine = ref: ''export ${ref.env}="$(${lib.escapeShellArgs (selectedBackend.secretCommand ref)})"'';
  in {
    options.agentic.secrets = {
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

        wrapServer = pkgs: {
          name,
          bin,
          secrets,
          extraEnv ? {},
        }:
          pkgs.writeScriptBin name ''
            #!${pkgs.runtimeShell}
            ${lib.concatStringsSep "\n" (lib.mapAttrsToList (var: val: "export ${var}=${lib.escapeShellArg val}") extraEnv)}
            ${lib.concatMapStringsSep "\n" exportLine (lib.attrValues secrets)}
            exec ${bin} "$@"
          '';
      };
    };
  };
}
