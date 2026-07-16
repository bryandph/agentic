# Serena — the knowledge/memory holder (design D11), pinned via the
# mcp-servers-nix package so the tool holding project memories is locked
# through the consumer's flake.lock (never `nix run` against an
# untracked branch).
#
# Two deployment shapes (agentic-mcp-registry spec / D11):
#
#   * `memory-only` — a rendered custom context whose `fixed_tools` is
#     exactly the memory tool set: no language servers, no symbolic
#     tools, no LS startup tax. For harnesses with native LSP (Claude
#     Code) or repos that only need the knowledge plane.
#   * `full` — full symbolic tooling under a built-in context. The
#     default where the harness lacks native LSP (Codex, Pi).
#
# Both shapes are wrapper scripts: the wrapper pins `--project "$(pwd)"`
# (expanded by the wrapper's own shell, not the MCP client) and blanks
# PYTHONPATH — serena ships its own python env; inheriting a devshell
# PYTHONPATH makes serena's python load foreign-ABI native modules
# (pydantic_core), which is exactly the failure documented in nixspace's
# devenv.nix. The isolation lives in the wrapper so every harness gets
# it regardless of how the entry is delivered.
{
  lib,
  config,
  agenticInputs,
  ...
}: let
  cfg = config.agentic.serena;

  memoryTools = [
    "list_memories"
    "read_memory"
    "write_memory"
    "delete_memory"
    "edit_memory"
    "rename_memory"
  ];

  serenaPackage = pkgs: (import agenticInputs.mcpServersSrc {inherit pkgs;}).packages.serena;

  memoryContextFile = pkgs:
    pkgs.writers.writeYAML "serena-memory-only-context.yml" {
      description = "Memory-plane-only context: knowledge access without language servers.";
      prompt = "You are operating on this project's knowledge memories only; use the memory tools.";
      single_project = true;
      fixed_tools = memoryTools;
    };

  wrapperFor = pkgs: shape: let
    contextArg =
      if shape == "memory-only"
      then "${memoryContextFile pkgs}"
      else cfg.fullContext;
    extraPath = lib.makeBinPath (map (f: f pkgs) cfg.languageServers);
  in
    pkgs.writeScriptBin "serena-${shape}" ''
      #!${pkgs.runtimeShell}
      # PYTHONPATH isolation: serena's own python env only.
      export PYTHONPATH=""
      ${lib.optionalString (shape == "full" && cfg.languageServers != []) ''export PATH="${extraPath}:$PATH"''}
      exec ${serenaPackage pkgs}/bin/serena start-mcp-server \
        --context ${contextArg} \
        --project "$(pwd)" \
        --enable-web-dashboard false "$@"
    '';
in {
  options.agentic.serena = {
    shape = lib.mkOption {
      type = lib.types.enum ["memory-only" "full"];
      default = "full";
      description = ''
        Deployment shape of the Serena registry entry.
        `memory-only`: fixed_tools restricted to the memory tool set,
        no language servers. `full`: symbolic tooling — the default
        where the harness lacks native LSP (Codex, Pi).
      '';
    };

    fullContext = lib.mkOption {
      type = lib.types.str;
      default = "claude-code";
      description = "Built-in serena context for the full shape (the claude-code context strips tools Claude Code natively duplicates).";
    };

    languageServers = lib.mkOption {
      type = lib.types.listOf (lib.types.functionTo lib.types.package);
      default = [];
      example = lib.literalExpression "[(pkgs: pkgs.nixd) (pkgs: pkgs.rust-analyzer)]";
      description = "Package selectors for language servers put on the full-shape wrapper's PATH.";
    };

    lib = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = "Shape helpers for other adapters: `wrapperFor pkgs shape`, `memoryContextFile pkgs`, `memoryTools`.";
    };
  };

  config = {
    agentic.serena.lib = {inherit wrapperFor memoryContextFile memoryTools serenaPackage;};

    agentic.mcp.servers.serena = {
      tiers = ["user" "project"];
      command = pkgs: "${wrapperFor pkgs cfg.shape}/bin/serena-${cfg.shape}";
    };
  };
}
