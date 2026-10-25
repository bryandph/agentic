## Context

`modules/workspace.nix` holds the delivered milestone. Its devenv half takes `agentic.workspace.repos.<name>.{path,url,tags}` and writes `mani.yaml` through devenv's `files` layer, with `sync_gitignore = false` so an allowlist `.gitignore` in the workspace repository is not rewritten. Its Home Manager half takes `agentic.workspace.root`, sets git `worktree.useRelativePaths`, and sets Herdr's `worktrees.directory` only when a `programs.herdr` option exists, because core does not provide one. `modules/checks/workspace.nix` covers both halves: `workspace-devenv` validates the rendered manifest with `mani check`, `workspace-home` checks the Home Manager result with and without a Herdr stub.

The devenv workspace module is exported on its own as `devenvModules.workspace` and is not covered by the `workbench` alias in `modules/registry.nix`, which applies to the flake-parts registry only. The Home Manager half reaches consumers both through `homeModules.workspace` and through `homeModules.agentic`/`workbench`.

The tool choice behind the declaration was made on BPH-73 (operator, 2026-10-20) and is recorded below as D1. The decisions marked "operator, 2026-10-24" were made in review of this draft; the rest of the document is proposed.

## Goals / Non-Goals

**Goals:**

- One declaration of repositories and paths that works for any forge and any folder layout, with organisation layout supplied as configuration.
- A renderer boundary that keeps the declaration independent of mani and makes rendering safe for existing checkouts.
- Development against local peer checkouts without pin bumps.
- A template and README so someone outside the operator's environment can create their own workspace instance.

**Non-Goals:** as listed in the proposal. In particular, nothing here fetches from a forge API, pins revisions, or moves a checkout.

## Layer placement

| Artifact | Layer | Why |
|---|---|---|
| Schema, resolved form, mani renderer, audit, override helper, Herdr HM module, template, fixtures | core | True for any organisation's workspace. |
| Remote base URLs, mirror aliases, the `defaultPath` function that encodes an area layout | env (the instance repository) | Names forges and an organisation's folder convention. |
| Which repositories exist and where they are checked out | env (the instance repository) | The instance is the declaration. |
| Repository-specific setup after clone (hooks, trust, secrets) | repo, or the instance's own scripts | Not a property of the workspace. |

## Decisions

### D1. mani is the first backend (decided, operator, 2026-10-20)

mani renders from generated config, clones missing projects without touching existing ones, runs tasks across projects, is in nixpkgs, and behaves the same on macOS and Linux, including WSL. Its own worktree management (`worktrees`, `remove_orphaned_worktrees`) and remote synchronisation (`sync_remotes`, `sync --sync-remotes`) overlap with Herdr and git and stay off.

Alternatives considered (survey on BPH-73): vcs2l and myrepos also fit the independent-repository model; Google repo and west pin revisions on detached HEADs; ghorg, git-workspace and ghq assume a forge organisation or host-derived layout; josh, copybara and git-subrepo change the git model.

Validation is part of the decision: on both workstations, `mani sync` must leave existing checkouts untouched, `mani run` must be useful and WSL must behave. If that fails, the fallback is vcs2l plus a small task runner. The fallback is cheap because core only renders configuration from the resolved declaration (D3), and the audit and override helper never depend on mani.

### D2. Schema: remotes, repos, groups, defaultPath

```
workbench.workspace = {
  remotes.<remote> = {
    url = "<base URL>";        # scp-style or URL form, any forge
    aliases = [ "<base URL>" ];# mirrors serving the same repositories
  };
  repos.<key> = {
    remote = "<remote>";       # with name: url = <remote.url>/<name>.git
    name = "<repo name>";      # default: <key>
    url = "<clone URL>";       # alternative to remote + name
    aliases = [ "<URL>" ];     # further URLs that identify this repository
    path = "<relative path>";  # default: defaultPath applied to the entry
    groups = [ "<group>" ];
  };
  defaultPath = entry: entry.name;
};
```

A repository sets exactly one of `remote` or `url`; an evaluation assertion names the entry when both or neither are set. A remote URL is joined to the name with `/` and a `.git` suffix (configurable per remote as `suffix`, default `".git"`), which covers scp-style SSH (`git@host:owner`), HTTPS and `ssh://` bases on Gitea, GitHub and GitHub Enterprise, GitLab (including nested groups, which are part of the base) and Bitbucket. `defaultPath` receives the entry's key, name, remote name and groups, and must return a relative path.

The default `defaultPath` puts every repository at `<name>` under the workspace root: a flat list. An area layout is configuration, and an area is expressed as a group (operator, 2026-10-24). For example, an instance that keeps its own repositories at the root and each area's repositories under a folder named after the area puts each area repository in a group naming the area and writes:

```
defaultPath = r: let area = lib.findFirst (g: lib.elem g areas) null r.groups;
  in if area == null then r.name else "${area}/${r.name}";
```

