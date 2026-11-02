# agentic

Org-neutral core for the agentic development environment: a declarative MCP
server registry, an agent + knowledge registry, a devenv shell bootstrap,
and project templates — consumable as a flake by any environment.

## Layering contract

Three layers, merged at consumption time (the `mandala` / `mandala-bph`
precedent):

| Layer | Lives in | Carries |
|---|---|---|
| **core** (this repo) | `git.bph/bryan/agentic`, mirrored to GitHub | Schemas, renderers, delivery adapters, org-neutral knowledge fragments, language profiles, templates |
| **env** (e.g. `agentic-bph`) | the environment's private aggregation point (a repo or a `modules/` subtree) | Forge instances, secret-backend config, model endpoints, org knowledge fragments |
| **repo** | each consuming repo | Repo traits (submodules, services, secret dotfiles), repo knowledge fragments, repo agents |

**Placement test** for any artifact: *"would this sentence be true at
work?"* — true → core; true only in one environment → env layer; true only
in one repo → repo.

Hard rules:

- Core contains **no environment identity**: no forge hostnames, secret
  mounts/addresses, model endpoints, host names, or org-specific knowledge.
  Every environment-specific value enters through a module option.
- Secrets are sourced at runtime by a CLI (modular backend; vault/OpenBao
  wired, others as presets). Raw values never land in rendered artifacts or
  the nix store.
- Core fragments may only reference deep sources that every consumer of
  core can see (e.g. memories core itself ships) — never a consuming repo's
  artifacts.

## Secret scanning (opt-in)

Betterleaks is the single scanner for the staged hook, deterministic source-tree
check and explicit history audit. The package comes from the consumer's `pkgs`
(and therefore its nixpkgs pin); this implementation is qualified with 1.3.1.
No organization policy or automatic adoption is built in.

For a flake-parts consumer already importing `agentic.flakeModules.default`:

```nix
agentic.secretScanning.enable = true;
# Optional repo-relative, committed exception files:
# agentic.secretScanning.baseline = ".secret-baseline.json";
# agentic.secretScanning.ignoreFile = ".betterleaksignore";
```

Import the resulting consumer `config.flake.modules.devenv.agentic` into the
devenv shell as usual. Its shellModule composes the existing `git-hooks` lifecycle
module and adds a generated prek hook (no handwritten pre-commit YAML). The
same option works in the devenv-native transport. That transport has no flake
outputs: use `agentic.secretScanning.lib.check pkgs source` for a CI derivation
when building a separate flake. Flake-parts consumers automatically receive
`packages.<system>.agentic-secret-scan` and `checks.<system>.secret-scanning`.
The check scans the consumer's flake source, not Agentic's source.

```sh
agentic-secret-scan --mode staged    # index diff only; the commit-time hook
agentic-secret-scan --mode worktree  # current tracked file contents, not history
agentic-secret-scan --mode history  # deliberate read-only audit of all local refs
nix build .#checks.aarch64-darwin.secret-scanning  # deterministic CI/source scan
```

The CLI also accepts `--source DIR` and `--report FILE`. Without `.git`, worktree
mode scans the source tree; with Git it snapshots tracked regular files only,
including their unstaged contents. Untracked files are intentionally excluded;
stage new files before scanning them. Symlinks, Git metadata and gitlinks are
never traversed; source trees honor `.gitmodules` paths and nested `.git`
markers. Each submodule must opt in and scan independently in its owning repo.
History is never run by the hook or sandbox check. Exit codes are 0 (clean),
1 (unbaselined findings), and 2 (scan/configuration failure).

All modes force `--redact=100`, discard raw scanner stdout/stderr, and project
JSON to **RuleID, File, StartLine, Fingerprint only** before emitting it to stdout
or the report file. Raw scanner diagnostics and reports are never published.
Do not bypass this boundary by calling Betterleaks directly for CI reports.

Environment modules can merge or override `agentic.secretScanning.config`
(TOML attributes; default `{ extend.useDefault = true; }`), for example adding
narrow generic `allowlists`. Repositories should supply only justified local
exceptions, not copy the shared rules. `--config`, `--baseline`, and
`--ignore-file` offer explicit one-off CLI overrides; implicit scanner config
and ignore discovery is disabled. Baseline paths and ignore paths are relative
to `--source` and must exist when configured.

For a known historical finding, review whether it was a real credential and
rotate/revoke it first. Commit a sanitized `--report` as the baseline only after
review, with an issue/reason in the change description. Baselines match exact
fingerprints; source/staged/history fingerprints may differ, so audit each
intended mode. Never commit raw Betterleaks reports. A fingerprint ignore file
is an alternative for individually justified findings. For an intentional
placeholder on a specific line, use `betterleaks:allow` with a reason next to
it; prefer this narrowly scoped inline allowlist to disabling a whole rule.
Encrypted stores are not blanket-excluded: the same policy detects accidental
plaintext while leaving organization-specific exceptions to the environment.

## Workspace

A workspace is one tree of independently versioned repositories under a
single root, declared once in Nix instead of chained together with
submodules. Core ships the declaration and the tools around it; the
environment's own workspace repository supplies the remotes, the
repositories and the folder layout.

### Declaration

`devenvModules.workspace` (also in `flake.modules.devenv.workspace` for
flake-parts consumers) adds `workbench.workspace` (alias
`agentic.workspace`) to a devenv shell:

