## Why

On **2026-10-31**, **Bryan**, relayed by the operator seat, approved agentic-only retirement because **"mesh is Pi-only"**. This waives the qualification matrix (tasks 3.x) and the separate final retirement approval (4.6) for agentic only. It supersedes the earlier all-harness gate only within agentic. Removals in nixspace, home and finance remain requests to their owners; no package uninstall, profile removal or cross-repository change is authorized.

The original cross-repository plan below is historical context where it conflicts with this bounded waiver. Agentic now removes generation and retains creator-neutral setup, teardown and hooks. Legacy option definitions warn and redirect where equivalent; retired generation-only options give removal guidance. Other owners retain their own approval gates.

Authoritative work item: BPH-71, under BPH-11. This public change uses work item
IDs instead of private links.

Workmux manages Git worktrees, setup hooks, terminals, status, launch profiles
and integration. The current mesh workflow already uses Herdr worktrees and
panes with Cotal messaging. That path does not yet replace every setup hook or
prove that a harness accepted an assignment. Removing Workmux before those
checks pass would lose behavior and hide failures.

## What Changes

The operator settled the stage-0 decisions on **2026-10-25**:

- Retire Workmux for **all harnesses together**. Pi, Claude Code, Codex and
  OpenCode must qualify their launch paths and status reporting. No non-Pi
  consumer may retain a Workmux dependency after the retirement.
- Keep `/worktree` as a coordinator-run `herdr worktree create`. Keep `/merge`
  as the coordinator's reviewed merge. Workers never merge their own work.
- Assign G1 to agentic, G2–G4 to the infrastructure repository, and G5 to each
  repository that owns external resources.
- Keep the current Pi trust projection: each checkout and its repository
  worktree parent, with explicit denials preserved. A missing or failed
  projection only warns. It never blocks launch. A harness that then asks for
  trust has not accepted an assignment.
- Propose a watcher under G3/G4 that DMs the operator seat when coordinator work
  is held or expires, or a session stops consuming turns. The operator seat
  raises the problem with the operator. This includes provider rate limits.
- Cancel BPH-22 and BPH-32. The operator seat updates the tracker. Preserve
  their evidence; do not revive their forks or submit upstream work.

This commit also removes Workmux artifact promises from the active
`standardize-project-workbench` change. It adds deltas for the durable specs
that promise those artifacts. These are documentation changes, not runtime
implementation or removal of active tooling.

The plan gives each responsibility one owner. It separates installed Herdr
capabilities from repository tooling and the remaining gaps. Each stage has a
rollback path. Final retirement still requires qualification and separate
approval. [design.md](design.md) records the sources, owner map, watcher design
and gates. [tasks.md](tasks.md) separates completed planning from proposed work.

## Non-goals

This commit does not uninstall packages, change hooks or configuration, migrate
active sessions, implement the watcher, merge code or deploy services. It does
not grant global project trust or allow silent credential, model or billing
fallback. It does not approve remote-worker qualification or Hermes migration.
No resource may be adopted or force-removed when its ownership is uncertain.

## Capabilities

### New Capabilities

- `worktree-worker-migration`: one-owner workflow with startup checks, evidence,
  recovery, reviewed integration and staged retirement across all harnesses.

### Modified Capabilities

- `agentic-devenv`: remove the generated Workmux configuration requirement.
  Preserve creator-neutral setup, hook isolation and workflow bootstrap.
- `agentic-project-template`: remove the Workmux artifact promise from scaffold
  and adoption scenarios. Preserve the other workflow and build contracts.

The durable `agentic-agents` spec promises no Workmux artifact. It needs no
retirement delta. Its implementation and checks still contain Workmux-specific
worker guidance, which the migration must update.

## Impact

Reusable setup, checks, generated artifacts, templates and portable guidance
belong in agentic. Harness launchers, profiles, status integrations and shared
workflow delivery belong in the user's Home Manager configuration and the
infrastructure repository. Repository declarations and trust projection belong
in the workspace instance. Each repository keeps its safety rules, setup scripts
and database lifecycle.

This commit changes no runtime export. Later implementation affects
`agentic.workmux.*`, its `workbench` alias, `agentic.workmuxLib`, generated
`.workmux.yaml`, status resources and template contracts. Compatibility remains
only during the reversible migration. All four harness paths must pass before
the shared retirement. Each repository owner must approve and perform its own
removals. Removing declarative packages alone does not remove the separate
imperative user-profile install.

BPH-27 and BPH-59 provide messaging evidence. BPH-70 provides the existing CI
watch path. LAB-133 covers general process supervision. LAB-178 and FIN-62 remain
setup and cleanup gates. BPH-A-21 defines the mechanism, profile and instance
layers and the resolved workspace declaration.
