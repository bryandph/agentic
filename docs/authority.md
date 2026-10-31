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

These are instructions, not tool permissions, Cotal control-plane grants or
runtime enforcement. They do not replace capability limits, service ACLs or
existing approval gates. Unlisted classes receive no authority from this field.
