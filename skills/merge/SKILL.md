---
name: merge
description: Review and serialize a worker branch merge into its assigned base, rerun checks and watch required CI. Use as a coordinator when integrating completed work.
---

# Merge

Only the coordinator integrates reviewed work. Workers never merge their own
branches; they report their branch, HEAD and evidence to the coordinator.
Follow your coordinator persona for escalation policy and authorization.

Never use `--no-verify` or any other hook or check bypass.
A failing hook or check is a finding to investigate, not an obstacle to evade.

1. Read the assignment and confirm its explicit base and worker branch. Stop
   and escalate if the integration target is missing or ambiguous.
2. Review the complete diff and the worker's evidence, including tests and
   known limitations. Resolve findings before integration; a worker's report
   is not a substitute for your own review.
3. Record the worker HEAD and run the repository's required checks yourself on
   that branch. If it changes after review or validation, review and check the
   new HEAD before proceeding.
4. Serialize integrations into the base: only one merge at a time. Verify the
   intended repository and clean checkout, and record the explicit base ref,
   its current commit and the reviewed worker HEAD before integrating.
5. Integrate the reviewed worker HEAD into that explicit base using the
   repository's merge policy. Resolve any conflicts deliberately and review
   the resulting diff. Record the resulting HEAD; do not silently change the
   target or include unrelated work.
6. Rerun the repository's required checks on the integrated result. If any
   check or hook fails, stop and report the finding; do not push a failed
   result or bypass the guard.
7. Push the validated result to the assigned base under the repository's
   authorization policy, then watch required CI for that exact commit.
   Report failures or blocked CI using your coordinator persona; do not
   declare completion while required checks remain pending.
8. Report the merge hash, base, reviewed worker HEAD, local check results,
   push result and required CI outcome. Leave worktree cleanup to the
   coordinator's worktree procedure.
