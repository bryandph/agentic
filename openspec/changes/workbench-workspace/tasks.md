Implementation starts only after the operator approves this change as a whole. The review questions were decided on 2026-10-24 (design D2, D5, D6, D7, D9). Each section is one shippable commit. `<system>` is the workstation's system; checks run without `--all-systems`.

## 1. Approval and baseline

- [x] 1.1 Operator decisions on the review questions (2026-10-24): binary content deferred to BPH-74 with nothing reserved (D9); nested declared paths refused (D2); overrides as an argument list plus `--` exec only (D6); the audit ships in this change (D5); Herdr core surface is `enable`/`package`/`extraConfig` plus reconciliation (D7); `defaultPath` input is `{ key, name, remote, groups }` with areas as groups (D2)
- [x] 1.2 Operator approval of the change as a whole, recorded on BPH-73 (2026-10-24)
- [x] 1.3 Record the current `workspace-devenv` manifest output as the compatibility baseline for 2.4
- [x] 1.4 Baseline gates pass before any edit: `nix fmt` leaves no diff; `nix build .#checks.<system>.workspace-devenv .#checks.<system>.workspace-home .#checks.<system>.org-neutral --no-link`

## 2. Declaration schema and resolved form

- [x] 2.1 Add `remotes`, the new `repos` fields (`remote`, `name`, `url`, `aliases`, `path`, `groups`) and `defaultPath` in `modules/workspace.nix`, with the one-of `remote`/`url` and path assertions
- [x] 2.2 Add the resolved form and the shell's manifest file; switch the mani renderer to read only the resolved form
- [x] 2.3 Add the `workbench.workspace` alias to the devenv workspace module; read `tags` as `groups` with a deprecation warning
- [x] 2.4 Fixtures in `modules/checks/workspace.nix`: a non-Gitea remote (scp-style, nested group) entry; a flat list by URL with no remotes, paths or groups; an area-as-group `defaultPath` fixture; refusal cases (both/neither of `remote`/`url`, colliding paths, a path nested inside another declared path); the milestone declaration rendering identical project entries to the 1.3 baseline; mixed `workbench`/`agentic` declarations
- [x] 2.5 Gates: `nix fmt`; `nix build .#checks.<system>.workspace-devenv .#checks.<system>.org-neutral --no-link`

## 3. Renderer boundary

- [x] 3.1 Set `sync_remotes` and `remove_orphaned_worktrees` explicitly false; add assertions refusing `extraConfig` or project overrides that enable them or add `worktrees`/`remotes`; add `renderers.mani.enable`
- [x] 3.2 Sync-safety check: in a sandbox with local bare repositories as remotes, run `mani sync` over a manifest where one checkout exists (local commit, uncommitted edit, extra worktree) and one is missing; assert the missing one is cloned and the existing one's HEAD, index, working tree, remotes and worktree list are unchanged
- [x] 3.3 Gates: `nix fmt`; `nix build .#checks.<system>.workspace-devenv .#checks.<system>.workspace-sync --no-link`

## 4. Audit

- [x] 4.1 Add the `workspace-audit` command with `audit.ignore` and `--strict`
- [x] 4.2 Check `workspace-audit` over a fixture tree with one missing checkout, one origin mismatch and one undeclared directory; assert the three findings and an unchanged tree (hash before and after)
- [x] 4.3 Gates: `nix fmt`; `nix build .#checks.<system>.workspace-audit --no-link`

## 5. Local flake-input overrides

- [x] 5.1 Add the `workspace-overrides` command: lock reading, URL normalisation, alias matching, nested input paths, `follows` skipping, `--map`, `--checkout`, `--only`, `--scheme`, `--` exec, untracked-file warning, `--no-write-lock-file`
- [x] 5.2 Unit fixtures for URL normalisation across scp-style, `ssh://`, `git+ssh://`, HTTPS and `github:` forms, including a mirror alias and a non-match between two repositories of the same name on different remotes
- [x] 5.3 Check `workspace-overrides`: a fixture consumer flake locks an input to a declared URL; the peer checkout carries an uncommitted edit to a tracked file; evaluation with the emitted arguments sees the edit and leaves `flake.lock` byte-identical; also the relative `path:` input mapped explicitly and the missing-checkout case
- [x] 5.4 Gates: `nix fmt`; `nix build .#checks.<system>.workspace-overrides --no-link`

## 6. Home Manager half and Herdr

- [x] 6.1 Add the `workbench.workspace` alias to the Home Manager workspace module with no behaviour change
- [x] 6.2 Add the org-neutral `programs.herdr` module (`enable`, `package`, `extraConfig`, live-file reconciliation), export it as `homeModules.herdr` and include it in `homeModules.workbench`/`agentic`
- [x] 6.3 Extend `workspace-home`: core-only consumer with Herdr enabled gets `<root>/.worktrees`; Herdr disabled writes no file or activation step; `homeModules.workspace` alone behaves as today; reconciliation keeps a runtime-written key (as `checks.herdr-home`, which also covers a flake-parts consumer carrying its own herdr module)
- [x] 6.4 Gates: `nix fmt`; `nix build .#checks.<system>.workspace-home .#checks.<system>.public-surface .#checks.<system>.org-neutral --no-link`

## 7. Template and README

- [ ] 7.1 Add `templates/workspace/` (allowlist `.gitignore`, `.envrc`, `flake.nix` with empty declaration) and register it in `modules/templates.nix`
- [ ] 7.2 Template check: instantiate, evaluate the shell with core substituted, assert no manifest and only scaffolding untracked; create a nested repository directory and assert the allowlist hides it
- [ ] 7.3 README: workspace section covering the declaration, renderer boundary, audit, overrides, worktree root and instance pattern, with `*.example` hosts only
- [ ] 7.4 Gates: `nix fmt`; `nix build .#checks.<system>.workspace-template .#checks.<system>.org-neutral --no-link`

## 8. Review gate

- [ ] 8.1 `nix flake check` passes on the workstation's system
- [ ] 8.2 `nix develop -c openspec validate workbench-workspace --strict` passes
- [ ] 8.3 Update BPH-73 with the commit links and check evidence; hand off for review. Merge needs the operator's authorisation

## 9. BPH-73 done-when (consumer work, outside this repository)

These are verified in the consuming repositories under their own work, after the core change is published; they are listed here because BPH-73 closes on them.

- [ ] 9.1 Fixtures pass for a non-Gitea remote and for a flat list with no org/area structure (tasks 2.4 and 3.2 in core)
- [ ] 9.2 The workspace instance repository uses the new schema with Area-derived paths through `defaultPath`; the audit shows no path change against the previous manifest
- [ ] 9.3 An uncommitted core edit reaches an evaluation of the operator's infrastructure repository through `workspace-overrides` with no pin bump, and that repository's `flake.lock` is unchanged afterwards
- [ ] 9.4 On both workstations (macOS and WSL), `mani sync` leaves existing checkouts untouched and `mani run` is useful (D1 validation); if not, open the vcs2l fallback as a follow-up
