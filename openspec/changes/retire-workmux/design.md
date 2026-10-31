## Status and evidence boundary

On **2026-10-31**, **Bryan**, relayed by the operator seat, approved agentic-only retirement because **"mesh is Pi-only"**. This waives the qualification matrix (tasks 3.x) and the separate final retirement approval (4.6) for agentic only. It supersedes the earlier all-harness gate only within agentic. Removals in nixspace, home and finance remain requests to their owners; no package uninstall, profile removal or cross-repository change is authorized.

The original cross-repository plan below is historical context where it conflicts with this bounded waiver. Agentic now removes generation and retains creator-neutral setup, teardown and hooks. Legacy option definitions warn and redirect where equivalent; retired generation-only options give removal guidance. Other owners retain their own approval gates.

BPH-71 sits under BPH-11. The operator settled stage 0 on **2026-10-25**.
All harnesses retire Workmux together. This plan records those decisions and
proposes the implementation. It does not authorize changes to active tooling
or final retirement.

The commands below either verify capabilities or describe future procedures.
The audit needed no disposable lifecycle probes and ran none.

Sources read: BPH-71, BPH-11, BPH-22, BPH-32, BPH-27, BPH-59, BPH-70,
LAB-133, LAB-178, FIN-62 and BPH-A-21. Tracker claims are historical evidence,
not a substitute for installed-version verification or fresh acceptance tests.

### Installed capability baseline

`herdr --version` reports **0.9.5**. `workmux --version` reports **0.1.268**;
the installed package identifies fork revision **7e5e4e6**. These are different
identifiers, not two upstream release claims. Cotal orientation and bundled
`cotal_docs` report **0.91.0**. Recheck versions before implementation.

Herdr source citations below are relative to the installed package's source,
resolved read-only through `nix derivation show` for that binary. Consult that
source, not a checkout of another release. Its `Cargo.toml`, `src/cli/`,
`src/worktree.rs`, `src/app/api/worktrees/`, and bundled
`docs/next/api/herdr-api.schema.json` support the CLI observations:

| Evidence | Verified command / source and limits |
| --- | --- |
| H1: worktree lifecycle | `herdr worktree create --help`, `herdr worktree open --help`, `herdr worktree remove --help`, `herdr worktree list --help`. Create accepts `--cwd`, `--branch`, `--base`, `--path`, `--label`, `--no-focus`; remove requires `--workspace` and has explicit `--force`. `src/worktree.rs`: `default_checkout_path`, `branch_to_path_slug`, `run_worktree_add_command`, `build_worktree_remove_command`. Existing branches are reused, not reset to the requested base. Default path is configured root / repository name / branch slug; slashes become dashes, so the literal branch name need not equal the directory name. |
| H2: panes and inspection | `herdr pane run --help`, `herdr pane read --help`, `herdr pane list --help`, `herdr workspace --help`, `herdr agent get --help`, `herdr agent explain --help`, `herdr api --help`. Pane IDs target commands; read supports visible/recent/detection output. Workspace close is not worktree removal. `src/cli/pane/`, `src/cli/agent/`, and the bundled API schema define the native surface. |
| H3: startup and status | `herdr agent start --help` accepts `--kind pi`, `--kind claude`, `--kind codex` and `--kind opencode`, with `--pane <id> --timeout <ms>`. It starts at an interactive shell and reports detected input readiness, not Cotal assignment acceptance. `herdr agent wait --help` waits on idle/working/blocked/done/unknown. `herdr agent prompt --help` rejects already-blocked agents but explicitly does not track turns; an active turn can satisfy its wait. Do not use it for correlated mesh assignments. |
| H4: lifecycle reporting | `herdr pane report-agent --help`, `herdr pane report-agent-session --help`, `herdr pane release-agent --help`, `herdr pane report-metadata --help`; metadata is display-only. `herdr integration status` confirms the installed Pi integration v9 is current. Sources: `src/integration/assets/pi/herdr-agent-state.ts`, `claude/herdr-agent-state.sh`, `codex/herdr-agent-state.sh` and `opencode/herdr-agent-state.js` under the same assets directory. `src/detect/manifests/pi.toml` has working rules, not a project-trust readiness contract. The other harnesses need the same effective-integration checks; a source file alone does not prove delivery. |
| H5: events, not setup barriers | `herdr plugin --help`, `herdr plugin log --help`; source `src/api/schema/events.rs` includes `worktree.created/opened/removed`; `src/api/schema/plugins.rs` defines command event hooks. `src/app/api/plugins/runtime.rs::run_plugin_event_hooks` starts hook commands asynchronously; `src/app/api/worktrees.rs` tests created/removed events. There is no verified blocking repository setup/pre-remove veto equivalent here. Do not claim these events imply setup finished or permit irreversible cleanup. |
| H6: human attention and trust distinction | `herdr notification show --help` supplies a human toast, not a Pi wake or accepted assignment. `herdr worktree create --help` has `--trust-repository`; `src/worktree.rs::repository_git_args` implements request-scoped Git `safe.directory`. This is not Pi project trust or a direnv grant. |

