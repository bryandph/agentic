---
name: rebase
description: Rebase an assigned worker branch onto its explicit base, resolve conflicts and rerun checks without bypassing hooks or rewriting shared branches. Use when a worker branch needs updating.
---

# Rebase

Use the explicit base from the assignment, never a guessed default branch.
If the base is missing or ambiguous, stop and ask the coordinator.
Follow your coordinator persona for escalation policy and authorization.

Never use `--no-verify` or any other hook or check bypass.
Never force-push a shared or protected branch.

1. Confirm the checkout and assigned branch, inspect `git status`, and preserve
   uncommitted work before proceeding. Record the original HEAD, the explicit
   base ref and its resolved commit. If fetching is needed, use the assigned
   remote and base; do not substitute another integration target.
2. Rebase onto that recorded base commit. Resolve conflicts by understanding
   both changes, not by blindly choosing one side. Stop and escalate if the
   intended behavior is unclear; abort the rebase if it cannot be completed
   safely, and report what remains unresolved.
3. Review the full resulting diff against the base and rerun the repository's
   required checks, including hooks. Treat a failure as a finding to resolve,
   not a reason to bypass validation. Record the new HEAD and check results.
4. If publishing the rewritten history is authorized, `--force-with-lease`
   is permitted only on your own unmerged worker branch, never on a shared
   or protected branch. Verify ownership, unmerged status and the expected
   remote HEAD before pushing. If a lease fails, inspect the remote changes
   and escalate rather than retrying with an unconditional force.
5. Report the old and new HEAD, resolved base commit, conflict decisions and
   checks to the coordinator. A worker rebase does not authorize a self-merge.
