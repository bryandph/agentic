# workbench-workspace Specification

## Purpose
Declare a workspace of independently versioned repositories on any forge, render repository-manager configuration from that declaration without touching existing checkouts, audit the tree against it, derive local flake-input overrides from it, and place worktrees under one root. `flake.lock` stays the only pin.

## Requirements
### Requirement: Forge-neutral repository declaration
The workspace module SHALL accept a declaration of named remotes and repositories under `workbench.workspace`, with `agentic.workspace` resolving to the same options. A remote SHALL carry a base URL and MAY carry mirror alias base URLs; any git URL form (scp-style SSH, `ssh://`, HTTPS) SHALL be accepted for any forge. A repository SHALL be given either as a `remote` plus a `name` (defaulting to its key), whose clone URL is the remote's base URL joined with the name and the remote's suffix, or as a full `url`, and MUST NOT set both or neither. A repository MAY carry `aliases` and a list of `groups`. Core SHALL NOT assume any organisation, owner or host structure in URLs.

#### Scenario: remote plus name on a non-Gitea forge
- **WHEN** a fixture declares a remote with an scp-style base URL on a GitLab-style host with a nested group, and a repository with that remote and a name
- **THEN** the resolved clone URL is the base URL, a slash, the name and `.git`, and the rendered manifest uses it

#### Scenario: full URL entry
- **WHEN** a repository declares `url` and no `remote`
- **THEN** the resolved clone URL is that URL unchanged

#### Scenario: ambiguous entry is refused
- **WHEN** a repository declares both `remote` and `url`, or neither
- **THEN** evaluation fails with an assertion that names the repository key

#### Scenario: both namespaces resolve to one declaration
- **WHEN** one module sets a repository under `workbench.workspace.repos` and another sets a different one under `agentic.workspace.repos`
- **THEN** the resolved declaration contains both and the rendered manifest is the same as when both are set under one name

### Requirement: Configurable checkout paths
Each repository SHALL have a checkout path relative to the workspace root, taken from its explicit `path` or else computed by the `defaultPath` function, whose input SHALL be exactly the entry's key, name, remote name and groups. Remotes SHALL NOT carry free-form attributes for path computation; an area or team layout SHALL be expressed through groups. The default `defaultPath` SHALL place every repository at its name directly under the workspace root. Paths MUST be relative and normalised, MUST be unique, and MUST NOT be the workspace root; a violation SHALL fail evaluation naming the entries involved. A declared path MUST NOT lie inside another declared repository's path; such a declaration SHALL fail evaluation naming both entries.

#### Scenario: flat list with no organisation structure
- **WHEN** a fixture declares several repositories by full URL with no remotes, no paths and no groups
- **THEN** each resolves to a path equal to its name at the workspace root and the rendered manifest passes `mani check`

#### Scenario: layout supplied by configuration
- **WHEN** a fixture sets `defaultPath` to place repositories in an area group under a folder named after that group and every other repository at the root
- **THEN** resolved paths follow that function, and an explicit `path` on an entry overrides it

#### Scenario: colliding paths are refused
- **WHEN** two entries resolve to the same path
- **THEN** evaluation fails with an assertion naming both entries

#### Scenario: nested repository path is refused
- **WHEN** one entry resolves to `a` and another to `a/b`, whether through explicit paths or `defaultPath`
- **THEN** evaluation fails with an assertion naming both entries and no manifest is rendered

