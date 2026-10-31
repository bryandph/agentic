## 1. Planning and recorded decisions

- [x] 1.1 Read BPH-71, its related work items and BPH-A-21. Inspect installed versions, help, source and current consumers without changing active tooling.
- [x] 1.2 Record the owner map, gaps, source index, layers, reversible stages and qualification gates.
- [x] 1.3 Record the operator's stage-0 decisions dated 2026-10-25. All harnesses retire together. Keep coordinator-safe `/worktree` and `/merge`. Confirm G1–G5 owners, warning-only Pi trust projection and watcher escalation to the operator seat.
- [x] 1.4 Record cancellation of BPH-22 and BPH-32. The operator seat handles tracker updates. Preserve evidence and do not revive the forks.
- [x] 1.5 Remove Workmux promises from the active `standardize-project-workbench` proposal, design, tasks and delta specs. Keep its unrelated content unchanged.
- [x] 1.6 Add MODIFIED and REMOVED deltas for `agentic-devenv` and MODIFIED deltas for `agentic-project-template`. Confirm that durable `agentic-agents` has no Workmux artifact promise and needs no delta.
- [x] 1.7 Run the documentation gates in section 5 and hand the amended commit to the coordinator. Stage-0 decisions do not approve runtime implementation or final removal.

## Agentic-only waiver

On **2026-10-31**, **Bryan**, relayed by the operator seat, approved agentic-only retirement because **"mesh is Pi-only"**. This waives the qualification matrix (tasks 3.x) and the separate final retirement approval (4.6) for agentic only. It supersedes the earlier all-harness gate only within agentic. Removals in nixspace, home and finance remain requests to their owners; no package uninstall, profile removal or cross-repository change is authorized.

Tasks 3.1–3.10 and 4.6 remain unchecked as waived, not executed. Tasks 4.1 and 4.2 are completed by this branch; verification is recorded after execution. Durable spec sync and archival remain with the coordinator (5.4).

## 2. Proposed additive implementation

These tasks need implementation review and approval. They do not authorize
changes in another owner's repository.

- [x] 2.1 In agentic, expose the existing setup and hook helpers without a creator dependency. Keep compatibility aliases until the shared retirement gate passes. Preserve both transports, the Claude hook and per-worktree hook isolation. Add G1's explicit setup result before harness launch.
- [ ] 2.2 In the infrastructure repository, add G2's pre-model observations around approved launchers for Pi, Claude Code, Codex and OpenCode. A missing or failed Pi trust projection only warns and never blocks launch. A real trust, authentication or input prompt still prevents assignment acceptance.
- [ ] 2.3 In the infrastructure repository, add G3's attempt and session reconciliation. Preserve the native harness history, Cotal messages and any selected durable run journal. Fence an old attempt before replacement. Do not assume Cotal resume support for Codex or OpenCode.
- [ ] 2.4 Propose the G3/G4 watcher in design.md. Run it outside model turns with G4 process ownership. Observe connector queue progress, held delivery, native pane state, explicit harness conditions and deadlines. DM the bound operator-seat coordinator on held or expired work or stopped turn consumption, including provider rate limits. The seat raises the issue with the operator. Keep the proposed DM fields, reply correlation and duplicate handling.
- [ ] 2.5 Under LAB-133, qualify G4's process handle, bounded output, exit evidence, cancellation, orphan reconciliation and wake behavior. Do not treat pane execution, a toast or CI watch as a general process contract. Do not create a second journal or manager.
- [ ] 2.6 Request G5 setup and cleanup barriers from each repository owner. Preserve database isolation and safety policy. Resolve LAB-178 and FIN-62 in fixtures. A successful cleanup exit is not enough if it skipped external-resource removal.
- [ ] 2.7 Propose rewrites of the legacy `/coordinator` and operator merge/rebase skills for approval. `/worktree` creates worktrees through the coordinator. `/merge` means its reviewed merge. Workers never self-merge. Remove legacy `--no-verify` and self-merge defaults. Preserve explicit base selection and verified fork semantics.

## 3. Proposed qualification for every harness

Run the design.md matrix for Pi, Claude Code, Codex and OpenCode. A passing Pi
path does not qualify another harness. Final retirement has no non-Pi exception.

