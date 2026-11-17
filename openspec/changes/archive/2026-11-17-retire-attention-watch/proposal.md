Authoritative work item: BPH-81 (related: BPH-91, BPH-92). The work item's
private tracker link is supplied with the assignment, not published in core.

## Why

retired by Bryan 2026-11-16; rely on Cotal's stalled status and Herdr.

The always-on host watcher duplicates native observation and requires a separate
admin credential. The approved agentic-only retirement removes that mechanism
without changing host services, credentials or state.

## What Changes

- Remove the watcher module, package, contributor-shell and bootstrap entries.
- Remove broker queue sampling and watcher-state reads from worker recovery.
- Remove the watcher's requirement from `worktree-worker-migration` and its
  current README documentation.

## Capabilities

### Modified Capabilities

- `worktree-worker-migration`: remove "Independent watcher escalates coordinator
  attention"; retain startup, snapshots, fenced recovery and governance.

## Migration

Consumers stop selecting the retired package. Recovery callers stop passing the
removed admin credential, server and watcher-state flags and stop reading the
removed top-level queue evidence fields. Supported connector snapshot diagnostics
remain available; native Cotal stalled reporting and Herdr replace the watcher.
Environment owners manage any remaining services, credentials and state separately.

## Non-goals

No changes to another repository, credentials, launchd, host state, automatic
recovery, coordinator approvals, merges or deployments.

## Impact

The package export and bootstrap package list change in core. Recovery no longer
opens an admin connection or reads watcher files. The independent watcher
requirement is removed, not replaced with another daemon or execution journal.
