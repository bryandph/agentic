# Typed assignment outcomes

BPH-66 Phase 1 / BPH-11 introduces `agentic.outcome/1`: an assignment ends in
exactly one typed outcome, not a mixture of a result, a question and a handoff.
The receiver validates that record and independently re-measures its evidence.
This is an interchange contract, not an assignment journal, approval mechanism,
Cotal run program, supervisor, or decision queue. Validation cannot prove that a
worker actually published only one final message; the receiver owns that boundary.

The schema is [`schemas/agentic.outcome-1.json`](../schemas/agentic.outcome-1.json)
(JSON Schema draft 2020-12). The Python 3 stdlib CLIs are included in
`agentic.devenvLib.packages` under both shell transports and in this repository's
contributor shell. No Python dependencies or credentials are required.

## Record

Every record has these fields:

| Field | Meaning |
| --- | --- |
| `schema` | Exactly `agentic.outcome/1`. |
| `kind` | One of the seven kinds below. |
| `assignment` | Object with required `repo`; optional `issue`, `branch`, `worker`, `run`. Each is a nonempty string. Public records use issue IDs, not tracker links. |
| `summary` | String of at most 500 Unicode characters, with no CR, LF, or Unicode line/paragraph separators. One paragraph. |

Exactly one body must be present, and it must match `kind`. Unknown fields are
rejected at every object level. Required and optional textual fields are nonempty
strings, except `summary`, which may be empty. Optional does not mean nullable.

| Kind | Required body | Fields |
| --- | --- | --- |
| `result` | `result` | `evidence`: array of at least one evidence item. |
| `blocked:decision` | `decision` | `id`, `question`, `context`, `options` (at least two objects with `id`, `label`, `consequences`), `recommendation` (an option id), `scope` (what an answer authorizes). |
| `blocked:approval` | `approval` | `id`, `action`, `artifact`, `reason`. |
| `blocked:environment` | `environment` | `code`, `detail`; optional `remediation`. Codes such as `nix-relativeworktrees` are valid; there is no closed code registry. |
| `blocked:external` | `external` | `waitingOn`, `deadline` (RFC 3339 timestamp including timezone); optional `evidence` (one item). |
| `failed` | `failed` | `attempted`, `error`, `externalEffects` (boolean); optional `effects` (array of nonempty strings). |
| `handoff` | `handoff` | `to`, `reason`. |

Decision option IDs must be unique, and `recommendation` must match one of them.
These cross-value constraints cannot be expressed in standard JSON Schema: they
are declared in the schema's `$comment` and checked by `workbench-outcome` in
addition to the schema's structural rules. Other schema validators must also
enable `date-time` format assertion. `x-discriminator` is a schema annotation
used by the stdlib implementation to report precise errors rather than an opaque
`oneOf` failure. It does not change standard JSON Schema evaluation.

### Evidence items

| `type` | Fields |
| --- | --- |
| `git-ref` | `remote`, `ref`, `sha` (40- or 64-character lowercase hexadecimal object ID). Use an exact full ref, e.g. `refs/heads/main`, or `HEAD`, not a glob or branch shorthand. |
| `check` | `attr`, `exitCode` (integer); optional `flake` (defaults to `.`). `attr` is the check attribute beneath `checks.<current system>`. |
| `file` | `path`, `sha256` (64 lowercase hexadecimal characters). |
| `ci` | `system`, `pipeline`, `status` (all strings; stringify numeric pipeline IDs). |
| `flux` | `kind`, `name`, `namespace`, `revision` (all strings). |

Paths and local Git remotes resolve against the receiver's current working
directory, not the outcome file's directory. File content is hashed in chunks.
Evidence records are claims, not commands or permission to deploy or merge.

## Commands

```sh
workbench-outcome validate outcome.json
workbench-outcome validate - < outcome.json
workbench-outcome extract message.txt > outcome.json
workbench-outcome yield outcome.json
workbench-outcome ask-schema
workbench-verify outcome.json
workbench-verify --rerun-checks outcome.json
```

`validate [FILE|-]` defaults to stdin. It exits 0 for a valid record, or 1 and
prints one violation per stderr line: `<JSON-pointer>: <reason>`. `/` denotes the
root in diagnostics. Input and filesystem errors also exit 1. Validation emits
nothing on success and performs no probes.

