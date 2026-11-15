# Agent authority

`agentic.agents.<name>.authority` declares which action classes an agent may
perform without asking and which require a decision:

```nix
agentic.agents.worker.authority = {
  autonomous = [ "push-own-branch" ];
  decision = [ "deploy-manual" "secrets" "cross-repo" ];
};
```

Both lists default to `[]`. They must be disjoint and contain no duplicates.
Unknown classes fail option type validation. Overlaps and duplicates fail
rendering with the agent name and offending classes in the error.

The closed vocabulary is:

| Class | Rendered description |
| --- | --- |
| `merge-own-repo` | merge and push your own repository's branches |
| `push-own-branch` | push your own working branch |
| `deploy-manual` | deploy manually |
| `cluster-out-of-git` | change the cluster outside git |
| `secrets` | access or change secrets |
| `delete-remote` | delete or archive remote repositories |
| `cross-repo` | work across repositories |
| `set-work-status-final` | set final work-item statuses |

Every renderer carries plain authority sentences in the body. Autonomous
classes follow “You may do these without asking”. Decision classes go to the
peer with the Cotal role of `cotal.escalateTo`, found through roster lookup;
when no target is set, they go to the operator. Existing escalation target
validation applies to every renderer. Empty lists render nothing, leaving
existing outputs unchanged.

## Standing rules

`authority.standing` records explicit, narrow grants per agent in the consuming
repository's agent registry. It defaults to `[]` and adds no output when empty.
For example:

```nix
agentic.agents.coordinator.authority.standing = [
  {
    id = "merge-local-checks";
    rule = "Merge this repository's branches after its required local checks pass.";
    source = "decision:merge-local-checks BPH-11";
    grantedBy = "human:operator";
    grantedAt = "2026-11-15T08:00:00Z";
  }
];
```

Each entry requires all five string fields. `id` is a `[a-z0-9-]` token, unique
per agent; duplicates fail rendering with the agent name. `rule` is one plain
sentence saying exactly what may be done without asking. `source` records where
it was decided (a decision id and, when available, an issue id); `grantedBy`
identifies the grantor; `grantedAt` is an RFC 3339 date-time with timezone.

Every authority renderer adds “Standing rules (apply without asking, only exactly
as written): ” followed by each `<rule> (<id>)`, separated by semicolons. A
standing rule cannot authorize anything outside the agent's scope. It is a
narrower additional grant, not a new action class and never a reason to remove a
`decision` class. Decision classes still apply to everything a rule does not
cover. Review the rule together with scope, capability limits and existing gates.

### Promote an answered decision

Any answered decision can be proposed as a standing rule:

```sh
workbench-decide promote prompt.txt answer.json \
  --granted-by human:operator --granted-at 2026-11-15T08:00:00Z
```

The command first applies the same validation as `check-answer`: the answer must
match the decision id, an offered option and the exact scope. It also requires
`promote: true`, a standing-rule-compatible decision id and valid grant metadata.
It prints only a Nix attrset literal containing the decision id, the chosen
option's label and consequences plus the decision scope, `decision:<id>` and
`assignment.issue` when present, and the supplied grantor and time. Nix string
quoting preserves prose without allowing interpolation.

The command is offline and never edits files or submits a grant. Take its output
through a reviewed PR to the consumer's `authority.standing` list, checking that
the proposed prose is an exact, plain grant rather than a broader interpretation
of the answer. An answer's promotion flag proposes persistence; it does not
itself install standing authority.

These are instructions, not tool permissions, Cotal control-plane grants or
runtime enforcement. They do not replace capability limits, service ACLs or
existing approval gates. Unlisted classes receive no authority from this field.