Cotal sources are **bundled v0.91.0** pages retrieved through `cotal_docs`:
`presence-and-delivery`, `connect-pi`, `mcp-tools`, `workflows` (C1–C4 respectively).
C1 separates broker storage from receipt and completion. DMs can be delivered
more than once. Their durable inbox belongs to a lifecycle; a new seat with the
same name does not inherit it.

C2 describes provider-confirmed Pi delivery and bounded continuation followed
by a hold. Pi keeps its native JSONL session history. The page also describes
managed resume and restart. Those claims do not prove foreground recovery
without a manager.

C3 documents `cotal_dm` correlation through `replyTo`, connection diagnostics
and local reconnect. Connection `ready` means the connector consumes its queue.
It does not mean the harness accepted a particular assignment.

C4 provides durable run journals and a local-drive option. Hosted runs and
managed spawn or supervision need a manager. Today's deployment has none. This
plan does not add one or assume its APIs are available.

The audit also read bundled v0.91.0 `connect-claude`, `connect-codex` and
`connect-opencode` (C5–C7). Claude Code has hook and channel paths; channel
policy can prevent idle wake even when tools work. Codex and OpenCode refuse
Cotal `spawn --resume` in this release. OpenCode also has version-specific event
limits. These are qualification constraints, not reasons to retain Workmux for
those harnesses. Each harness must prove its actual foreground path and native
continuation or use the explicit replacement procedure.

## Today's practice before mapping

A coordinator writes a self-contained assignment, then uses
`herdr worktree create --cwd <repo> --branch <branch> --base <base> --label <worker> --no-focus`.
It records the returned workspace, checkout path and root pane ID. It does not
guess them from a handle. Worktrees live under the workspace root's `.worktrees/`.
The coordinator runs `herdr pane run <pane> "exec pi-worker -n <worker> -C <checkout> --prompt-file <assignment>"`
and uses `herdr pane read <pane>` for inspection. Removal is
`herdr worktree remove --workspace <id>`, only after review and reconciliation.
Shell command syntax must match the pane's actual shell; do not reuse POSIX
quoting assumptions blindly.

The infrastructure repository defines `pi-coord`, `pi-worker`, `pi-mesh` and
`pi-seat` as foreground Cotal launches of registry-rendered personas. The seat
launcher is declared but was not present on PATH at audit time; activation is
not proved by source existence. Default names combine the role, directory
basename and a random suffix. The launcher also accepts explicit names and
reads prompt files. Cotal's spawn allow-list forwards the Herdr pane variables
so native Pi status and blocked-input reporting still work.

Plain Pi remains independent. Existing launch and harness configuration owns
profile and model policy. A new dispatcher must not choose an implicit fallback.

The workspace instance's `pi-trust` projects resolved workspace entries into
Pi trust for each checkout and its repository-specific worktree parent. It
merges only absent decisions, preserves explicit false entries, supports a dry
run, and warns rather than failing shell activation. This is narrower than
global auto-trust. The operator confirmed this scope on 2026-10-25. A missing
or failed projection only warns. It never blocks launch. If Pi then shows its
trust prompt, the process has launched but has not accepted an assignment.
Use the resolved form specified in `openspec/specs/workbench-workspace/spec.md`;
portable core must not acquire instance paths or write personal trust decisions.

Workers DM results, blockers and questions to their coordinator. The coordinator
DMs decisions to the operator seat. The seat asks the operator.

Repository coordinators review the evidence and run checks. They merge one
branch at a time within their authorized repository scope. They report the
merge and post-merge CI. They coordinate cross-repository changes with the
owners. No skill grants a worker permission to merge or deploy.

The operator confirmed the vocabulary on 2026-10-25. `/worktree` means the
coordinator runs `herdr worktree create`. `/merge` means the coordinator performs
a reviewed merge. Workers never self-merge. Rewriting the legacy `/coordinator`
and operator merge/rebase skills is a proposal for approval. The rewrite must
remove self-merge defaults and must not carry `--no-verify` forward as a workflow
bypass.

## Capability and ownership map