The function's input is exactly `{ key, name, remote, groups }`. Remotes carry no free-form attributes (operator, 2026-10-24): a remote describes where repositories are fetched from, and folder layout belongs to groups.

Paths are validated at evaluation: relative, normalised (no `.`, `..` or empty segments, no trailing slash), unique, and not the workspace root itself. A declared path inside another declared path is refused (operator, 2026-10-24), because `mani sync` would clone into another repository's working tree and that repository's status would show the nested checkout as untracked content.

Groups replace tags. They render as mani tags and are the selection unit for tasks and for the override helper. A group needs no separate declaration.

Alternatives: keep a raw URL per repository and leave composition to the consumer (rejected: every instance would re-implement remote joining and mirror equivalence, and the override helper needs mirror equivalence); derive paths from the URL's owner segment (rejected: assumes a forge layout, which is what ghq does); a template string for paths instead of a function (rejected: cannot express "root for some repositories, a folder for the others" without a mini-language); free-form attributes on remotes, such as an area slug, as `defaultPath` input (rejected by the operator: it ties layout to the forge side, and groups already carry it); allowing nested declared paths with a clone order (rejected by the operator: no current case needs it).

### D3. A resolved form is the only renderer input

The module computes `workbench.workspace.resolved`, a read-only, JSON-serialisable list of `{ key, url, aliases, path, groups }` with remotes joined, paths computed and aliases expanded (remote aliases joined with the name, plus the entry's own). The shell also exposes it as a JSON file whose path is in `WORKBENCH_WORKSPACE_MANIFEST`, for scripts. Renderers, the audit and the override helper read only this. A consumer script that today reads `repos.<name>.path` can switch to it.

Alternative: each renderer reads the options. Rejected because the vcs2l fallback or a second manifest format would duplicate remote joining and path rules.

### D4. Renderers write manifests only

The mani renderer writes `mani.yaml` with `sync_gitignore`, `sync_remotes` and `remove_orphaned_worktrees` set to false and no per-project `worktrees` or `remotes`. `extraConfig` stays as a freeform escape hatch, but an assertion refuses `extraConfig` or project overrides that set any of those keys to a value that enables them. Tasks keep their current default (`status`, `fetch`).

What rendering does not do is the contract: no clone, fetch, reset, clean, checkout or move happens at shell entry. Changing an entry's path does not move its checkout; the next `mani sync` clones at the new path and the audit reports the old checkout as undeclared. Each renderer is selectable (`renderers.mani.enable`, default true when any repository is declared), so a later renderer can be added beside mani or replace it.

Alternative: run `mani sync` on shell entry. Rejected: network access and clones on every shell entry, and failures there are hard to see.

### D5. Read-only audit

A `workspace-audit` command in the shell compares the resolved declaration with the tree and reports, without changing anything: declared but missing; present but not a git repository; origin URL that matches neither the declared URL nor an alias; and top-level directories not declared and not listed in `audit.ignore`. It exits non-zero only when asked (`--strict`), so it can serve as a check. The audit ships in this change (operator, 2026-10-24): BPH-73 records it as needed whatever backend D1 ends with, and the instance migration's prevention step depends on it.

Alternative: a follow-up change. Rejected because the instance migration needs the audit before and after the schema switch.

### D6. Local flake-input overrides

A `workspace-overrides` command takes a consumer flake directory (default: the current directory) and reads its `flake.lock`. For every input node that is not a `follows`, it normalises the locked and original URLs (scheme spelling, `git+ssh://`/scp-style/`ssh://`, trailing `.git`, `github:owner/repo` and its HTTPS and SSH forms) and matches them against each resolved entry's URL and aliases. When an entry matches and its checkout exists, it emits `--override-input <input path> git+file://<absolute checkout>` for that input, with nested inputs addressed as `a/b`. `--no-write-lock-file` is emitted once, so an override never ends up in a lock. Output is one shell-quoted argument list; `workspace-overrides -- nix build .#x` runs the command with the arguments added. These two forms are the whole interface (operator, 2026-10-24): every override is visible on the command that uses it.

Inputs whose URL cannot match an entry, such as relative `path:` inputs backed by a submodule, are mapped explicitly with `overrides.<input path> = "<key>"` in the consumer's own declaration or with `--map <input>=<key>` on the command line. `--checkout <key>=<dir>` points an entry at a different checkout, typically a worktree, for one run. `--only <key or group>` limits the set. Inputs that `follows` an overridden input pick it up through Nix and need no argument.

`git+file` is the default because it carries uncommitted changes to tracked files, which is what the BPH-73 done-when needs, while leaving out ignored build output. New files must be added to the index (`git add -N`) before Nix sees them; the command prints that reminder when a checkout has untracked files. `--scheme path` switches to `path:` for checkouts where untracked files matter. Submodule-bearing checkouts get `?submodules=1`.

Alternatives: a shell-wide setting that adds the overrides to every `nix` call in the dev shell (rejected by the operator for now: an evaluation would differ from its lock with nothing on the command line to show it); `nix flake lock --override-input` or `nix flake update` against local paths (rejected: writes the lock and makes pins point at a workstation path); a `follows` into a local registry entry (rejected: global state, hard to see per run); `path:` by default (rejected: copies ignored build output into the store on every evaluation).

### D7. Home Manager half and Herdr

`workspace.root` and `worktreeDir` keep their current types, defaults and behaviour, and gain the `workbench.workspace` alias. Core gains `homeModules.herdr`: a `programs.herdr` module with the org-neutral surface (`enable`, `package`, `extraConfig` rendered to Herdr's TOML config, and reconciliation of the Nix-owned keys into the writable live file, since Herdr writes runtime state into the same file). It is included in `homeModules.workbench`/`agentic`, so a core-only consumer gets `programs.herdr` and the workspace root then sets `worktrees.directory`. That is the whole core surface (operator, 2026-10-24). Plugins, agent-detection overrides and personal defaults such as key bindings, commands and SSH host lists stay with the consumer, as plain `extraConfig` values or in the consumer's own module. The package stays consumer-supplied; `programs.herdr.enable` defaults to false, so importing the module writes nothing.

The workspace module keeps its current guard (configure Herdr only where `programs.herdr` exists), so a consumer that imports only `homeModules.workspace` sees no change.

Alternatives: add Herdr as a core flake input and re-export its module (rejected: upstream ships no Home Manager module, and every core consumer's lock would gain the input); move plugins and agent detection into core as well (rejected by the operator: they are consumer choices and carry activation steps core does not need); write Herdr's config file from the workspace module directly (rejected: a second writer next to any `programs.herdr` module); leave Herdr to consumers (rejected: the scope on BPH-73 asks for core-only consumers to get it).

### D8. Template and instance pattern

`nix flake init -t <core>#workspace` creates a workspace repository: an allowlist `.gitignore` that ignores everything and re-includes only the scaffolding files, an `.envrc` that loads the dev shell, and a `flake.nix` that imports the workspace devenv module and declares empty `remotes` and `repos`. The README section describes the pattern: the workspace root is itself a small repository that tracks only scaffolding and the declaration, other repositories are ordinary checkouts beneath it, and Home Manager points worktree tooling at `<root>/.worktrees`. Examples use `*.example` hosts.

### D9. Large binary content is deferred (operator, 2026-10-24)

Whether the declaration gains a non-git `stores` kind or a per-repository LFS flag is decided in BPH-74. This change reserves nothing in the schema for either; adding them later is additive.

## Migration

Option namespace. The devenv workspace module adds `mkAliasOptionModule ["workbench" "workspace"] ["agentic" "workspace"]` (or the reverse, once the implementation namespace moves, as the README compatibility phase describes). Both names keep working; alias removal is the separate breaking change already planned for the whole surface.

Schema. The change is compatible. An existing entry `{ path; url; tags; }` is a valid new entry: `url` instead of `remote`, an explicit `path`, and `tags` read as `groups` with a deprecation warning. Its rendered `mani.yaml` project entries are identical, and the manifest gains explicit `sync_remotes: false` and `remove_orphaned_worktrees: false` keys, which match mani's defaults. A consumer moves to the new form by declaring `remotes`, replacing `url` with `remote`, and dropping `path` wherever `defaultPath` produces the same value. The audit run before and after shows whether any path changed.

Alternative: a breaking schema with no `url`/`tags` compatibility. Rejected: there is one known consumer, but nothing is gained by breaking it, and the compatible form costs one option.

Herdr. A consumer that vendors its own `programs.herdr` module and imports `homeModules.workbench` would declare the option twice. Its migration is to drop the vendored module and keep its values, or, until it does, to import `homeModules.workspace` alone. Implementation lands the core module first and the consumer switch afterwards, in the consumer's repository.

Rollback. Every step is additive until a consumer changes its declaration; reverting the core commit and the consumer's pin restores the milestone.

## Risks / Trade-offs

- [mani fails validation on one workstation] → D1's fallback; only the renderer changes.
- [URL normalisation gives a false match between different repositories] → matching is exact after normalisation, never by name alone; the command prints every match it makes.
- [Override silently omits new files] → `git+file` semantics; the command warns when a checkout has untracked files and offers `--scheme path`.
- [A path change looks like a move but is not] → documented in D4; the audit reports the stale checkout.
- [Herdr option surface drifts from upstream Herdr] → core's module keeps only `extraConfig` as typed surface beyond `enable`/`package`, so new Herdr keys need no core change.

## Open Questions

None. The six questions raised in review were decided by the operator on 2026-10-24 and are recorded in D2 (nested paths refused; `defaultPath` input, areas as groups), D5 (audit ships here), D6 (argument list plus `--` exec only), D7 (Herdr core surface) and D9 (binary content deferred).
