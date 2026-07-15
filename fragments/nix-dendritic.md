Nix code in this ecosystem follows the **dendritic pattern** on
flake-parts: every `.nix` file under `modules/` is a flake-parts module,
auto-imported by import-tree (paths containing `/_` are skipped),
organized by feature rather than by mechanism.

Rules that matter:

- Each file is exactly ONE kind: **infrastructure** (options/factories/
  third-party flakeModule imports), **feature** (`flake.modules.<class>.
  <name> = {…}` — one concern across every class it touches, in one
  file), or **configuration** (`configurations.<class>.<name>` — pure
  composition of feature imports). If a file mixes kinds, split it.
- No `<name>.enable` gates on your own features — composition is by
  `imports`. (Setting upstream options like `services.openssh.enable`
  is fine; that's configuring a downstream module.)
- No `specialArgs` pass-thru — declare a top-level option and read
  `config.*` instead.
- Names are role-based (`ssh`, `zfs-root`, `desktop`), never per-host.
- Overlays co-locate with the feature that needs them; no global
  overlays directory.
- Aggressive `inputs.<x>.follows` deduplication on every flake input;
  multi-level chains are intentional — never "simplify" them away.
- Format via `nix fmt` (treefmt → alejandra); never add a second Nix
  formatter or shell out to a formatter directly.
- New files must be `git add`-ed before any flake evaluation can see
  them.

Deeper sources: https://github.com/mightyiam/dendritic (pattern),
https://github.com/vic/import-tree, https://flake.parts/options/flake-parts-modules.html.