Each row has **one accountable replacement owner**. Dependencies in the evidence
column are not competing lifecycle authorities. G1–G5 are deliberately small
missing contracts, not verified replacement capabilities.

| Responsibility | Workmux today and source | Exactly one replacement owner | Qualification / disposition |
| --- | --- | --- | --- |
| Worktree naming, placement and base selection | Shared `/worktree` and `/rebase` skills; generated `main_branch`, optional model `auto_name`; branch-local `workmux-base` used by `/merge` | Native Herdr (H1) | Pass explicit branch/base/cwd; record resolved path and base in assignment. Check existing-branch behavior and slug collisions. Retain reading legacy base metadata during transition; do not invent automatic base guessing. |
| Model-generated branch names | `_workmux.nix::autoNameModel/autoNamePrompt` | Deliberately retired | Explicit issue/branch naming is sufficient; no extra model invocation or fallback just to name a branch. |
| Submodules and setup execution | `_workmux.nix::setupScript`, generated `post_create`, bootstrap Claude WorktreeCreate hook; repository-specific hooks | G1: setup barrier, owner agentic | Reuse existing script as one setup implementation for every creator, with an explicit success or failure result before any harness starts. Herdr event hooks alone do not supply it (H5). LAB-178 and FIN-62 require fresh fixtures, not manual deletion recipes. |
| Environment, caches and copies | Setup probes flake discovery, trait-keyed init, copies declared files, repairs legacy state links, grants direnv, warms shell; per-worktree hooks helper | Existing repository tooling | Keep per-worktree `.direnv`, `.devenv`, service state and hooks; Nix store is the shared cache. Never share writable state or expose copied sensitive values. Warm-up warning is not success. Preserve repository safety flags and state provisioning before claiming ready. |
| Agent launch and profile selection | `agent`, global named profiles, `<agent>` panes, workmux launch/argument handling | Existing Home Manager launchers | Use the existing Pi foreground persona launchers as evidence, not a universal wrapper. Qualify approved launchers for Pi, Claude Code, Codex and OpenCode. Preserve explicit model and provider choice and direct native use. Herdr executes the selected command; it does not own another profile registry. All Workmux profiles retire together after all four paths pass. |
| Pane targeting and terminal lifecycle | Fork backend, workmux handles and cross-project fallback, `open/close/run/capture` | Native Herdr (H2) | Exact workspace/pane IDs and checkout binding; no ambiguous basename fallback or terminal assignment injection. Native pane run does not promise workmux run's captured exit/result contract. |
| Status and inspection | `set-window-status`, pinned status resources, `status/capture/wait`, dashboard | Native Herdr (H2–H4) | Preserve native status and blocked-prompt reporting for all four harnesses. Check the pinned integration source and the effective hook delivery for each. Inspect Git and check evidence independently. Idle, done, display metadata and notifications do not prove task completion. |
| Pre-model trust/auth/setup readiness | Workmux launch/status can show idle or no active agent before trust is answered; BPH-71 failure | G2: pre-model readiness, owner infrastructure repository | Trust projection only warns and never gates launch. After launch, require the setup result, exact pane and session, live connector and correlated acceptance before work starts. Observe an actual trust prompt or other blocker without requiring project extensions or a model. Roster presence does not prove readiness. |
| Assignments, questions and follow-ups | `/coordinator` sends terminal text; BPH-32 records blocked-prompt send rejection | Cotal (C1–C3) | Unique peer incarnation; message IDs plus assignment/attempt IDs and `replyTo`; broker storage is not acceptance. Duplicate delivery must not start duplicate work. Questions traverse coordinator → operator seat → coordinator → worker. |
| Harness session continuation | Workmux send/wait and skills; optional fork ancestry | Existing native harness sessions | Each harness owns its transcript. Prove the same session and attempt after foreground reconnect. Pi's managed restart claim in C2 is not assumed. C6/C7 refuse Cotal resume for Codex/OpenCode; qualify native continuation separately or fence and replace explicitly. A new same-name peer does not inherit an inbox. Fork needs explicit selection and proof of supported history inheritance. |
| Held-delivery recovery | Workmux status did not expose accepted-delivery semantics | G3: recovery reconciliation, owner infrastructure repository | Inspect the connector queue and native session. Preserve attempt ownership; reconnect may leave a steer held. The G3/G4 watcher below escalates held or expired coordinator work and sessions that stop consuming turns, including rate limits. Fence old work before replacement and relay unresolved work explicitly. Do not resend blindly or create a duplicate worker. |
| Durable multi-stage coordination journal | Workmux status/wait and ad hoc coordinator context | Cotal (C4) | Only if a durable multi-stage run is selected: use the existing local run path and journal, not a second custom engine or a hosted-manager assumption. Ordinary one-assignment work need not gain a workflow. Pi keeps reasoning/session history; Git keeps code history. |
| CI continuation | Workmux wait plus blocking/detached monitoring patterns (LAB-133) | Existing CI-watch integration (BPH-70) | Exact-head, bounded background watch and correlated wake; no in-turn sleep loop. General long process supervision remains G4, not magically solved by CI watch. |
| Long-running local process result | `workmux run` captured output/exit and timeout; detached wait workaround | G4: process supervision, owner infrastructure repository (LAB-133) | Qualify owned process handle, bounded output, exit, cancellation, orphan recovery and session wake before retiring this use; Herdr run/notification is not parity. |
| Review, rebase, merge and pre-merge gates | `_workmux.nix::preMerge/mergeStrategy`, dashboard merge command, shared `/merge` and `/rebase` | Existing repository coordinator tooling | Explicit base/HEAD, reviewed diff, independent checks and applicable authorization. Use Git integration, serialize it, rerun after rebase; never preserve skill bypass flags as default authority. |
| Worktree and workspace removal | Workmux merge/remove cleanup and repository `pre_remove` | Native Herdr (H1) | Remove by verified workspace ID only after G5 succeeds and sessions stop. Keep branches/evidence on failure. No implicit force; submodule removal may require a separately approved action. |
| Repository external-resource cleanup | Repository `pre_remove` database cleanup and safety-sensitive hooks | G5: cleanup barrier, owner each repository with external resources | Run and verify repository cleanup before Herdr removal; failing cleanup vetoes removal. Native removed events are too late. Existing cleanup can exit successfully when its backing service is unavailable, so an exit code alone is not proof external resources were removed. Disposable tests must cover initialized submodules and preserved dirty/ambiguous trees. |
| Generated configuration and compatibility | `_bootstrap.nix` emits real `.workmux.yaml`; module aliases, templates and baseline checks | Existing agentic repository tooling | Add creator-neutral setup export/checks before deprecating old options; migrate both transports and templates coherently. Remove generator only after consumers pass, with an explicit option migration and rollback pin. |

