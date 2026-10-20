---
name: work-tracking
description: Track this repository's work as Backlog.md tasks under the shared lifecycle. Use before creating, changing or finishing a task, and when work needs planning, a decision or review.
---

# Work tracking

This repository's work lives in `backlog/` as Backlog.md tasks, committed
with the code. Knowledge (specifications, decisions, learned facts) lives in
the repository's Open Knowledge Format bundle (`.okf/`) instead; see the memory skill. Upstream Backlog.md owns the
workflow; this skill adds the conventions that apply on top of it.

## Start with upstream

Run `backlog instructions overview` and read the guide it names before
the matching action (`task-creation`, `task-execution`,
`task-finalization`). Change Backlog data only through the `backlog` CLI;
never edit its markdown files. Run `backlog <command> --help` before an
unfamiliar operation.

## A task is the current state, not a log

- The description says why the task exists. Acceptance criteria say what
  will be true when it is done. The plan is the current approach.
- Notes hold the current status and next step. Replace them with
  `--notes`; do not append progress (`--append-notes`) or narrate what a
  session did.
- Comment only for something a later reader needs that the task does not
  hold: a decision the operator made, with its date; a blocker that needs
  someone; or a question for review.
- Execution detail stays where it happens (commits, pull requests, run
  journals, harness sessions). Link it with `--ref`; do not paste it.

## Lifecycle

Statuses are configured by the agentic module, in order: Backlog,
Exploring, Planning, Approved, Implementing, Verifying, Review, Done.

- Agents may move a task through Exploring, Planning, Implementing,
  Verifying and Review.
- Only the operator sets Approved and Done, archives (cancels) a task or
  changes its priority.
- Material scope, architecture or workflow decisions in a plan wait for
  the operator's approval before implementation.
- Blocked work keeps its status and records what it waits on as a
  dependency (`--dep`), or in its notes when the blocker is outside the
  repository.
- Before Review: every acceptance criterion is checked against objective
  evidence, the final summary states the result, and the task references
  the pull request and the checks that ran.

## Specifications and decisions

- Small changes need only the task: description, acceptance criteria and
  plan replace a separate proposal and task list.
- Behaviour contracts that outlive a single task are `type: Spec`
  concepts in the OKF bundle; durable rules and design choices are
  `type: Decision` concepts. Do not use Backlog.md docs or decisions for
  them.
- A task links the concepts it relies on or changes with `--ref` (bundle
  path). A task that changes a contract updates the Spec concept in the
  same pull request, as `status: draft` until the operator verifies it.

## Who writes the backlog

- The repository's coordinating agent shapes, plans and moves tasks on
  the default branch.
- A worker in a worktree reads its assigned task and returns its result
  (summary, evidence, learnings) to its coordinator. It changes only its
  own task's status, checked criteria and final summary, in its branch,
  so they land with the code in the same pull request.
- Ask the operator before creating tasks unless the current assignment
  authorizes it.

## References

Refer to a task in another repository as `<repo>#<ID>` (for example
`finance#FIN-12`). Tasks migrated from another tracker keep the old
identifier and URL in their references.