### Requirement: Resolved declaration
The module SHALL expose the declaration in one resolved, JSON-serialisable form listing, per repository, its key, clone URL, all alias URLs (remote aliases joined with the name, plus the entry's own), path and groups. Every renderer, the audit and the override helper SHALL read only this form. The dev shell SHALL make it available to scripts as a file.

#### Scenario: renderers agree with the resolved form
- **WHEN** the populated fixtures are evaluated
- **THEN** every project in the rendered manifest has the URL, path and tags of the matching resolved entry, and no resolved entry is missing from the manifest

### Requirement: Compatibility with the milestone schema
Existing entries of the form `repos.<key> = { path; url; tags; }` SHALL remain valid. `tags` SHALL be read as `groups` and SHALL produce a deprecation warning. For such entries the rendered manifest's projects SHALL be identical to the milestone's output.

#### Scenario: milestone declaration renders unchanged
- **WHEN** the milestone fixture declaration (explicit path, URL and tags) is evaluated against the new module
- **THEN** the manifest's project entries equal the milestone's, and evaluation emits a warning that `tags` is deprecated in favour of `groups`

### Requirement: Manifest renderers never touch checkouts
Rendering SHALL write only manifest files. Entering the shell or rendering MUST NOT clone, fetch, reset, clean, check out, move or delete any repository or worktree. The mani renderer, the first backend, SHALL write `mani.yaml` with `sync_gitignore`, `sync_remotes` and `remove_orphaned_worktrees` set to false and with no per-project `worktrees` or `remotes`, and SHALL refuse at evaluation any `extraConfig` or per-project override that enables one of them. Each renderer SHALL be individually selectable, and additional manifest formats SHALL be added as renderers of the resolved declaration rather than as new declarations.

#### Scenario: rendered manifest keeps destructive features off
- **WHEN** any populated fixture is rendered
- **THEN** `mani.yaml` sets `sync_gitignore: false`, `sync_remotes: false` and `remove_orphaned_worktrees: false`, and no project has a `worktrees` or `remotes` key

#### Scenario: enabling a destructive mani feature is refused
- **WHEN** a consumer sets `extraConfig.remove_orphaned_worktrees = true` or `extraConfig.sync_remotes = true`
- **THEN** evaluation fails with an assertion naming the key

#### Scenario: sync leaves existing checkouts alone
- **WHEN** `mani sync` runs on a rendered manifest where one declared checkout exists with local commits, uncommitted edits and an extra worktree, and another is missing
- **THEN** the missing one is cloned, and the existing one's HEAD, index, working tree, remotes and worktrees are unchanged

#### Scenario: empty declaration renders nothing
- **WHEN** no repository is declared
- **THEN** no manifest file is written and no package is added to the shell

### Requirement: Read-only workspace audit
The shell SHALL provide an audit command that compares the resolved declaration with the workspace tree and reports declared but missing checkouts, declared paths that are not git repositories, checkouts whose origin URL matches neither the declared URL nor an alias, and top-level entries that are neither declared, nor ancestors of a declared path, nor listed as ignored. The audit MUST NOT modify any file or repository. It SHALL exit zero unless run in strict mode with findings.

#### Scenario: audit reports without changing anything
- **WHEN** the audit runs over a fixture tree with one missing checkout, one origin mismatch and one undeclared directory
- **THEN** it reports exactly those three findings and the tree is byte-for-byte unchanged afterwards

### Requirement: Local flake-input overrides
The shell SHALL provide an override helper that reads a consumer flake's `flake.lock` and, for every input that is not a `follows` and whose locked or original URL matches a resolved entry's URL or alias after normalisation, emits `--override-input <input path> <checkout reference>` pointing at that entry's existing checkout, plus `--no-write-lock-file`. Nested inputs SHALL be addressed by their slash-separated input path. Inputs that cannot be matched by URL SHALL be mappable to an entry explicitly, and an entry SHALL be pointable at another checkout such as a worktree for one run. The default checkout reference SHALL be a `git+file` URL of the absolute checkout path, which includes uncommitted changes to tracked files; a `path` scheme SHALL be available on request. The helper's output forms SHALL be the argument list and a mode that runs a given command with the arguments added; the shell SHALL NOT apply overrides to `nix` calls implicitly. The helper MUST NOT write any lock file and MUST NOT emit an override for a checkout that does not exist. It SHALL print each match it makes.

#### Scenario: uncommitted core edit reaches a consumer without a pin bump
- **WHEN** a fixture consumer flake locks an input to a forge URL declared in the workspace, the matching checkout has an uncommitted edit to a tracked file, and the consumer is evaluated with the helper's arguments
- **THEN** the evaluation sees the edited value, and the consumer's `flake.lock` is unchanged

#### Scenario: mirror URL matches through an alias
- **WHEN** the consumer locks the input through a mirror URL that is declared as a remote alias
- **THEN** the helper matches the same entry and emits the override

#### Scenario: relative path input mapped explicitly
- **WHEN** a consumer's input is a relative `path:` input that no URL can match, and it is mapped to an entry
- **THEN** the helper emits the override for that input path

#### Scenario: follows and missing checkouts are skipped
- **WHEN** a nested input follows a root input, and another matched entry has no checkout on disk
- **THEN** no override is emitted for either, and the missing checkout is reported

### Requirement: Shared worktree root
The Home Manager workspace module SHALL keep `workspace.root` (null by default) and `worktreeDir` (default `<root>/.worktrees`), available under both `workbench.workspace` and `agentic.workspace`. When `root` is set it SHALL set git `worktree.useRelativePaths` and, when a `programs.herdr` option exists, Herdr's worktree directory, both as defaults a consumer can override. When `root` is null it SHALL configure nothing.

#### Scenario: root set with Herdr present
- **WHEN** a Home Manager configuration sets the root and has `programs.herdr`
- **THEN** Herdr's worktree directory is `<root>/.worktrees` and git records worktree links as relative paths

#### Scenario: root unset
- **WHEN** the root is null
- **THEN** neither git nor Herdr configuration is changed

### Requirement: Herdr configuration for core-only consumers
Core SHALL publish an org-neutral `programs.herdr` Home Manager module, as `homeModules.herdr` and as part of `homeModules.workbench`, that renders consumer-supplied settings to Herdr's configuration file and reconciles the Nix-owned keys into the writable live file without discarding keys Herdr writes at runtime. It SHALL be disabled by default, SHALL write nothing while disabled, and SHALL leave the Herdr package consumer-supplied. Its typed surface SHALL be `enable`, `package` and `extraConfig`, plus the reconciliation. Plugins and agent-detection overrides SHALL remain with consumers, and core SHALL NOT ship personal key bindings, commands or host lists as defaults.

#### Scenario: core-only consumer gets the worktree root in Herdr
- **WHEN** a Home Manager configuration imports only core's Home Manager module, enables `programs.herdr` with a stub package, and sets the workspace root
- **THEN** the rendered Herdr configuration sets the worktree directory to `<root>/.worktrees`

#### Scenario: disabled module writes nothing
- **WHEN** core's Home Manager module is imported and `programs.herdr.enable` is false
- **THEN** no Herdr configuration file or activation step is produced

### Requirement: Workspace instance template
Core SHALL publish a `workspace` flake template containing an allowlist `.gitignore` that ignores everything except the scaffolding files, an `.envrc` that loads the dev shell, and a `flake.nix` that imports the workspace devenv module with an empty declaration. The template SHALL contain no environment hosts or endpoints. The public README SHALL describe the instance pattern: a workspace root that is itself a repository tracking only scaffolding and the declaration, with the other repositories as checkouts beneath it and worktrees under the shared worktree root.

#### Scenario: template evaluates empty
- **WHEN** the `workspace` template is instantiated and its dev shell evaluated with core substituted for the input
- **THEN** evaluation succeeds, no manifest is rendered, and `git status` in the new repository shows only the scaffolding files as untracked

#### Scenario: allowlist keeps checkouts out
- **WHEN** a repository directory is created beneath an instantiated template
- **THEN** `git status` in the template repository does not list it