## Source and disposition index

This index points to migration sources. It is not a saved workspace or status
snapshot. The coordinator handoff holds exact environment paths. Historical
archives remain evidence, not active consumers to edit.

### Core paths (repository-relative)

| Paths | Current role | Proposed disposition |
| --- | --- | --- |
| `modules/registry/_workmux.nix`, `modules/registry.nix` | Options, YAML, setup and per-worktree hook helper; registry import | Extract creator-neutral setup/hooks additively; retain compatibility until final approved removal. |
| `modules/registry/_bootstrap.nix`, `devenv.nix` | Shell-entry YAML placement; native/flake setup and Claude hook wiring | Keep setup and hook isolation in both transports; stop YAML only after consumer migration. |
| `modules/checks/workmux.nix` | `workmux` generation/setup and `workmux-worktree-hooks` linked-submodule fixtures | Preserve semantic assertions under replacement names, including core.worktree migration and idempotence; do not delete coverage with package naming. |
| `modules/checks/public-surface.nix` | Baseline Workmux artifact parity across exports/aliases | Add replacement setup parity before removing baseline YAML; publish breaking export migration explicitly. |
| `modules/registry/_agents.nix`, `modules/checks/agents.nix`, `modules/adapters/agents.nix` | Pi role text/assertion says workmux owns workers; adapter boundary comment | Replace assertion/text with single-owner external-worker contract; keep roles as ordinary Pi prompts, not native subagents. |
| `modules/templates.nix`; `templates/{default,embedded,polyglot,python,rust,adopt}/flake.nix`; matching `.gitignore` (adopt: `.gitignore-additions`) | Advertise Workmux traits/artifacts and ignore generated YAML | Migrate all template comments/contracts and ignores after generator stops; do not hand-edit generated files. |
| `docs/pi.md`, `docs/harness-coverage.md`, `docs/native-transport.md` | Worker ownership and transport artifact guidance | Document Herdr/Pi/Cotal boundaries and retained compatibility accurately. |
| `openspec/specs/agentic-devenv/spec.md`, `openspec/specs/agentic-project-template/spec.md`; `openspec/changes/standardize-project-workbench/` | Existing artifact and setup promises | This commit removes Workmux promises from the active Workbench change and adds durable-spec deltas. Keep one writer during implementation. Existing spec cache-symlink wording is stale: current code never shares writable state. Preserve that safety rule. |

### Other consumer owners (repository names only)

