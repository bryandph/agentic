---
name: memory
description: Search, propose and curate this repository's knowledge bundle (Open Knowledge Format) - specs, decisions and memory. Use before designing or answering why something is the way it is, when a change touches a contract, and when a session learns something a later session should know.
---

# Memory

This repository's knowledge is an [Open Knowledge Format 0.2](https://github.com/GoogleCloudPlatform/open-knowledge-format/blob/main/SPEC.md)
bundle in the folder set by `agentic.bundle.root` (usually `.okf/`),
committed with the code. It holds durable knowledge about the
repository: behaviour contracts (`specs/`, `type: Spec`), decisions
(`type: Decision`), how it works, why it is that way, gotchas and
conventions. Work and its status belong in the backlog (see the
work-tracking skill), never in the bundle.

## Search before you design

`qmd-knowledge query "<question>"` (or `search` for keywords) searches
this scope: the repository's bundle plus any child scopes it declares.
Read a hit with `qmd-knowledge get <path>`. A scope never sees its
parent; context from above arrives in your assignment.

## One concept per file

```markdown
---
type: Gotcha
title: Migrations must not run at startup
description: Schema migrations run as a separate job, never in the app process.
tags: [database]
status: stable
generated: { by: <agent>/<model>, at: 2026-01-01T00:00:00Z }
verified:
  - { by: human:<operator>, at: 2026-01-02T00:00:00Z }
sources:
  - id: pr-42
    resource: <pull request or commit URL>
---

Why, in a few sentences, with the evidence linked through `sources`.[^pr-42]
```

- `type` is required. Use short, descriptive kinds: `Spec`, `Decision`,
  `Architecture`, `Convention`, `Gotcha`, `Reference`, `Playbook`.
- `generated.by` names who wrote it: `<agent>/<model>` for an agent,
  `human:<name>` for a person. `generated.at` is the last meaningful
  change.
- `verified` lists who confirmed it. Only the operator adds `human:`
  entries; a coordinating agent that checked it adds its own actor.
- `status` is `draft` (proposed, not reviewed), `stable` or
  `deprecated` (kept for links, no longer true). Set `stale_after` when
  a fact is known to expire.
- Link related concepts with bundle-relative links (`/architecture/x.md`).
- Keep `index.md` in each folder listing its concepts with their
  descriptions. Do not keep a `log.md`: git is the history.

## Specs

A `type: Spec` concept states what the system must do, as requirements
with scenarios a reviewer can check, and why. One concept per capability
under `specs/`. A change to a contract edits the concept in the pull
request that implements it; git history is the change record.

## Who writes memory

- Workers do not write memory. They return learnings with their result.
- The repository's coordinating agent decides what is worth keeping and
  commits it, as `draft` for anything not yet confirmed.
- The operator reviews drafts; reviewed concepts become `stable` with a
  `human:` verification. Specs and decisions are agent drafts until the
  operator verifies them.
- Agents never add or change a `human:` entry in `generated` or
  `verified`. Pull request review checks this; there is no automated
  check.
- Correct a wrong concept in place, or mark it `deprecated` with a link
  to its replacement. Never store secrets, credentials or personal data.
