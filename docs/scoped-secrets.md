# Scoped runtime credentials

Flake-parts consumers can use the standalone SecretSpec CLI. This does not
enable devenv's native SecretSpec integration or require a native devenv shell.

Set `agentic.secrets.backend = "secretspec"`, select a SecretSpec package
version >= 0.20 through `agentic.secrets.secretspec.package`, and configure
`agentic.secrets.secretspec.provider` with a credential-free provider URI.
Keep provider authentication in its runtime credential store.

`agentic.secrets.scopes.<name>` maps environment names to the existing
`{ path, field }` references. `asPath = true` delivers a private temporary
file instead of an inline value. The SecretSpec process removes that file
after its child exits. An empty field selects a provider's flat item reference.

`agentic.secrets.lib.mkRunner pkgs { name = "project-secrets"; }` builds a
runner accepting `--scope NAME -- COMMAND [ARG...]`. It generates declarations
only; Nix evaluation and shell entry never resolve these secrets. Missing
required credentials prevent command launch. `SECRETSPEC_REASON` can supply
an access reason when the user's SecretSpec policy requires one.

MCP references and command scopes feed the same generated manifest. Scoped
execution removes declared out-of-scope variables inherited from the caller.
Add retired credential names to `agentic.secrets.managedEnvironment` to scrub
them as well; the shell bootstrap also unsets these legacy variables.
Scopes reduce delivery, not provider authorization: a process with a usable
provider session can still request additional secrets. Child output is not
redacted by SecretSpec.

For HTTP MCP tokens, select `agentic.mcp.httpSecretDelivery = "proxy"` and
provide `agentic.mcp.httpProxyPython`, a Python environment containing the
pinned `mcp-proxy` package. Those servers render as stdio commands. The bridge
expands header references in memory after scoped credential delivery; header
values never become process arguments or client configuration. HTTP servers
without secret references retain native HTTP/client-managed OAuth behavior.

`agentic.mcp.projectServers` optionally selects a subset from the shared
registry for a project shell. It does not create another registry or renderer.

Legacy per-secret CLI backends remain supported. Their wrappers now stop on
a failed lookup or an empty required value rather than starting the target.