| Owner | Audited consumer class | Proposed disposition, subject to that owner's approval |
| --- | --- | --- |
| nixspace | Fork flake input/lock, overlay, home input following, workstation enablement, generated YAML/render export, traits, hook reconciliation fixtures, knowledge fragments, maintenance registry/skills, permission allow-list, Pi portability extension and tests, launchers/personas | Keep launchers and native integration; migrate skills/status/tests; remove input/package/config only after dependent profile and repository slices pass. Preserve unrelated telemetry/sounds/MCP behavior in wrappers. |
| home | Standalone input/lock and presets/configurations; typed Workmux module; pinned cross-harness hook resources; Pi status extension and UI bridge; hook/sound tests, documentation, terminal restoration list | Decouple native Herdr state/UI-blocked reporting from Workmux resources first. Preserve sound suppression and native integrations for every harness. Remove Workmux options, resources, package delivery and the obsolete restoration entry only after all four harness paths pass. There is no non-Pi exception. |
| finance | Checkout YAML, launch profiles, recursive submodule setup, per-worktree database provisioning/cleanup and worker safety | Preserve safety and external state isolation with repository-owned barriers. FIN-62 and initialized-submodule cleanup are mandatory gates. |
| portfolio-balancer | Checkout YAML launches repository worker wrapper with safety/setup behavior | Preserve guardrails; migrate wrapper invocation without importing its policy into core. |
| nixos-boards | Checkout YAML provides agent-only pane layout | Native single-pane worker path replaces this config after a smoke test. |
| bph | Workspace declaration, placement, scoped Pi trust projection and operating guidance; no checkout Workmux YAML found | Keep resolved declaration as source of paths; validate trust projection and launch readiness. No global trust expansion. |

### User-profile package outside declarative configuration

Read-only `nix profile list` confirms a separately installed `workmux` user-profile
entry. `readlink -f` of the selected PATH binary resolves to the fork package
identified above. This imperative profile install is independent of Home Manager
and the infrastructure repository's declarative package configuration. Removing
the declarative package or input does **not** remove the user-profile entry or
its PATH precedence. Proposed owner: the operator's environment. At stage 5, after
separate approval and active-attempt reconciliation, remove that specific profile
entry. Verify PATH resolution in a fresh shell. Preserve the exact store
reference for an approved rollback. Do not run a general profile cleanup or
remove unrelated generations or packages. The coordinator handoff holds the
exact profile and store paths; this public plan does not.

The installed binary and user extension delivery are environment consumers, not
files for core to remove. Checkout searches excluded archived clones. The plan
does not revive or change archived forks. Operator-owned shared
`worktree`, `coordinator`, `merge`, `rebase` and `workmux` skills remain external
compatibility consumers until their owner approves updates. They currently
contain tmux assumptions, terminal sends, Workmux base metadata, fork claims,
worker self-merge and verification bypass options. The infrastructure
repository's shared-workflows extension loads them dynamically and injects
portability guidance, so migrating only a copied skill body would not suffice.

## Operator decisions and rationale

The operator made these stage-0 decisions on **2026-10-25**. They settle the
scope questions, not implementation or final-removal approval.

1. **All harnesses retire together.** Pi, Claude Code, Codex and OpenCode share
   the retirement gate. Their status hooks, skills, Workmux profiles, registry
   entries and checks leave in the same retirement. This decision supersedes
   BPH-71's earlier Pi-first rollout direction. Temporary compatibility supports
   rollback before that gate. It is not a non-Pi carve-out.
2. **Keep the vocabulary.** `/worktree` is the coordinator's Herdr creation
   command. `/merge` is its reviewed merge. Workers never self-merge. Proposed
   rewrites of `/coordinator` and the operator merge/rebase skills must follow
   that rule and remove the legacy verification bypass defaults.
3. **Keep the proposed owners.** Agentic owns G1. The infrastructure repository
   owns G2, G3 and G4. Each repository owns G5 for its external resources. This
   avoids both a replacement monolithic manager and competing lifecycle owners.
4. **Trust projection only warns.** Keep the checkout and `.worktrees/<name>`
   scope. Preserve explicit denials. Missing or failed projection never blocks
   launch. An actual harness trust prompt still prevents assignment acceptance
   until the operator resolves it. Herdr Git trust is not harness trust.
5. **Escalate to the operator seat.** A watcher DMs held or expired coordinator
   work and sessions that stop consuming turns, including a provider rate
   limit. The seat raises the problem with the operator. G3/G4 own the observer
   and its process lifecycle; the design below gives the proposed contract.
