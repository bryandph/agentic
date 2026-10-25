Tracks BPH-73, the authoritative work item (parent BPH-7). The tracker is private, so this public repository names the item without its URL. The operator decided the review questions on 2026-10-24 (design D2, D5, D6, D7, D9); implementation still needs approval of the change as a whole.

## Why

Independently versioned repositories that are developed together are today held together by submodule chains, so one core change needs a pin bump in every repository between it and the consumer, and workers stall on uninitialised submodules. The workspace milestone in `modules/workspace.nix` replaced part of that with a declared repository list rendered to `mani.yaml` and one shared worktree root. Its schema, though, takes only a raw clone URL and path per repository, offers no way to express forges, mirrors or a path convention, and gives no way to evaluate a consumer against a local, uncommitted checkout. The capability has to work for any forge and any folder layout, with no organisation-specific structure in core.

## What Changes

- New capability `workbench-workspace`, published as `workbench.workspace` with `agentic.workspace` resolving to the same options during the compatibility phase described in README "Consuming".
- Declaration schema: named `remotes` (base URL plus optional mirror aliases, any forge); repositories given as `remote` + `name` or a full `url`; an explicit `path` or one computed by a configurable `defaultPath` function; `groups` for selection. The existing `repos.<name>.{path,url,tags}` entries stay valid, with `tags` read as a deprecated synonym of `groups`.
- A resolved, serialisable form of the declaration that every renderer and helper reads, so manifest formats and tools do not reinterpret the options.
- Renderer boundary: `mani.yaml` is the first backend. Rendering writes only the manifest; it never resets, cleans or moves existing checkouts, and the rendered manifest keeps mani's `worktrees`, `remove_orphaned_worktrees` and `sync_remotes` off. Further manifest formats are later renderers of the same resolved declaration.
- A read-only audit that compares the declaration with the tree on disk and reports differences without changing anything.
- Local flake-input overrides: a helper maps a consumer flake's inputs to existing peer checkouts in the workspace and emits `--override-input` arguments, so an uncommitted core edit reaches a consumer evaluation without a pin bump.
- Home Manager half: `workspace.root` and `worktreeDir` are kept unchanged. Core gains an org-neutral `programs.herdr` module so consumers that import only core get Herdr configuration and the worktree root applies to them.
- A `#workspace` template (allowlist `.gitignore`, `.envrc`, `flake.nix`, an empty declaration) and public README documentation of the instance pattern.
- Fixtures for a non-Gitea remote and for a flat repository list with no organisation or area structure, in addition to the existing ones.

Consumer-facing exports that change: `devenvModules.workspace` and `homeModules.workspace` gain options (additive); a new `homeModules.herdr` export and a `#workspace` template are added; the workspace devenv module gains a `workbench.workspace` alias it does not have today. No existing option or output is removed.

## Capabilities

### New Capabilities

- `workbench-workspace`: declaring a workspace of independently versioned repositories, rendering repository-manager configuration from it, auditing it, deriving local flake-input overrides, and placing worktrees under one root.

### Modified Capabilities

None. The milestone in `modules/workspace.nix` was delivered without a spec; this change specifies and extends it.

## Non-goals

- Forge discovery in core (for example listing an organisation's repositories). A consumer may generate declaration entries with its own tool; core consumes only the declaration.
- Revision pinning in the manifest. `flake.lock` stays the only pin; rendered manifests name no commit, tag or branch to check out.
- Single-tree monorepo tooling (josh, copybara, git-subrepo).
- Moving repositories between forge organisations, creating mirrors, or migrating any consumer's submodules. Those are separate work in the consuming repositories.
- Changing the instance repository. Moving it to the new schema is consumer work tracked on BPH-73.
- Large binary content. Whether the declaration gains a non-git store kind or an LFS flag is undecided and waits on BPH-74; this change leaves room for it but specifies nothing.

## Impact

- Core files: `modules/workspace.nix` (schema, resolved form, renderer, audit and override helpers), `modules/checks/workspace.nix` (fixtures), a new org-neutral Herdr Home Manager module, `modules/exports.nix`, `modules/templates.nix`, `templates/workspace/`, README.
- Consumers: existing `agentic.workspace.repos` declarations keep evaluating and render the same `mani.yaml` content. Consumers that read `config.agentic.workspace.repos.<name>.path` directly keep working; the resolved form is the recommended read path. Consumers that already vendor a `programs.herdr` module must drop it or skip core's to avoid a duplicate option declaration (see design, migration).
