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
   dispatching work. A successful setup does not prove worker readiness.
5. Start the selected worker in the returned, available shell pane:
   `workbench-worker-start --pane <pane> --worktree <path> --timeout 30 -- <launcher> --prompt-file <file>`.
   Inspect its JSON result and escalate blocked or failed startup; do not
   answer prompts or retry blindly. Herdr startup evidence is not assignment
   acceptance: wait separately for the worker's first acknowledgement.

## Remove

1. Confirm the worker has finished and the checkout belongs to this assignment.
   Preserve uncommitted work and stop if ownership is unclear.
2. From this repository's dev shell, run
   `workbench-worktree-remove --workspace <id> --worktree <path>` with the
   recorded workspace ID and path. Omit `--worktree` only to resolve it from
   Herdr; the command always checks workspace and checkout agreement.
3. Retain the JSON result for the coordinator's handoff. Only `status: removed`
   (exit zero) means success. A refusal is a stop: preserve its diagnostics and
   escalate, never bypass the barrier with direct Herdr or Git removal.

The command refuses main or foreign checkouts, dirty/untracked paths, running
or blocked workspace agents, and failed teardown verification. It preserves
teardown output. Initialized submodules permit an automatic `--force` retry
only for Git's specific submodule removal refusal after successful teardown
and fresh clean-tree checks, including recursive submodules. It never deletes
branches, stashes changes, or deletes untracked files.

Never use `--no-verify` or any other hook or check bypass.