6. **Cancel the fork work.** BPH-22 and BPH-32 are cancelled. The operator seat
   handles the tracker updates. Keep the historical evidence. Remove Workmux
   artifact promises from the active Workbench change in this commit and add
   the durable-spec deltas here. No upstream submission follows.

Herdr owns worktrees and terminals. A second Git/workspace manager would
repeat that authority. G1 instead calls the existing setup entrypoint and
waits for its result. A plugin is an alternative only if it uses that same
implementation and waits for completion. An asynchronous created event is not
such a barrier. The new public export name remains an implementation detail
for review.

Readiness needs affirmative evidence. The proposed qualification labels are
allocated, preparing, blocked, connecting, ready-for-assignment, accepted,
working, result-reported, reviewed and cleanup-eligible. These are not new Herdr
or Cotal protocol states. Keep the underlying observations separate.

A prior seat retained automatic deliveries with “Pi ended before confirming a
queued Cotal steer”. Reconnect did not release them, and the seat was replaced.
This is reported practice, not a probe run during this audit. Keep the queued
count, oldest delivery, last queue commit and held reason visible where the
connector exposes them. A healthy transport and heartbeat do not release the
attempt's ownership.

Each harness keeps its native reasoning and session history. Cotal owns messages
and any selected durable coordination journal. Git and repository artifacts
hold code and evidence. A small attempt binding may record resource IDs and
references. It must not become a shadow transcript or workflow engine.

Foreground launches and Herdr remain explicit. Cotal's managed spawn and stop
APIs are not today's lifecycle mechanism. Loading a skill does not grant new
permission to dispatch, bypass checks, merge or deploy.

## Proposed G3/G4 watcher

The infrastructure repository supplies a bounded, non-LLM watcher process. Its
host launch tooling starts the watcher with the coordinator seat. The invoking
coordinator or operator seat registers each supervised assignment binding and
its deadlines. Starting observation must not depend on the supervised model
finishing a turn. G4 owns the process handle, cancellation, exit evidence and
orphan reconciliation. The watcher runs outside model turns and project
extensions, so a rate-limited or stopped coordinator cannot prevent observation.

The watcher takes the existing attempt binding and absolute deadlines. It
reads that binding after restart rather than creating workers or a new journal.
It uses bounded reads with backoff. It never extends a deadline because presence
is fresh. Cancel it only after the attempt is reviewed, explicitly abandoned
or transferred through the recovery contract.

The watcher observes three sources:

- **Connector diagnostics.** Read connection state, queued automatic-delivery
  count, oldest queued delivery, last queue commit and explicit held reason.
  Detect a queue that makes no progress across the attempt's declared stall
  budget. `cotal_connection_status` describes a session-local surface; a host
  process cannot assume it can call that tool remotely. G3 must expose a narrow,
  read-only diagnostic snapshot from the existing connector or reuse an
  authenticated observer surface that actually supplies those fields. If the
  version cannot supply one, report observation as unavailable. Do not infer a
  healthy queue from presence.
- **Harness and pane state.** Read the bound pane with Herdr and use its native
  agent state and session identity. Use explicit connector or harness conditions
  for provider rate limits, input requests and held delivery. Native session or
  event evidence may confirm that a turn started or ended. Terminal text can
  support human inspection, but cannot prove task acceptance or completion.
  Missing turn evidence at the accepted-response deadline is an escalation,
  not a claim that the worker is dead. Do not add a heuristic continuation guard.
- **Assignment and run deadlines.** Read the accepted assignment's deadline and,
  when a durable run exists, its authoritative Cotal journal. An expired or held
  run needs attention even if the pane looks idle. A released run is held for
  reconciliation, not automatically completed or failed.

On the first relevant transition, the watcher sends a Cotal DM to the bound
operator-seat coordinator. It resolves that seat through the current roster
and verifies the intended supervisor binding. It does not guess among multiple
seats or send to an unrelated same-name replacement. If the binding is stale
or missing, retain the unresolved escalation in the existing attempt evidence
and raise a Herdr human notification. Report the routing blocker; a toast does
not count as the required DM or as a Pi wake.

The proposed DM carries a bounded record in plain text. It contains no terminal
dump, credential or sensitive file value:

```text
kind: coordinator-attention
escalation_id: <attempt-id>:<reason>:<observation-sequence>
assignment_id: <assignment-id>
attempt_id: <attempt-id>
coordinator: <peer-name and incarnation>
session: <native harness and session-id>
workspace: <workspace-id>
pane: <pane-id>
reason: <delivery-held | queue-stalled | deadline-expired | rate-limit | input-required | observation-unavailable>
observed_at: <timestamp>
deadline: <absolute deadline, if applicable>
evidence: <bounded queue and pane observations plus evidence references>
action: Ask the operator to inspect or decide recovery; do not resend, replace, merge or deploy automatically.
```

