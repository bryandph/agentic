---
name: worktree
description: Create and remove worker worktrees with Herdr and the repository lifecycle runners. Use as a coordinator when preparing or cleaning up an assigned worker checkout.
---

# Worktree

Only the coordinator creates or removes worker worktrees. Workers use the
checkout supplied in their assignment; they do not create or remove worktrees.
Follow your coordinator persona for escalation policy and authorization.

## Create

1. Read the assignment for the repository, branch and explicit base. If any is
   missing or ambiguous, stop and escalate rather than guessing.
2. Run:

   ```sh
   herdr worktree create --cwd <repo> --branch <branch> --base <base> --label <name> --no-focus
   ```

   Always pass `--cwd` and the explicit `--base`. Record the returned worktree
   path, workspace ID and pane; do not infer them from the branch name.
3. If creation fails, stop and escalate. Never fall back to
   `git worktree add` or `herdr workspace create`.
4. Run `workbench-worktree-setup --worktree <path>` with the returned path.
   A non-zero exit is a stop: retain the diagnostics and escalate before
   dispatching work. A successful setup does not prove worker readiness;
   verify readiness through the actual harness before handing over the task.

## Remove

1. Confirm the worker has finished and the checkout belongs to this assignment.
   Inspect `git status` in that checkout; preserve uncommitted work and stop
   if ownership or the safe cleanup decision is unclear.
2. Run `workbench-worktree-teardown --worktree <path>`. It must succeed before
   removal. On failure, stop and escalate; do not remove the checkout.
3. Run `herdr worktree remove --workspace <id>` with the recorded workspace ID.
   Use `--force` only for a worktree you own, with a clean `git status`, after
   a verified successful teardown. It is not a recovery shortcut.
4. Record cleanup results for the coordinator's handoff.

Never use `--no-verify` or any other hook or check bypass.