```nix
workbench.workspace = {
  remotes.team = {
    url = "git@forge.example:team";              # scp-style, ssh:// or HTTPS, any forge
    aliases = [ "https://mirror.example/team" ]; # mirrors serving the same repositories
  };
  repos = {
    tool.remote = "team";                        # git@forge.example:team/tool.git
    site = { remote = "team"; name = "website"; groups = [ "apps" ]; };
    lib = { url = "https://code.example/upstream/lib.git"; path = "third-party/lib"; };
  };
};
```

A repository sets exactly one of `remote` or `url`. With `remote`, the
clone URL is the remote's `url`, a `/`, the repository's `name` (default:
its key) and the remote's `suffix` (default `.git`). `aliases`, on a
remote or a repository, lists further URLs that identify the same
repository. `path` defaults to `defaultPath { key, name, remote, groups }`,
which returns `name`: a flat list under the root. `groups` are selection
labels; they render as mani tags and select repositories for tasks and
overrides. Paths must be relative and normalised, unique, and not inside
another declared path; evaluation fails and names the entries otherwise.
The first release's `tags` still works as a deprecated synonym of
`groups`.

A folder layout is configuration, and an area is a group. To keep the
workspace's own repositories at the root and each area's repositories in
a folder named after the area:

```nix
workbench.workspace.defaultPath = r: let
  area = lib.findFirst (g: lib.elem g [ "infra" "apps" ]) null r.groups;
in if area == null then r.name else "${area}/${r.name}";
```

With that, `site` above is checked out at `apps/website` and `tool` at
`tool`.

The declaration resolves to `workbench.workspace.resolved`, a list of
`{ key, url, aliases, path, groups }` with remotes joined and paths
computed. The shell exports it as JSON at `$WORKBENCH_WORKSPACE_MANIFEST`;
the renderer, the audit and the override helper read only that, and so
can your scripts.

### Rendering

With any repository declared, the shell puts `mani` on the path and
writes `mani.yaml` (`renderers.mani.enable = false` turns that off).
Rendering writes the manifest and nothing else: entering the shell never
clones, fetches or moves anything. `mani sync` clones what is missing and
leaves existing checkouts alone, and `status` and `fetch` are the default
tasks for `mani run` (`tasks` replaces them), as in
`mani run status --all` or `mani run fetch --tags apps`.

The manifest sets `sync_gitignore`, `sync_remotes` and
`remove_orphaned_worktrees` to false. `extraConfig` is merged over the
generated manifest, but evaluation refuses it when it enables any of
those three or adds per-project `worktrees` or `remotes`: worktrees belong
to the worktree tool and remotes to git. Changing a path does not move a
checkout; the next `mani sync` clones at the new path and the audit
reports the old one as undeclared.

### Audit

`workspace-audit` compares the declaration with the tree and changes
nothing. It reports declared paths that are missing, declared paths that
are not the top of a git repository, checkouts whose `origin` matches
neither the declared URL nor an alias, and top-level directories nobody
declared. Dot-directories and parents of declared paths are never
reported; list other names in `audit.ignore` or pass `--ignore`. The root
is `$DEVENV_ROOT` inside the workspace shell and the current directory
outside it; `--root` sets it. `--json` prints the findings as JSON, and
`--strict` exits 1 when there are any, so the audit can serve as a check.
Run it before and after changing the declaration to see what moved.

### Local overrides

`workspace-overrides` lets another flake evaluate against your local
checkouts without bumping its pins. It reads that flake's `flake.lock`
(the current directory, or `--flake DIR`), matches each input's locked and
original URL against the declared URLs and aliases across spellings
(scp-style, `ssh://`, `git+ssh://`, HTTPS, `github:`), and prints
`--override-input <input> git+file://<checkout>` for each match, followed
by `--no-write-lock-file`. That is the whole interface, an argument list
or a command run with it:

```sh
eval "nix build $(workspace-overrides) .#thing"
workspace-overrides -- nix build .#thing
```

Nothing applies overrides implicitly, so every override is visible on the
command that uses it, and the lock file is never written. The `--` form
runs only nix commands that do not write a lock. Checkouts are found
relative to the workspace root, `$DEVENV_ROOT` inside the workspace shell
(`--root` sets it).

Inputs that no URL can match, such as a relative `path:` input backed by
a submodule, are mapped with `--map <input>=<key>` or, in the
declaration, `workbench.workspace.overrides.<input> = "<key>"`; nested
inputs are addressed as `a/b`. `--checkout <key>=<dir>` points one
repository at another checkout, such as a worktree, for one run, and
`--only <key or group>` limits the set. `git+file` sees uncommitted edits
to tracked files but not new files until they are added with `git add -N`;
the command reminds you when a checkout has untracked files, and
`--scheme path` uses `path:` instead.

### Worktrees and Herdr

The Home Manager half, `homeModules.workspace` (also part of
`homeModules.workbench`), takes `workbench.workspace.root`, the absolute
path of the workspace root. Setting it makes git record worktree links as
relative paths, so checkouts survive moving the tree, and points Herdr's
`worktrees.directory` at `worktreeDir`, by default `<root>/.worktrees`,
where Herdr creates `<repo>/<branch>` checkouts. Herdr is configured only
where a `programs.herdr` option exists.