The operator seat raises the DM with the operator and returns any decision
through the coordinator. The watcher uses a stable escalation ID for retries
and correlates replies to the original DM. Cotal storage proves only that the
broker stored it. The watcher keeps the notice unresolved until the seat
acknowledges it or the operator reconciles routing. Duplicate delivery must not
repeat recovery actions. The watcher reports observations; it cannot resume a
model, answer a trust dialog, launch a replacement or change authority.

Qualification must stop a coordinator on a provider rate limit, hold a queued
steer, expire a deadline, stop the observer and restart it, and replace the
operator-seat binding. Each case must reach the correct operator seat once
logically, with duplicate transport delivery tolerated. An unavailable observer
must produce a visible failure, not silently pass the retirement gate.

## Stages and qualification gates

Stop a stage when its evidence is uncertain. Keep the current package, input
and configuration pins until final removal is approved. Keep active ownership
records throughout. Rollback changes future launches only. Never recreate or
delete a live resource to roll back.

| Stage | Bounded action after approval | Exit evidence | Reversal |
| --- | --- | --- | --- |
| 0: decisions recorded | Record the operator's 2026-10-25 decisions: all harnesses together, coordinator vocabulary, gap owners, warning-only trust projection, watcher escalation and cancellation of BPH-22/BPH-32. Remove conflicting Workbench artifact promises. | Decisions and spec deltas reviewed; version evidence refreshed. Documentation approval is not implementation approval. | Revise the plan through an explicit operator decision. Active tooling stays unchanged. |
| 1: additive barriers | Core exposes the existing setup and hook helpers without a creator dependency. The infrastructure repository adds G2–G4, including the watcher. Each owner adds G5. Prepare launch and status paths for all four harnesses. | G1–G5 fixtures pass. Setup finishes before launch. Trust projection failure only warns. Actual harness blockers remain visible before model execution. Direct native use still works. | Use the previous exports and configuration for future launches. Retain replacement trees and evidence for inspection. |
| 2: disposable qualification | Use isolated throwaway Git repositories under a temporary directory. Prevent user-layout restore. Run the full harness matrix, two-worker routing, watcher and recovery cases below. | Record exact commands, versions and resource IDs. Each launch and status path passes. No duplicate workers or cross-routing occur. Verify fixture cleanup. | Stop fixture launches. Reconcile and remove only owned fixture resources. Preserve unknown or dirty state. |
| 3: useful change | Selected repository coordinator drives one real authorized change from assignment through implementation, verification, independent review, fix/follow-up and serialized integration | Commit/diff and check evidence independently inspected; operator question round trip; required CI and post-merge observation; no automatic deploy | Stop rollout and use prior path for future work; normal reviewed revert if code rollback is needed, never rewrite integration history |
| 4: consumer flip | Each owner migrates its skills, profiles, registry entries, generated configuration, status resources, templates and checks. Keep a rollback pin until the shared gate passes. | Every identified consumer runs without Workmux on PATH. Pi, Claude Code, Codex and OpenCode all pass. No runtime import, command, profile or status hook retains a Workmux dependency. There is no non-Pi exception. | Restore the previous pins and configuration for future launches. Do not steal active sessions. |
| 5: retirement | Seek separate operator approval. Each owner removes its unused Workmux package, input, configuration and hooks in the same all-harness retirement. The operator separately removes the imperative user-profile entry; declarative removal does not remove it. | All acceptance gates pass for every harness. No consumer or active attempt needs Workmux. A fresh-shell PATH check finds no remaining Workmux binary. Record approval and evidence references. | Restore the last known-good pins and the exact user-profile package for future launches if approved. Preserve historical refs and active branches. |

### Reproducible qualification cases

For future fixtures, record repository identity, exact base and HEAD, workspace
ID, pane ID, checkout path, native harness session ID, peer incarnation,
assignment ID, attempt ID and message/reply IDs. A name alone is insufficient.
Bound every wait. Preserve failure evidence. Terminal output alone does not
prove that a harness accepted a task.

Run the common cases below for **Pi, Claude Code, Codex and OpenCode**. Record
installed harness and connector versions for every row. No row may pass on
source existence or another harness's result.