- [ ] 3.1 Use disposable Git fixtures under a temporary directory. Record exact versions, commands, base and HEAD, checkout, workspace, pane, native session, peer incarnation, assignment, attempt and message IDs. Bound waits and remove only owned fixture resources.
- [ ] 3.2 Qualify each approved launch and status path with Workmux unavailable. Check effective native integration delivery, not source existence. Preserve each harness's explicit model, provider, sandbox and approval policy. Test its trust, authentication, permission and input blockers before model work.
- [ ] 3.3 Omit or fail Pi trust projection and prove launch still runs with a warning. Preserve explicit denials. Test the actual trust prompt separately. Do not grant global trust, fall back to credentials or models, or inject terminal text as an accepted assignment.
- [ ] 3.4 For each harness, prove a uniquely addressed worker accepts an assignment. Route its correlated question through its coordinator and operator seat. Return the answer and follow-up. Inspect the resulting artifact independently.
- [ ] 3.5 Interleave two workers in separate writable worktrees. Cover each harness and mixed-harness pairs. Prove correct assignment, question and follow-up routing. Reject shared writable state, cross-delivery and duplicate workers.
- [ ] 3.6 Test reconnect, coordinator restart, worker exit, duplicate delivery, stale roster, lost create reply and held automatic delivery for each supported path. Reconcile before retry. Prove native continuation or fenced replacement with an explicit transfer of unresolved work. Do not assume a new same-name seat inherits its predecessor's inbox.
- [ ] 3.7 Test watcher escalation for a held steer, expired coordinator work and a provider rate limit that stops turns. Prove the correct operator seat receives the correlated DM and raises it. Restart the observer, deny diagnostics and stale the supervisor binding. Report unavailable observations and routing failures. Tolerate duplicate delivery without repeated recovery actions.
- [ ] 3.8 Test recursive and linked submodules, initialized-submodule removal, repeated shell entry, per-worktree hooks, isolated service state, copy-not-share behavior, safety flags and explicit warm-up failure. Remove one fixture without breaking another's hooks. Do not automate the manual deletion workaround for LAB-178.
- [ ] 3.9 Test clean, dirty, untracked, unknown-owner and partial-create fixtures. Failed repository cleanup vetoes removal. Verify external resources are gone before Herdr removal. Do not force dirty or ambiguous trees. Preserve unrelated sessions, branches and files.
- [ ] 3.10 Complete one useful authorized repository change end to end. Implement, verify, review independently, follow up, integrate serially through the coordinator, and observe required CI after merge. Keep deployment and approval gates. Prove direct native use of all four harnesses and Herdr still works without the mesh.

## 4. Proposed consumer migration and final retirement

- [x] 4.1 In agentic, migrate every source-index path in design.md. Update setup exports, options, bootstrap, generated role guidance, registry entries, docs, templates and ignores. Preserve both transports and one writer per artifact.
- [x] 4.2 Preserve the semantics tested by `workmux`, `workmux-worktree-hooks`, `public-surface`, `agents`, `org-neutral` and affected template/bootstrap checks. Give replacement checks suitable names. Do not delete coverage just because its name contains Workmux.
- [ ] 4.3 Request coordinated changes from the infrastructure repository and Home Manager owners. Migrate launch profiles, all harness status resources, shared-workflows guidance, skills, registry entries and tests. Preserve native prompt visibility, sounds, telemetry and unrelated MCP behavior. Remove every Workmux dependency at the shared gate.
- [ ] 4.4 Request qualification from finance, portfolio-balancer and nixos-boards owners before they retire their setup and cleanup hooks. The workspace instance owner verifies the resolved declaration, placement and approved warning-only trust projection. These are proposals for the named owners, not edits authorized in agentic.
- [ ] 4.5 Exercise every identified consumer without Workmux on PATH. Record a discovered dependency with its owner and resolve it before retirement. Preserve active attempts, sessions, branches and trees. Restore prior pins for future launches if rollback is needed. Do not retain a non-Pi compatibility carve-out.
- [ ] 4.6 Seek separate final retirement approval after all four harnesses pass. Each owner then removes its unused Workmux package, input, configuration, hooks, profiles and registry entries in the same retirement. No automatic merge, deployment or fork resurrection follows.
- [ ] 4.7 Separately request operator-approved removal of the imperative user-profile entry found by `nix profile list`. Declarative package removal does not remove it. Preserve the exact package reference for rollback. Verify PATH in a fresh shell. Do not prune unrelated profile entries or generations.

## 5. Verification and lifecycle gates

- [x] 5.1 For this documentation commit run `nix develop -c openspec validate --all --strict`, `nix build .#checks.aarch64-darwin.org-neutral`, `nix fmt -- --fail-on-change` and `git diff --check`. Scan this branch's changed-content history for environment hosts, home paths and store paths; it must print no matches. Stage only the retirement change and the approved Workbench promise removals.
- [ ] 5.2 Before implementation review run `nix fmt` for the treefmt gate. Build each affected `nix build .#checks.<system>.<name>` target from 4.2, plus applicable setup and template transport checks. Then run `nix flake check` under repository policy. Do not use `--all-systems` locally; CI owns other-system coverage.
- [ ] 5.3 The coordinator reviews the actual diff and evidence independently. It reports milestones, blockers and handoff references to BPH-71. It routes decisions to the operator seat and keeps cross-repository authorization with each owner.
- [ ] 5.4 Keep evidence and rollback references through review. Archive only after authorized implementation ships. When syncing the durable spec, update the `agentic-devenv` purpose text to describe creator-neutral artifacts rather than the retired YAML. This draft does not complete implementation or approve retirement.