`homeModules.herdr` is core's `programs.herdr`: `enable` (default false),
`package` (yours to supply; core pins no Herdr) and `extraConfig` in
Herdr's own key names, rendered to TOML. Herdr writes runtime state into
the same `config.toml`, so the file is not a store link; the wrapped
`herdr` reconciles the keys Nix owns into the live file at launch and
keeps the rest. It is part of `homeModules.workbench`. Flake-parts
consumers do not get it through `flake.modules.homeManager`, where it
could collide with a herdr module of their own; they import
`inputs.<core>.homeModules.herdr` explicitly. A consumer that already
carries its own `programs.herdr` module drops it in favour of core's, or
imports `homeModules.workspace` alone.

### Instance pattern

The workspace root is itself a small repository. It tracks the
declaration and a little scaffolding; the repositories beneath it are
ordinary checkouts with their own history, and worktrees live under
`<root>/.worktrees`. To create one:

```sh
mkdir ~/src && cd ~/src
nix flake init -t <core>#workspace
git init
```

This writes `flake.nix` with an empty declaration, an `.envrc` that loads
the dev shell, and an allowlist `.gitignore` that ignores everything
except those files and `flake.lock`, so checkouts, `.worktrees/`, the
rendered `mani.yaml` and shell state never show up in the workspace
repository's status. Set the core input in `flake.nix` to the flake you
consume, declare `remotes` and `repos`, enter the shell with
`direnv allow`, and run `mani sync`. Point Home Manager's
`workbench.workspace.root` at the same directory.

## Consuming

Internals are dendritic (every file under `modules/` is a flake-parts
module, auto-imported via import-tree; `_`-prefixed paths are skipped).
Consumers do **not** need any of that — the supported surfaces are:

- `flakeModules.workbench` (also `default` and legacy `agentic`) — flake-parts
  consumers.
- `devenvModules.workbench` (also `default` and legacy `agentic`) — the
  project shell bootstrap.
- `homeModules.workbench` (also `default` and legacy `agentic`) — user-tier
  (home-manager) delivery.