`extract FILE` requires exactly one fenced block whose opening line is exactly
`` ```agentic-outcome `` (trailing horizontal whitespace is allowed). It prints
the parsed JSON object. Zero or multiple blocks, malformed JSON, and non-object
JSON are errors (exit 1). Extraction does not replace validation: run `validate`
on the extracted record before treating it as an outcome.

`yield FILE` validates and prints a Cotal yield argument record; it does **not**
contact Cotal or settle a workflow turn. Mapping:

| Outcome | Printed record |
| --- | --- |
| `result` | `{"status":"done","note":"<summary>"}` |
| `blocked:decision` | `{"status":"blocked","note":"blocked:decision <id>"}` |
| `blocked:approval` | `{"status":"blocked","note":"blocked:approval <id>"}` |
| `blocked:environment` | `{"status":"blocked","note":"blocked:environment <code>"}` |
| `blocked:external` | `{"status":"blocked","note":"blocked:external <waitingOn>"}` |
| `failed` | `{"status":"blocked","note":"failed: <error first line>"}` |
| `handoff` | `{"status":"handoff","to":"<to>","note":"<reason>"}` |

External blockers have no id/code field, so `waitingOn` is their note identifier.
All generated notes use only the first line and are bounded to 200 Unicode
characters; longer notes keep the first 199 characters followed by `…`.
The caller supplies a turn identifier separately if Cotal needs one. A handoff
does not authorize crossing a worktree or run boundary; Cotal's own restrictions
still apply.

### Cotal ask shorthand

`ask-schema` prints:

```json
{"schema":"string","kind":"string","assignment":"record","summary":"string"}
```

This is the Cotal 0.91.0 `ask` **shorthand**, not JSON Schema. A run passes it as
`ask`'s `schema` argument to require those four top-level fields and their kinds.
Shorthand permits extra fields and cannot enforce the literal schema version,
kind/body relationship, or nested fields. The receiver must still run
`workbench-outcome validate` before using the reply. Core ships no run program in
this phase.

## Re-measuring evidence

`workbench-verify FILE` validates the record, then probes result evidence in array
order, or the external blocker's optional single evidence item (index 0). Other
kinds have no evidence and produce `{"items":[]}` with exit 0; that does not turn
a blocker into a successful result.

The verifier prints one JSON object:

```json
{"items":[{"index":0,"type":"file","verdict":"ok","observed":"<measured sha256>","detail":"sha256 compared"}]}
```

Each item includes `index`, `type`, `verdict` (`ok`, `mismatch`, `unknown`),
`observed`, and `detail`. Observations are a SHA string for a file, an array of
SHAs matching the exact Git ref, an integer exit code for a re-run check, or
`null` when no measurement was available. A missing Git ref is a mismatch;
a missing/unreadable file, unavailable executable, failed remote query, or
120-second subprocess timeout is unknown, never evidence of success.

- `git-ref`: `git ls-remote <remote> <ref>`; compare the exact returned ref's SHA.
  No fetch, checkout, mutation, or credential retrieval is performed. Git may
  use the receiver's existing transport configuration; review untrusted remotes
  before invoking it.
- `file`: SHA-256 of the bytes at `path`.
- `check`: unknown with detail `not re-run` by default. Only `--rerun-checks`
  permits evaluating the current Nix system and running
  `nix build --no-link <flake or .>#checks.<current system>.<attr>`; compare its
  exit code with `exitCode`. Nix is not bundled or pinned: both commands use the
  receiver's `nix` on `PATH`. A missing executable returns unknown with detail
  `nix not on PATH`. This flag authorizes executing the referenced Nix
  build, not just observing it. Inspect the flake before opting in. Nix may
  substitute/fetch inputs according to the receiver's configuration.
- `ci`, `flux`: always unknown with detail `probe not configured (deferred)`.

Exit 0 means all probed items are ok; exit 1 means at least one mismatch; exit 2
means at least one unknown and no mismatch. Invalid input exits 1 with pointer
diagnostics instead of an evidence report. Unknowns must remain visible to the
receiver, not be silently promoted to ok. No service API, CI/Flux probe, credential
store, or non-Git network probe is included. Explicitly opted-in Nix builds have
their normal execution/network behavior.

## Compact examples

Each line below is a complete record; choose exactly one for an assignment.
The file hash is illustrative and must be replaced with a measured hash.

```json
{"schema":"agentic.outcome/1","kind":"result","assignment":{"repo":"agentic","issue":"BPH-66"},"summary":"Contract shipped.","result":{"evidence":[{"type":"file","path":"docs/outcome-contract.md","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}]}}
{"schema":"agentic.outcome/1","kind":"blocked:decision","assignment":{"repo":"agentic"},"summary":"Choose a transport.","decision":{"id":"transport","question":"Which transport?","context":"Both are supported.","options":[{"id":"a","label":"A","consequences":"Reuse existing setup."},{"id":"b","label":"B","consequences":"Add setup."}],"recommendation":"a","scope":"Select the transport only."}}
{"schema":"agentic.outcome/1","kind":"blocked:approval","assignment":{"repo":"agentic"},"summary":"Deployment needs approval.","approval":{"id":"deploy","action":"deploy","artifact":"reviewed commit","reason":"Live change."}}
{"schema":"agentic.outcome/1","kind":"blocked:environment","assignment":{"repo":"agentic"},"summary":"Worktree setup failed.","environment":{"code":"nix-relativeworktrees","detail":"Nix cannot resolve this worktree.","remediation":"Repair the setup before starting."}}
{"schema":"agentic.outcome/1","kind":"blocked:external","assignment":{"repo":"agentic"},"summary":"Waiting for upstream.","external":{"waitingOn":"upstream release","deadline":"2026-11-16T12:00:00Z"}}
{"schema":"agentic.outcome/1","kind":"failed","assignment":{"repo":"agentic"},"summary":"Build failed.","failed":{"attempted":"Build the contract check.","error":"Fixture assertion failed.","externalEffects":false}}
{"schema":"agentic.outcome/1","kind":"handoff","assignment":{"repo":"agentic"},"summary":"Repository boundary reached.","handoff":{"to":"coordinator","reason":"Next change belongs to a different repository."}}
```

## Offline check

`nix build .#checks.<system>.outcome-contract` exercises valid records for every
kind, missing required fields and their paths, kind/body mismatches, extraction,
yield mapping, ask shorthand, file hashes, a local bare Git remote, deferred
probes and opt-in check command construction. No fixture needs network access,
credentials, a broker, or a Nix daemon inside the build sandbox.
