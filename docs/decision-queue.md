# Bound decision queue

BPH-66 Phase 1 / BPH-11 adds `workbench-decide`, a Python stdlib CLI included in
the `workbench-outcome` package, both consumer shell transports, and the contributor
shell. It reuses the [outcome contract](outcome-contract.md) validator for assignment
and decision fields. No run program, supervisor integration, credentials, or
promotion-to-registry automation ships here.

A coordinator files a validated `blocked:decision` outcome; a run passes the
rendered prompt to `checkpoint(...)`. The operator seat reads open decisions,
presents them to the operator, and answers each by run and decision id. The
receiving coordinator verifies the accepted checkpoint answer against the original
prompt before acting. The CLI does not ask the human itself or grant authority.

## Commands

```sh
workbench-decide prompt outcome.json > prompt.txt
workbench-decide parse prompt.txt
workbench-decide queue --json
workbench-decide queue
workbench-decide answer --run run-1 --decision transport --option a
workbench-decide answer --run run-1 --decision transport --option a --promote --note 'Use existing setup.'
workbench-decide check-answer prompt.txt answer.json
```

`prompt` accepts only a valid `blocked:decision` outcome. It prints the question
on one plain-text line, options with their consequences, a recommendation line,
and exactly one fenced `agentic-decision` JSON block. Multiline prose is flattened
only for display; the JSON preserves exact strings. The block contains exactly:

```json
{"schema":"agentic.decision/1","decisionId":"transport","assignment":{"repo":"agentic","issue":"BPH-66"},"question":"Which transport?","options":[{"id":"a","label":"A","consequences":"Reuse setup."},{"id":"b","label":"B","consequences":"Add setup."}],"recommendation":"a","scope":"Select the transport only."}
```

`parse PROMPT` takes a **file path**, requires exactly one complete block, validates
it and prints its JSON object. It is the inverse of `prompt` at the decision-record
level, not the full outcome: `summary` and `context` are not checkpoint fields.
Prose outside the block is presentation only, never binding authority.

`queue --json` prints an array of `{run, stepKey, decisionId, repo, issue, question,
options, recommendation, scope}`; an absent issue is `null`. Plain `queue` prints
one compact identifying line per open decision. Settled decisions are absent.
Malformed or ambiguous adapter records fail the entire operation, not a partial
queue. If the assignment names a run, it must equal the adapter's run.

`answer` re-reads the open decisions and selects exactly one `(run, decisionId)`.
It checks option membership, copies the filed scope unchanged, and calls the
adapter once with the bound step key and this value:

```json
{"schema":"agentic.decision-answer/1","decisionId":"transport","option":"a","scope":"Select the transport only.","promote":false}
```

`promote` is always boolean and defaults to false; `note` is an optional string.
There is deliberately **no `--scope` flag**, arbitrary answer JSON, amendment
command, or retry. Unknown runs/ids/options, settled decisions, ambiguity and
adapter errors fail closed. `--promote` carries the operator's intent only: it
neither edits a registry nor widens scope.

`check-answer PROMPT ANSWER.json` requires the exact answer schema and fields,
matching decision id, an offered option, and exact scope equality. It is silent
on success. Unknown fields, missing fields, invalid promote/note types and all
binding mismatches refuse. It verifies a value, not its provenance: obtain the
accepted answer from the authenticated checkpoint journal, not an untrusted file.
Cotal owns single-use settlement, attribution and amendment history. Check the
accepted answer the run acted on; amendments do not replace that frozen result.

All commands exit 0 on success, otherwise nonzero with one stderr reason line.
Local refusals send nothing. An answer whose transport fails may already have
settled remotely: inspect the journal; never blindly retry. No client can retract
a dispatched answer after an uncertain transport failure.

## Adapter boundary

Adapters expose `open_decisions()` and `answer(run, step_key, value)`.
The first returns a list of `{run, stepKey, decision}` records, where `decision`
is the validated block object. The second must settle only an open step once.
The core checks the full list, binding and option before invoking `answer`.
No adapter is enabled by default.

### Offline fake

Set `WORKBENCH_DECIDE_FAKE=/absolute/path/fixture.json`; alternatively also set
`WORKBENCH_DECIDE_ADAPTER=fake`. The fixture is a JSON object with `decisions` and
`answers` arrays:

```json
{"decisions":[{"run":"run-1","stepKey":"/checkpoint:choose#0","prompt":"<full rendered prompt>","state":"open"}],"answers":[]}
```

Only `open` and `settled` states are supported. On answer the fake rechecks the
binding under a file lock, marks the row settled, and appends
`{run, stepKey, value}` to `answers`. Refusals leave the file byte-for-byte
unchanged. This is a test fixture, **not** a crash-safe production store.

### Cotal — UNVERIFIED, opt-in only

`modules/registry/_outcome/decide_cotal.py` isolates all Cotal-specific logic.
Its constructor refuses unless `WORKBENCH_DECIDE_ADAPTER=cotal`, even on direct
import. This explicit value overrides a fake fixture setting. The CLI uses the
existing `cotal` executable on PATH and its existing mesh configuration; it does
not bundle Cotal, discover credentials, or add credential flags.

Written against the **Cotal 0.91.0 bundled CLI/workflows docs**:

- `cotal run ps --json`: JSON Lines with `runId`.
- `cotal run journal <run> --json`: JSON Lines; pending `checkpoint` rows with
  string `asks` containing an `agentic-decision` block are candidates; `step`
  supplies the step key. Ordinary checkpoints are ignored. Malformed typed
  decisions and unknown candidate shapes refuse.
- `cotal run answer <run> <step> --value <json>`: one call, no amend or retry.

The exact open-checkpoint state/asks projection is **not live-qualified**. A
Cotal 0.164 upgrade is pending; the coordinator must recheck this single file
against that release and a controlled trial before enabling it. Empty inventory
is not independent proof of completeness. Multi-manager selection, inventory
completeness and expiry behavior must be requalified too; the adapter does not
invent manager-selection or pagination behavior. All subprocesses have a
30-second timeout; command failures suppress external stderr and fail closed.
The service remains responsible for the final atomic open-step check if another
answer races this client.

## Offline check

```sh
nix build .#checks.aarch64-darwin.decision-queue
```

Fixtures exercise the installed CLI: prompt/parse round trip, queue projection,
exact answers, scope copying, single use, unknown ids/options/runs, settled and
ambiguous decisions, absent scope flags, adapter errors, receiving verification,
invalid contract fields, and the Cotal opt-in guard. Cotal command construction
uses only stubbed responses; tests never call a real Cotal executable or service.