| Harness | Launch and status qualification | Recovery and blocker qualification |
| --- | --- | --- |
| Pi | Use the existing foreground persona launcher. Verify forwarded Herdr environment, native v9 status integration, UI prompt bridge, exact session and correlated acceptance. Remove the Workmux status extension only after replacement evidence passes. | A missing or failed trust projection warns and launch proceeds. A real trust prompt remains unaccepted work. Test held steers, provider rate limits and same-session reconnect without relying on managed restart. |
| Claude Code | Qualify its approved foreground command, explicit profile and model choice, native Herdr hook delivery, and Cotal hook/channel path (C5). Preserve the configured approval mode. | Test trust and permission prompts before model work. Prove idle delivery under the actual channel policy. A connected tool or hook alone is not proof of idle wake. Test rate limits and native session reconciliation. |
| Codex | Qualify its approved launch and sandbox profile without `profiles.workmux`. Replace the pinned Workmux hook resource while preserving native Herdr reporting and other composed hooks. | Test approval and authentication blockers, sandbox write limits and rate limits. C6 refuses Cotal spawn resume; prove the native route or use fenced replacement. Do not retain a Workmux profile to avoid the test. |
| OpenCode | Qualify its approved foreground command, chosen model, native Herdr plugin and Cotal plugin path (C7). Remove the Workmux plugin only after status and prompt evidence passes. | Test permissions, authentication, rate limits and idle delivery on the installed OpenCode line. Honor that line's event limits. C7 refuses Cotal spawn resume; qualify native continuation or fenced replacement. |

- **One worker:** create with explicit cwd/branch/base/label/no-focus; complete
  setup; launch a named worker for each harness; prove its connector and accepted assignment in the
  exact session. DM question with ID, route through coordinator/operator seat,
  return answer and follow-up, verify worker's resulting artifact with tools.
- **Startup failures:** untrusted checkout, preserved explicit denial, expired
  harness auth, failed setup, missing dev shell and dialog before extensions
  load. Observe blocked/unknown and notify the coordinator/operator; no
  keystroke trust bypass, terminal assignment injection or model fallback.
  Separately omit or fail Pi trust projection and prove that launch still runs
  with a warning. This warning is not an assignment blocker by itself.
- **Two workers:** distinct writable checkouts and peer/session bindings;
  interleave uniquely tagged assignments/questions/follow-ups, including one
  busy worker. Cover each harness and mixed-harness pairs across the matrix. Each artifact/reply must match its own attempt; no cross-routing,
  shared writable state, accidental global handle fallback or duplicate launch.
- **Recovery:** disconnect/reconnect same live session, restart coordinator,
  worker process exit, duplicate/redelivered message, stale roster, lost create
  reply and held automatic delivery. Reconcile actual Herdr/Git/session state
  before retry. Resume the same owned session where supported; if replacement
  is necessary, fence/stop the old attempt first and explicitly transfer only
  unresolved work. Offline DM storage is not proof a replacement inherited it.
- **Watcher:** hold delivery, expire coordinator work and stop turn consumption
  on a provider rate limit. Prove the G3/G4 observer DMs the bound operator seat
  and the seat raises the issue with the operator. Restart the observer and
  test stale supervisor routing without duplicate recovery or new workers.
- **Repository setup:** fresh parent repo with recursive submodule settings,
  linked worktree of a submodule, initialized submodule cleanup and repeated
  shell entry. Reproduce LAB-178's config-only gitdir and FIN-62 hook-config
  failure in fixtures; identify cause rather than assuming native Herdr owns
  submodule setup. No manual deletion workaround becomes automatic migration.
  Use inert fixture files instead of live sensitive material; prove copy-not-
  share, correct hook directory, isolated service state, safe-mode policy and
  explicit warm-up failure. Re-enter and remove one fixture tree without
  breaking another's hooks.
- **Cleanup:** clean, dirty, untracked, initialized-submodule, cleanup-failed,
  unknown-owner and partial-create fixtures. Repository pre-remove failure
  vetoes removal; dirty/ambiguous state is retained, not forced. Verify external
  fixture resources are gone, Herdr workspace no longer owns the tree, and
  unrelated sessions/branches/files are unchanged. Report every probe and
  remove all owned temporary resources.
- **Checks and gates:** retain format, local-system evaluation, targeted checks,
  CI policy and independent review. Rebase changes require fresh HEAD evidence.
  Failed checks, expiry, idle/done or stored messages never authorize integration.
  Prove direct Pi, Claude Code, Codex, OpenCode and Herdr still work without the mesh.

## Approval boundary

The 2026-10-25 decisions close the stage-0 questions. Implementation remains a
proposal. Each owner must review its code changes and skill rewrites. Final
removal requires a separate operator approval after every harness passes.
Do not treat this document, a complete task list or a cancelled fork issue as
permission to change active tooling.
