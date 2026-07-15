# Knowledge semantic search (design D11, agentic-agents spec "Knowledge
# memory plane"): qmd over the committed knowledge markdown. Serena's
# retrieval is name-based by design; qmd fills the concept-query gap
# with hybrid BM25/vector/rerank over local models. The index is
# disposable and lives OUTSIDE the repo (qmd's user cache) — nothing to
# commit, nothing to drift.
#
# Collections are declared per consumer: a per-repo collection over the
# repo's committed knowledge markdown (the serena memory namespace) and
# an org collection over the shared fragment source supplied by the env
# layer. The wrapper (re)registers declared collections idempotently
# before serving, so MCP and CLI callers see the same corpus.
#
# Pi coverage: the same wrapper is the CLI equivalent (`qmd-knowledge
# search …`) — declared on the registry entry per agentic-mcp-registry's
# harness-coverage requirement.
{
  lib,
  config,
  agenticInputs,
  ...
}: let
  cfg = config.agentic.knowledgeSearch;

  # On darwin the sandboxed node-gyp rebuild (better-sqlite3) fails
  # with "No Xcode or CLT version detected" — upstream builds with CLT
  # receipts visible. xcbuild's xcodebuild shim satisfies gyp's probe.
  qmdPackage = pkgs: let
    base = agenticInputs.qmdBase pkgs;
  in
    if pkgs.stdenv.hostPlatform.isDarwin
    then
      base.overrideAttrs (o: {
        nativeBuildInputs = (o.nativeBuildInputs or []) ++ [pkgs.xcbuild];
      })
    else base;

  wrapper = pkgs: let
    qmd = "${qmdPackage pkgs}/bin/qmd";
  in
    pkgs.writeScriptBin "qmd-knowledge" ''
      #!${pkgs.runtimeShell}
      # Register declared collections (idempotent — add failures on
      # existing collections are expected), then pass through.
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (
          name: c: "${qmd} collection add ${lib.escapeShellArg c.path} --name ${lib.escapeShellArg name} >/dev/null 2>&1 || true"
        )
        cfg.collections)}
      exec ${qmd} "$@"
    '';
in {
  options.agentic.knowledgeSearch = {
    collections = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.path = lib.mkOption {
          type = lib.types.str;
          description = ''
            Directory of markdown to index. Relative paths resolve
            against the process cwd (the repo root under both the
            shell bootstrap and the MCP server).
          '';
        };
      });
      default = {};
      description = ''
        qmd collections, name -> source. Convention: a per-repo
        collection over the committed knowledge markdown
        (`.serena/memories`) plus an org collection over the shared
        fragment source (env layer).
      '';
    };

    lib = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      description = "Helpers: `wrapper pkgs` (collection-registering qmd passthrough), `package pkgs`.";
    };
  };

  config = {
    agentic.knowledgeSearch.lib = {
      inherit wrapper;
      package = qmdPackage;
    };

    agentic.mcp.servers.knowledge = {
      tiers = ["project"];
      command = pkgs: "${wrapper pkgs}/bin/qmd-knowledge";
      args = ["mcp"];
      cliEquivalent = "qmd-knowledge search '<query>' (hybrid semantic search over the repo + org knowledge collections; qmd-knowledge vsearch/query for vector-only/reranked)";
    };
  };
}
