# devenv-native transport (opt-in)

The flake-parts transport (`devenv.shells.<name>.imports = [<agentic
devenv module>]`) is the primary contract — every capability works
there, indefinitely. The devenv-native transport is an OPT-IN
acceleration for repos that want the per-project eval cache and
in-place evaluation (no flake git discovery — worktree gitdir
indirection never enters the picture).

## Consuming natively

```yaml
# devenv.yaml
inputs:
  agentic:
    url: github:bryandph/agentic/<rev-or-tag>
    flake: false
imports:
  - agentic
```

devenv loads core's `/devenv.nix` shim, which composes the same
transport-neutral registry modules as the exported flakeModule and
wires the same shell module — the artifact set on shell entry
(`.mcp.json`, opencode config, agent dirs, memory plane,
`.workmux.yaml`, secret exports) is identical to flake-parts
consumption. Repo options go in the repo's own `devenv.nix`
(`agentic.*`), exactly as a flake consumer would set them.

Upstream dependencies (mcp-servers-nix, qmd) resolve from core's OWN
committed `flake.lock` via `fetchTree`/`getFlake` — locked and
narHash-pinned, no flake evaluation required.

## Dual-lock discipline (agentic-devenv spec)

A repo using the native transport alongside a flake carries TWO pins of
core: `flake.lock` (via the flake input) and `devenv.yaml`/`devenv.lock`
(via the native input). **`flake.lock` is the authoritative version
statement.** Keep them coherent by either:

- generating the `devenv.yaml` pin from the flake input (write
  `url: github:bryandph/agentic/<rev from flake.lock>` whenever the
  flake input moves), or
- a CI check comparing `devenv.lock`'s agentic rev against
  `flake.lock`'s:

  ```sh
  flake_rev=$(jq -r '.nodes.agentic.locked.rev' flake.lock)
  native_rev=$(jq -r '.nodes.agentic.locked.rev' devenv.lock)
  [ "$flake_rev" = "$native_rev" ] || { echo "core pin drift"; exit 1; }
  ```

No capability exists only on the native transport, so pin drift can
never strand a consumer — it can only make the two transports disagree
about which core they run, which the check above catches.

## Known upstream issue (devenv ≤ 2.1.x)

devenv 2.1.1–2.1.x's input fetcher can fail on public https GitHub
fetches with `authentication required but no callback set`. This is
cachix/devenv#2842 — a regression in devenv's embedded Nix fork's git
fetcher (missing credential callback), introduced between 2.1.0 and
2.1.1 and triggered by environment-dependent user configuration
(upstream reports name gitconfig url rewrites and ssh configs; in our
reproduction only the full real HOME triggered it — no single config
file did). Fixed by cachix/nix@078bffe (upstreamed as NixOS/nix#15470),
on devenv main, releasing in 2.2.

Workarounds until 2.2 lands in nixpkgs: run the fixed build
(`nix run github:cachix/devenv/main -- shell …`) or invoke devenv under
an isolated HOME.
