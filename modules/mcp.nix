# The MCP server registry (design D4, agentic-mcp-registry spec).
#
# Exactly ONE definition per server, carrying its tier membership
# (`user` — home-manager plane; `project` — per-repo `.mcp.json` /
# opencode config); a server lives in both tiers without duplicating its
# definition. Delivery adapters (see modules/adapters/) feed this set
# into the upstream registries — core maps schema, it does not render
# file formats.
#
# Secret requirements reuse the backend abstraction from
# modules/secrets.nix: stdio servers get their binaries wrapped, http
# servers get client-side `''${VAR}` header expansion with the variable
# exported by the shell bootstrap from the same backend.
{
  flake.modules.flake.agentic = {
    lib,
    config,
    ...
  }: let
    cfg = config.agentic.mcp;
    secretsLib = config.agentic.secrets.lib;

    serverType = lib.types.submodule ({name, ...}: {
      options = {
        tiers = lib.mkOption {
          type = lib.types.listOf (lib.types.enum ["user" "project"]);
          default = ["project"];
          description = ''
            Delivery tiers this server belongs to. `user` renders into
            the home-manager plane; `project` into per-repo artifacts
            (`.mcp.json`, opencode config). One definition may carry
            both.
          '';
        };

        type = lib.mkOption {
          type = lib.types.enum ["stdio" "http"];
          default = "stdio";
          description = "Transport: a wrapped local process (stdio) or a remote endpoint (http).";
        };

        command = lib.mkOption {
          type = lib.types.nullOr (lib.types.functionTo lib.types.str);
          default = null;
          description = ''
            stdio only: package selector returning the executable path
            (`pkgs: lib.getExe pkgs.<server>`). A selector function so
            one flake-level definition serves every system, and so the
            server package is pinned by the consumer's flake.lock
            (registry entries MUST NOT invoke unlocked references).
          '';
        };

        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "stdio only: arguments passed to the server command.";
        };

        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "stdio only: plain (non-secret) environment for the server process.";
        };

        url = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "http only: the server endpoint.";
        };

        headers = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = ''
            http only: request headers. Secret-bearing headers reference
            an environment variable (`Bearer ''${TOKEN}`) expanded
            client-side; declare the variable under `secrets` so the
            bootstrap exports it from the secret backend.
          '';
        };

        secrets = lib.mkOption {
          type = lib.types.attrsOf config.agentic.secrets.refType;
          default = {};
          description = ''
            Secret requirements as ENV_VAR -> ref. stdio: exported by
            the wrapper before exec. http: exported by the shell
            bootstrap for client-side header expansion. Values are
            resolved at runtime by the selected backend CLI and never
            land in rendered artifacts or the store.
          '';
        };

        external = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Escape hatch: the server is declared (so agent references
            validate) but delivery is ad-hoc or runtime-only — no
            rendered configuration is produced and agent references to
            it warn instead of failing.
          '';
        };

        _name = lib.mkOption {
          type = lib.types.str;
          default = name;
          internal = true;
          readOnly = true;
        };
      };
    });

    deliverable = lib.filterAttrs (_: s: !s.external) cfg.servers;

    # Canonical rendering (Claude Code schema — the common denominator
    # every adapter maps from). stdio servers with secrets resolve to a
    # wrapped binary; http servers pass headers through untouched.
    render = pkgs: name: def:
      if def.external
      then throw "agentic.mcp.servers.${name} is external — it has no renderable delivery"
      else if def.type == "http"
      then
        {
          type = "http";
          url =
            if def.url != null
            then def.url
            else throw "agentic.mcp.servers.${name}: http server requires `url`";
        }
        // lib.optionalAttrs (def.headers != {}) {inherit (def) headers;}
      else let
        bin =
          if def.command != null
          then def.command pkgs
          else throw "agentic.mcp.servers.${name}: stdio server requires `command`";
        wrapped =
          if def.secrets == {}
          then bin
          else "${secretsLib.wrapServer pkgs {
            name = "${name}-mcp-wrapped";
            inherit bin;
            inherit (def) secrets;
          }}/bin/${name}-mcp-wrapped";
      in
        {
          type = "stdio";
          command = wrapped;
        }
        // lib.optionalAttrs (def.args != []) {inherit (def) args;}
        // lib.optionalAttrs (def.env != {}) {inherit (def) env;};
  in {
    options.agentic.mcp = {
      servers = lib.mkOption {
        type = lib.types.attrsOf serverType;
        default = {};
        description = "The MCP server registry: one definition per server, merged across layers.";
      };

      lib = lib.mkOption {
        type = lib.types.raw;
        readOnly = true;
        description = ''
          Registry helpers for delivery adapters and the agent registry:
          `serversForTier`, `render`, `renderTier`, `httpSecretRefs`,
          `validateAgentRefs`.
        '';
      };
    };

    config.agentic.mcp.lib = {
      inherit render;

      serversForTier = tier: lib.filterAttrs (_: s: lib.elem tier s.tiers) deliverable;

      # Everything an adapter needs for one tier, rendered.
      renderTier = pkgs: tier:
        lib.mapAttrs (render pkgs)
        (lib.filterAttrs (_: s: lib.elem tier s.tiers) deliverable);

      # Secret requirements of http servers (any tier) — the set the
      # shell bootstrap must export for client-side header expansion.
      httpSecretRefs = lib.foldlAttrs (
        acc: _: def:
          acc // def.secrets
      ) {} (lib.filterAttrs (_: s: s.type == "http") deliverable);

      # Eval-time validation of agent-declared MCP requirements: an
      # undefined reference fails naming the agent and the server; a
      # reference to an `external` entry warns (delivery not guaranteed)
      # but passes.
      validateAgentRefs = agentName: refs: let
        missing = lib.filter (r: !(cfg.servers ? ${r})) refs;
        externals = lib.filter (r: (cfg.servers.${r}.external or false)) refs;
      in
        if missing != []
        then
          throw ''
            agentic.agents.${agentName} requires undefined MCP server(s): ${lib.concatStringsSep ", " missing}.
            Define them in agentic.mcp.servers (or mark an ad-hoc server `external = true`).''
        else if externals != []
        then
          lib.warn
          "agentic.agents.${agentName} references external MCP server(s) ${lib.concatStringsSep ", " externals} — delivery is not managed by the registry"
          refs
        else refs;
    };
  };
}