- `devenvModules.workspace`, `homeModules.workspace` and `homeModules.herdr`
  — the two [workspace](#workspace) halves and core's `programs.herdr`. The
  devenv half is imported on its own; the Home Manager half and `herdr` are
  also part of `homeModules.workbench`.
- `templates.<name>` — `nix flake init -t <core>#<name>`: `default`, the
  language variants, `adopt`, and `workspace`.
- `flake.modules.<class>.<name>` — dendritic consumers may merge the
  namespace directly; it carries the same modules as the aliases above.

`workbench.*` is the public option namespace for new consumers. Existing
`agentic.*` declarations remain valid and resolve to the same option graph;
the implementation still uses the Agentic paths during this compatibility
phase. Both names publish identical generated artifacts. Alias removal is a
separate breaking change after known consumers migrate.

Pi 1.1+ consumes the registry through its built-in MCP client: environments
reconcile user servers into writable `~/.pi/agent/mcp.json`, while project
bootstrap provides the trusted `.pi/mcp.json`. The legacy
`packages.<system>.pi-mcp-adapter` remains only for consumers pinned before
built-in MCP and must not be registered alongside it. Consuming flakes also
expose `pi-agent-roles`, a package of specialist prompt templates compiled from
the agent registry. See [Pi delivery](docs/pi.md) for ownership, native paths,
compatibility, and targeted checks.

Flake-parts integration defaults every devenv shell's `task.package` to the consumer's `inputs.devenv.packages.${system}.devenv-tasks` (no import-from-derivation); consumer overrides win, absent integration is skipped silently, and missing task packages warn and skip.

### Standalone self-healing Git hooks

A devenv shell can opt into hook isolation and GC protection without the
registry, MCP configuration, or full shell bootstrap:

```nix
# In a consumer's flake-parts module (with the agentic input available):
{ inputs, ... }: {
  perSystem = { ... }: {
    devenv.shells.default = {
      imports = [ inputs.agentic.devenvModules.git-hooks ];
      git-hooks.enable = true;
      # Configure git-hooks.hooks as usual; use prek as the hook package.
    };
  };
}
```

Consumers already importing `flakeModules.agentic` can instead use
`config.agentic.devenvLib.gitHooksModule` in the same `imports` list. Both
surfaces are the same standalone module. The full shell module (including the
native transport) already imports it.

Before devenv installs hooks, linked checkouts get their own Git hooks directory;
after installation, each embedded prek store output gets an indirect GC root
inside `git rev-parse --git-path hooks`. Re-entry replaces obsolete managed
roots. Removing the checkout's gitdir removes those roots; this does not root
the hook configuration or repair old hooks in other checkouts automatically.
Root registration uses unprivileged `nix-store --add-root --indirect --realise`
and warns without blocking shell entry if the Nix daemon cannot register it.
On registration failure it leaves previous roots alone; GC protection is not
guaranteed in that environment.

`agentic-hooks-doctor [--fix] [repository]` scans the main gitdir, submodule
gitdirs (including deinitialized submodules), and their linked worktrees for
prek-generated hooks with missing executables or configurations, or in orphaned
gitdirs with no verified checkout. Relative worktree registrations and submodule
`core.worktree` (including migrated `config.worktree`) resolve against their own
gitdir, never the doctor's current directory. It is included
in the module and `agentic.devenvLib.packages`; without a shell, run
`nix run <agentic>#agentic-hooks-doctor -- /path/to/repo`. Reports exit 1 when
dangling hooks are found, including on `--fix`; a clean scan exits 0 and an
operational error exits 2. `--fix` unlinks only the reported generated hook
files, never hand-written hooks, configurations, GC roots, or gitdirs. Shared
hooks with relative or default configs are removed only when invalid for every
checkout they serve. A config missing from only some checkouts is reported but
the shared hook is retained; isolate those checkouts by entering their shells.
Re-enter
the affected checkout's shell to install a fresh hook afterwards.

### Seat snapshots and fenced worker recovery

`packages.<system>.pi-seat-snapshot` is an org-neutral Pi extension package;
load its output with Pi's package configuration or `pi --extension <output>`.
Consumer enabling is deliberately separate. With `COTAL_SPACE` and `COTAL_NAME`
it writes `$XDG_STATE_HOME/cotal-seat/<space>/<name>.json` (default state home:
`~/.local/state`) at session start and every 60 seconds, outside model turns.
`COTAL_ID` supplies the instance id when available; the native session file and
cwd come from Pi's lifecycle context. Without a safe space/name it is inert.
Files use schema `agentic.seat-snapshot/1`, mode 0600, private directories,
fsync plus atomic rename, and are removed on clean shutdown (including reload).
No prompts, message contents or credentials enter the snapshot.

**Diagnostic limitation:** qualified against Cotal 0.91.0 and Pi 1.4.0, the
connector has no supported timer-side diagnostic read API. Pi's nested tool
caller is tool-execution-scoped, not a lifecycle/timer API. We neither call the
model nor inspect Cotal's private global runtime map. The writer records
`connection: null` and `connectionError: "observation unavailable: connector has
no supported diagnostics API (cotal <version>)"`. This is unavailable, not healthy.
The nullable connection object remains reserved for a future supported reader.

Both shell transports and this repository's dev shell include:

```sh
agentic-seat-snapshot --space <space> --name <presence-name> --json
workbench-worker-recover --worker <name> --worktree <path> --space <space>
workbench-worker-recover --worker <name> --worktree <path> --space <space> --action resume
workbench-worker-recover --worker <name> --worktree <path> --space <space> --action replace --assignment <file>
```

The reader lists records with derived `stale` (older than 180 seconds **or** pid
dead), liveness and queue fields when available. Unknown schemas are unavailable.
Readers never delete snapshots. Recovery always emits one JSON record; without
`--action` it only observes. Classes are `progressing`, `queue-stalled`, `blocked`,
`hung-process`, `dead`, or `unknown`. A fresh heartbeat is not progress: frozen
working `activeAt` text of at least 30 minutes signals a hung process; Herdr
blocked plus unchanged presence of at least 10 minutes signals blocked. Git
processes in the worktree aged at least 20 minutes include pid/etime. A supported
fresh connector observation can identify a queue head stalled for 15 minutes.
Missing diagnostics/ages remain unknown, never an invented healthy state.
Hung-process output suggests `kill -TERM <pid>` for coordinator review; the tool
never executes it or kills anything.

Optional broker queue observation uses `--admin-creds`, then
`AGENTIC_COTAL_ADMIN_CREDS`, then
`~/.local/share/cotal/<space>/attention-watch/admin.creds`. Only an owned regular
file with permissions exactly 0600 (no symlink) is accepted. The read-only
`cotal pending` sample retains only pending/ack-pending counts and sequence
numbers, never ids/senders/bodies. A single sample cannot prove progress stalled;
it is labelled `queue: unknown (single sample)`. Presence ages never imply a
queue stall. Recovery also reads the watcher's published floor observations from
`$XDG_STATE_HOME/agentic-attention-watch/state.json` (override with
`--watch-state <path>`), without changing the file. It requires an owned regular
0600 file, schema `agentic.attention-watch.state/1`, epoch-second `writtenAt`,
and positive `intervalSeconds`. State older than three intervals is unavailable.
Only `broker_progress[<presence-name>] = {floor, since, observedAt}` and the
file's `brokerCoverageSeconds` are inspected: a fresh entry with unchanged floor
for at least 900 seconds yields `queue-stalled` only when that agent was actually
observed within twice the coverage interval. Older per-agent observations are
`queue: unknown (watcher sample too old)`, even if the file is fresh from reading
other agents. A fresh file without an entry means not stalled per watcher. Missing, malformed,
stale or unknown-schema state leaves this queue observation unknown. Other
watcher state keys are ignored, not copied into recovery output.

Recovery refuses unless a known schema-1 snapshot's pid is dead, a complete mesh
presence read proves the old name offline (absence from complete live presence
also proves offline), and Herdr proves the single worker pane has no Pi process
or unrecognized foreground runtime. Two agents for one worktree, live snapshots,
partial reads, unknown process state and ambiguous panes all refuse. The existing
`workbench-worker-start` barrier rechecks setup and the available foreground shell.

`resume` passes the old readable session file to `pi-worker --resume` under a new
presence incarnation `<name>-r<N>`. **Cotal resumes Pi as a history-preserving
fork**, not an exact reopen: the source session stays untouched. The JSON attempt
records both the source and the new Pi session returned by startup. `replace`
requires the assignment and generates a private prompt combining it with branch,
HEAD, recent commits and uncommitted status. Both preserve the checkout and all
unresolved work; neither implies predecessor inbox inheritance. Follow-up DM text
is emitted for the coordinator to send, never sent automatically. The coordinator
must explicitly reconcile unacknowledged work and obtain assignment acceptance.

A per-worktree lock and private launch receipt under
`$XDG_STATE_HOME/agentic-worker-recover` serialize recovery and retain uncertain
launch outcomes. A repeat against the predecessor name refuses even after a lost
reply; inspect the recorded new incarnation and pane rather than retry blindly.
Recover a subsequent dead incarnation by its new name. Receipts are fencing
observations, not a competing work/assignment journal or authorization to merge.

### Worktree setup and verified teardown

Both shell transports include `workbench-worktree-setup`,
`workbench-worktree-teardown`, `workbench-worker-start`, and
`workbench-worktree-remove`. Run them from the main checkout's dev shell
against the path returned by the creator; do not infer it from the branch name.
The coordinator owns this sequence:

1. `herdr worktree create --cwd <repo> --branch <branch> --base <base> --no-focus`
   — record the returned checkout path, workspace ID and pane ID.
2. `workbench-worktree-setup --worktree <path>` — await its result.
3. Start the selected worker in its exact, available shell pane:
   `workbench-worker-start --pane <pane> --worktree <path> --timeout 30 -- <launcher> --prompt-file <file>`.
   The command checks setup and prompt-file readability before launching once,
   without `exec`, then observes Herdr (never mesh roster presence). It refuses
   missing, failed or stale setup; resolve that failure before launching.
4. After review and repository-specific resource reconciliation, confirm the
   worker has finished and run
   `workbench-worktree-remove --workspace <id> --worktree <path>`.
   The removal barrier verifies Herdr's workspace/path agreement and linked
   Git membership, refuses main checkouts, dirty or untracked paths, and
   working/blocked agents, then runs the repository's verified teardown.
   Only then does it ask Herdr to remove the worktree, without deleting its
   branch. Omit `--worktree` to resolve the path from Herdr's workspace JSON
   and worktree list. A mismatch refuses removal.
5. Retain its single JSON record (`status`, `reason`, `workspace`, `worktree`,
   `teardown`, `herdr`). Exit zero means `removed`; `refused` or `failed`
   requires preserving the diagnostics and escalating, not direct removal.
   Teardown stdout, stderr and verified lines are retained in the record.
   Only Git's specific initialized-submodule refusal permits an automatic
   `--force` retry, with fresh clean-tree and recursive submodule checks after
   successful teardown in this invocation. No auto-stash, untracked-file
   deletion, branch deletion or arbitrary force fallback is performed.

`workbench-worker-start` prints one JSON record with `status`, `pane`,
`workspace`, `worktree`, `agent`, native `session`, `agentStatus`, `evidence`,
`reason`, `fallback_reason`, `visible_blocker`, `diagnostics` and `ts`. Evidence is an ANSI-stripped pane tail of at
most 40 lines, 240 characters per line and 4,096 UTF-8 bytes total. Runs of
eight or more identical characters collapse to a short count marker. Diagnostics
use the same bounds and carry setup errors or Herdr lifecycle facts separately
(state, fallback reason, visible-state flags, manifest version and matched rule),
without detector buffer previews. The pane also prints the human-readable,
shell-quoted launcher command before starting it. Exit codes are 0 `started`, 10
`blocked`, 11 `not-started`, 20 `launch-failed`, 30 `setup-failed`; argument errors are CLI
misuse. Timeout is in seconds; unclassified startup or an undetected agent
fails closed. A detected agent that never reaches working/blocked returns
`not-started`, preserving its state and Herdr explanation fields. A returned
shell or vanished pane is a launch failure. Herdr
state recognition is authoritative: unrecognized trust/auth dialogs are not
inferred from terminal text. The command never sends keys, answers prompts,
retries a launch or cleans up resources. Inspect failures and escalate prompts.
**Started is not accepted**: acceptance remains the worker's first acknowledging
message to the coordinator. Keep that acceptance step separate.

Known limitation (live-qualified with Herdr 0.9.5, Pi manifest 2026.10.01.1):
Pi's project-trust UI is detected as `idle`, with
`fallback_reason=default_known_agent_idle_fallback` and `visible_blocker=false`,
not `blocked`. `not-started` plus the pane tail is the signal to inspect and
escalate this prompt; no trust response is automated.

Setup and standalone teardown default to the current directory. Setup preserves per-worktree
copies, isolated writable `.direnv`/`.devenv` state, and Git hooks. Declared
submodules initialize recursively, before shell warm-up. Warm-up failure is a
setup failure, not success with a warning. Rerunning setup is idempotent for
unchanged repository inputs; repository hooks must also be safe to repeat.

For a linked worktree of a submodule, setup's `worktree-config` step pins
`core.worktree` to that checkout's absolute path in its own
`<common-gitdir>/worktrees/<name>/config.worktree`, before Nix discovery or
submodule initialization. It enables `extensions.worktreeConfig` and leaves
the parent's shared `core.worktree` untouched, so later parent
`git submodule update` calls cannot redirect the linked checkout. Already-migrated
main `config.worktree` values from older helpers remain supported. The
`agentic:worktree-hooks` devenv task applies the same pin on every shell entry.
After updating agentic, rerun `workbench-worktree-setup --worktree <path>` for
an existing affected worktree; entering its shell also repairs the Git setting
if shell entry can reach the task. Setup is the recovery path when wrong Git
resolution prevents shell entry. Neither action repairs other worktrees.

Setup's early `fsmonitor` step disables `core.fsmonitor` only in the linked
worktree's `config.worktree`, then stops that checkout's running daemon before
Nix discovery, tolerating a stop race and waiting up to five seconds for exit.
Setup probes only `fsmonitor--daemon.ipc` in that linked worktree's gitdir:
a refused or missing connection permits removal of that stale socket only.
Removal logs the path to stderr and records it as `fsmonitor.staleSocketRemoved`
in `workbench-setup.json`. A live listener, non-socket file, or uncertain probe
fails setup at `fsmonitor` with the path, without removing it. Setup never touches
the `fsmonitor--daemon/` directory or another checkout's sockets.
Main checkouts, global fsmonitor settings, and `core.untrackedCache` are unchanged.
The shell-entry hooks task shares the config pin only, not daemon management;
rerun setup to stop an existing daemon before Nix evaluates the worktree.

LAB-178: a recursive `git reset --hard` before submodule initialization can
leave a config-only submodule gitdir. Setup detects this and fails closed at
`submodule-stub`, naming the path without changing the stub or its checkout.
For manual, data-preserving repair, move **both** that gitdir and the submodule
working directory to backups outside the worktree, inspect and preserve their
contents, then run `git submodule update --init --recursive` and rerun setup.
Never delete a stub blindly or reset a fresh worktree before setup. Earlier
Git discovery commands use command-local `-c submodule.recurse=false`; setup
never changes the caller's recursion policy.

Configure `workbench.worktree` (or `agentic.worktree`):

- `traits.submodules`: recursively initialize declared submodules (default false).
  If off while `.gitmodules` has entries, setup warns once naming
  `agentic.worktree.traits.submodules` and records `skipped: "trait-off"`;
  intentional opt-outs still succeed.
- `submodules.exclude`: exact top-level paths from `.gitmodules` to leave
  uninitialized (default `[]`), for example `["secrets"]`. Setup only passes
  non-excluded paths to recursive initialization, never cloning or recursing
  into an excluded path. It then verifies every selected top-level submodule
  is initialized and every excluded one is not. Missing initialization (even
  after a successful Git command), an initialized exclusion, or a Git error
  fails at `submodules`, listing affected paths. Existing excluded checkouts
  are not deinitialized or deleted; repair their state manually.
- `traits.secretDotfiles`: paths or shell globs copied, never shared (default empty).
- `copyFiles`: paths or shell globs copied when absent from the new worktree
  (default `[".envrc" ".claude"]`). Both lists expand against the main checkout,
  for example `[".env.*" "config/*.local"]`. Matching files retain their relative
  paths, with parent directories created as needed; existing destinations are
  skipped and patterns with no match are ignored.
- `setupHooks` and `teardownHooks`: ordered lists of shell command strings.
  Each runs in a separate strict Bash process with the worktree as cwd; changes
  to environment or cwd do not carry into the next hook. Reference packages
  through their store paths for reproducible dependencies. Hook names in
  diagnostics are zero-based, for example `setupHooks[0]`. Setup hooks run
  after the built-in preparation and must exit zero. Every teardown hook must
  exit zero **and** print a stdout line beginning `verified:`; any stdout
  containing `skipped` (case-insensitive) fails, even alongside a verification
  line. Hooks must verify actual resource absence, not merely command dispatch.
  A failure stops the runner; no declared teardown hooks succeeds with a note.

`agentic.worktreeLib.{setupScript,hooksScript,teardownScript,workerStartScript,removeScript} pkgs` exposes the
same runners and the Git-hook isolation helper. These are the supported APIs;
legacy creator-specific traits and copy options warn and redirect to them.
Legacy generation-only settings are ignored with warnings; delete them on a pin
bump. They no longer generate artifacts or affect coordinator behavior.
`agentic-worktree-setup` remains an executable alias. The Claude
`WorktreeCreate` hook and coordinator-created Herdr worktrees use the same
canonical setup command. No creator configuration is generated or installed.
The contributor shell also supplies all four runners from this repository's own
registry configuration.

#### Setup result and check codes

Setup atomically writes `workbench-setup.json` inside the target's own
`git rev-parse --absolute-git-dir`, including on failure after Git discovery.
It contains `status` (`ok|failed`), `failedStep` (string or null),
`warmUp` (`{status, exitCode}`, with status `not-run|skipped|ok|failed`),
UTC `startedAt`/`finishedAt` timestamps, and `setupCommand` (the canonical
executable's store path). `submodules` contains `configured` (the trait boolean),
`initialized` (observed initialized top-level paths in declaration order),
`excluded` (the configured exclusion list), and `skipped` (`null`, `"trait-off"`,
or `"no-gitmodules"`). Initialization is observed even after an update failure;
partial results remain visible in a failed record. When a preceding step fails,
initialization has not yet been observed and the list is empty. Failed setup
exits nonzero; invalid arguments exit 64. Check mode does not run setup or hooks:

| `--check [<path>]` exit | Meaning | Next action |
| --- | --- | --- |
| 0 | Current successful record | Continue observing actual harness readiness |
| 1 | Failed or malformed record | Investigate, then rerun setup |
| 2 | Missing record (or inaccessible checkout) | Run setup for the returned path |
| 3 | Record from a different setup store path | Rerun the current setup command |
| 4 | Not a linked worktree (a main checkout, or no repository) | Nothing; setup does not apply |

Every nonzero check prints one stderr line naming the worktree and its state;
codes 1–3 add the `workbench-worktree-setup --worktree <path>` action, and code
4 says setup does not apply, so a launcher can stay silent on it. A changed setup command
takes precedence over an older record's success/failure. These records do not
grant trust, prove mesh acceptance, replace native harness status or authorize
cleanup. Repository owners retain their safety flags and external-resource
lifecycle policy.

### Serena memory namespaces

Serena's `knowledge/` memories remain generated and read-only. Agent-written
memories belong in other topic subdirectories. To enforce that convention in a
consumer importing core's flake-parts module:

```nix
agentic.memoryPlane.namespaces = {
  require = true; # default false: existing root memories remain allowed
  allowRoot = [ "legacy-finding" ]; # default []; names without .md
};
```

This adds `checks.<system>.serena-memory-namespaces`, scanning the committed
source at `agentic.instructions.selfPath` (default: the consumer's `inputs.self`).
It lists every non-allowlisted `.serena/memories/*.md` directly at the root and
fails. Subdirectory memories, including the generated namespace, are unaffected.
Move a memory with Serena's `rename_memory` so `mem:` references stay valid;
this check never moves or deletes anything.

With the same opt-in, both flake-backed and devenv-native shells receive the
`serena-memory-namespaces` CLI via `devenvLib.packages`. Run it from the repo
root to check the live checkout; native consumers have no flake check.
`agentic.memoryPlane.lib.namespaceCheckScript pkgs` exposes the same gate for
other CI wiring.

### Skills

Core renders canonical bodies to `.claude/skills/<name>/SKILL.md` and discovery
wrappers to `.agents/skills/<name>/SKILL.md`. Consumers commit both projections;
`nix run .#write-agent-skills` refreshes them, and `agent-skills-drift` checks
for drift. Work tracking and memory join the library when their capabilities
are configured. Add repository-specific skills through `agentic.skills.library`.

The Herdr coordination skills are opt-in and default to off. In a consuming
flake-parts module that imports core's flake module, enable them with:

```nix
workbench.skills.coordination.enable = true;
```

The compatibility spelling `agentic.skills.coordination.enable = true;` selects
the same option. This adds `/worktree`, `/merge` and `/rebase`: coordinators
own Herdr worktree creation and teardown and reviewed, serialized integration;
workers may rebase their assigned branches but never merge their own work.
The skills use the repository's lifecycle runners and checks and refer to your
coordinator persona for escalation policy. They do not create a coordinator
persona or grant permission to merge or publish.

The coordinator procedure lives in the consumer's coordinator persona, its
single source of truth; core does not ship a `/coordinator` skill. The legacy
`/coordinator` and workmux-based `/merge`, `/rebase` and `/worktree` skills are
retired in favor of that persona and these opt-in skills. Remove stale legacy
copies from consumer and user skill directories when adopting the replacements;
the writer does not delete unmanaged skills. Core does not enable or commit
these skill projections for itself.

### Agent role projections

`agentic.agents.<name>` composes knowledge fragments, scope, capabilities, and
MCP requirements. Native model settings are optional: `claude.model` and
`claude.maxTurns`, `codex.model`, `codex.reasoningEffort`, and
`opencode.model`. Unset fields preserve harness defaults;
model/provider availability and authentication remain the operator's concern.

Use `agentic.modelProfiles.<name>` for reusable native model defaults and set
`agentic.agents.<name>.profile = "<name>";` to select one. Profiles accept
`claude.model`, `codex.model`, `codex.reasoningEffort`, `opencode.model`, and
`cotal.model`; each defaults to null. Non-null fields populate the existing
agent settings at `mkDefault` priority, so explicit per-agent pins win. Unknown
profile names fail evaluation with the agent name and defined profiles.
Agents without a profile are unchanged. This does not configure Cotal's runtime
`modelPolicy`.

```nix
agentic.modelProfiles.quick = {
  claude.model = "haiku";
  codex = { model = "fixture-small"; reasoningEffort = "low"; };
  opencode.model = "provider/small";
  cotal.model = "provider/small";
};
agentic.agents.reviewer.profile = "quick";
agentic.agents.builder = {
  profile = "quick";
  claude.model = "sonnet"; # Explicit pin overrides the profile.
};
```

The project bootstrap places Claude and OpenCode Markdown agents and Codex
standalone TOML agents. `nix run .#write-agent-roles` refreshes those directories
without the rest of shell bootstrap. Nonempty unmanaged directories are refused
rather than overwritten. Rendered farms are also available through
`agentic.agentsLib.{claudeAgentsDir,codexAgentsDir,opencodeAgentsDir} pkgs`.
Pi consumes the shared body as a prompt in its current session, not as a native
subagent or automatic model switch. Codex roles inherit their parent's sandbox;
capabilities are not a universal security boundary. Codex's launch-time reader
rejects individual role symlinks, so its directory contains regular TOML files.

`platforms` selects where an agent is rendered (default: the four harnesses).
An agent that lists `cotal` and sets `cotal.role` becomes a Cotal persona
(`.cotal/agents/<name>.md`): mesh identity and channel ACLs
(`cotal.{role,agent,model,tags,subscribe,allowSubscribe,allowPublish}`) in the
frontmatter. Tags combine `cotal.tags` with enabled `edit`, `exec` and `web`
capabilities, without duplicates. The persona body starts with bare fragment
text, then plain scope, required MCP server and capability sentences, without
a description line or headings. MCP references are validated even for Cotal-only
agents: undefined servers fail rendering and external servers warn.
`scope.delegateTo` must name registered agents on every platform.
Optional `cotal.escalateTo` names a registered Cotal agent with a role; the body
directs decisions and escalations to that role through roster lookup, since
presence names change on restart. `packages.<system>.cotal-personas` is the link
farm; the environment places it at its space root, since a persona catalog
belongs to a mesh, not a project. Neither MCP requirements nor escalation targets
are frontmatter keys. No Cotal control-plane capability (`spawn`, `run`) is
rendered: starting agents is the environment's launcher concern.

### CI cache profile contract

Environment layers may define `agentic.ciCache.profiles.{nix,rust,python}`.
Repositories request the ecosystems they use through
`agentic.ciCache.requestedProfiles`; the resolved, JSON-serializable contract
is available as `flake.agenticCiCacheContract` and
`config.agentic.ciCache.lib.contract` for the repository's own workflow
renderer. Core never creates a workflow or supplies endpoints and credentials.

The language templates request matching profiles, but those requests are
inert unless an environment layer defines them. This keeps the same templates
usable outside any particular organization and leaves out-of-shell packaging
unchanged.

Nix publication endpoints are split by trust tier: protected workflows may
write the authoritative cache, while pull requests may write only their
quarantine endpoint. The contract explicitly forbids protected substitution
from pull-request entries and direct promotion between the two tiers.

#### The cache client: `agentic-ci-cache`

Core also ships the consumer-side implementation of that contract. It is
one CLI, delivered two ways:

- **Standalone** — `packages.<system>.ci-cache` / `apps.<system>.ci-cache`
  (`nix run github:bryandph/agentic#ci-cache -- …`). No flake-module import
  is needed: the contract JSON is handed over at runtime through
  `AGENTIC_CI_CACHE_CONTRACT` (a file path, or inline JSON). This is the path
  for hand-written workflows and runner images.
- **Pre-wired** — `config.agentic.ciCache.lib.tools pkgs` returns the same
  binary with the resolved contract baked in (`lib.contractFile pkgs` is
  the JSON itself). Endpoints and variable *names* are public metadata; no
  secret value can enter the contract or the store.

Subcommands: `identity`; `nix config` (substituter lines for `NIX_CONFIG`,
never the quarantine); `nix publish <path>…` (bounded completed-closure
publication to the tier's endpoint); `sccache env` / `sccache run -- <cmd>`
/ `sccache stats`; `uv env` / `uv restore` / `uv publish`. Every cache
action exits 0 and prints one JSON report line (`outcome`, `detail`,
backend, repository, tier, identity) so failures are visible without
becoming build failures; `sccache run` execs the command and propagates
its exit status, degrading to an uncached build (`RUSTC_WRAPPER=""`, which
also overrides `.cargo/config.toml`) when configuration, credentials, or
the backend are unavailable.

Trust tier comes from Woodpecker's `CI_PIPELINE_EVENT` /
`CI_COMMIT_BRANCH` / `CI_REPO_DEFAULT_BRANCH` (or `AGENTIC_CI_TRUST_TIER`).
Credentials are read **only** from tier-prefixed variables,
`CI_CACHE_PROTECTED_<NAME>` and `CI_CACHE_PULL_REQUEST_<NAME>` (each with a
`_FILE` variant); a workflow mounts only its own tier, un-prefixed legacy
names are ignored, and a value found identical in both tiers is refused.
Cache keys carry the tier (`<keyPrefix>/<repo>/<tier>/…`) so backend
policies can scope each credential to its namespace.

What the Nix quarantine does and does not isolate: pull-request closures
are published only to the quarantine endpoint, the quarantine is never a
substituter for any tier, and promotion is rebuild-based (a protected
pipeline builds and publishes its own closures). It does **not** isolate a
pull request's builds from a shared lane store or daemon on the worker
itself — that boundary is the worker platform's, not this contract's.

Versioning: consumers pin a **tag or locked rev** (never an
implicitly-tracked branch). The API is 0.x until a second environment
consumes it; expect breaking changes between 0.x tags.

## Hosting

Primary: `git.bph/bryan/agentic` (Gitea). A GitHub push mirror is the
consumption channel for environments without access to the primary.
Verified 2026-07-15: the mirror is `github:bryandph/agentic` (public) —
`nix flake metadata github:bryandph/agentic` resolves and locks without
credentials, so a second environment consumes core exactly like any
public flake input (design Open Question 1 resolved: no work-side
mirror needed).
