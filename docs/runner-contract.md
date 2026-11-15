# Worktree runner contract

BPH-66 Phase 1 separates repository preparation from the execution path. Today
Herdr creates the checkout and hosts the worker. A future OpenShell sandbox or
cluster pod must use the **same consumer Nix declaration**, preparation evidence,
launch gate and verified cleanup rules. This is a contract for that future
payload, not a claim that those runners exist. The current boundary is explicit
in `modules/registry/_worktree.nix:1-2`; the exported builders are at
`modules/registry/_worktree.nix:691-696`.

Source references below name paths and line ranges in the implementation at
`ef84d442a201d6b98aac4569bdec6d71d0c0b454`. Requirements for a future runner are
identified as such; they are not additional behavior of the existing tools.

## Inputs and rendered tools

The consumer declares `agentic.worktree` once in Nix, not in a worktree-local
runner file. Its inputs are:

- `shell.kind` (`auto|none|flake|devenv`), `shell.attr` (default `default`) and
  `shell.required` (default false). Auto prefers an available devenv with
  `devenv.nix`, then `flake.nix`, otherwise none.
  (`modules/registry/_worktree.nix:271-278,587-604`.)
- `traits.submodules` (default false) and `submodules.exclude` (exact top-level
  `.gitmodules` paths). Selected submodules initialize recursively; setup checks
  that selected paths are initialized and excluded paths are not. Trait-off is
  an explicit recorded skip, not a request to initialize everything.
  (`modules/registry/_worktree.nix:313-409,606-625`.)
- `copyFiles` (default `[".envrc" ".claude"]`) and `traits.secretDotfiles`
  (default `[]`). Both accept paths or shell globs, preserve relative paths,
  ignore unmatched patterns and copy only absent destinations from the main
  checkout. They do not share writable state.
  (`modules/registry/_worktree.nix:411-435,612-631`.)
- Ordered `setupHooks` and `teardownHooks`: strings or
  `{ name; run; required ? true; needs ? []; }`. Strings remain required with
  zero-based names. Names are unique tokens within each phase, and `needs`
  must name declared services. Each hook runs in its own strict Bash process;
  hooks should use store paths for dependencies. Setup hooks run after built-in
  preparation; only non-required failures may continue as degraded.
  (`modules/registry/_worktree.nix:9-62,480-515,677-688`.)
- `services`: repository-shared declarations with exactly one `probe.tcp` or
  `probe.run`, optional `start`, `process` (default service name), `autostart`
  (default true), `startTimeout` (default 60 seconds), and non-secret `env`.
  (`modules/registry/_worktree.nix:633-676`.)

Render the consumer's `agentic.worktreeLib` builders with its `pkgs`:
`setupScript`, `teardownScript`, `workerStartScript`, `removeScript` and
`servicesScript`. They produce `workbench-worktree-setup`,
`workbench-worktree-teardown`, `workbench-worker-start`,
`workbench-worktree-remove` and `workbench-services`; `hooksScript` supplies Git
hook isolation. Do not substitute generic default-configured tools from PATH.
Worker-start has the consumer's setup store path baked in; remove has the
consumer's teardown store path; setup and teardown call their rendered services
helper directly. (`modules/registry/_worktree.nix:77-85,487,525-526,572-584,695`;
`modules/registry/_worker-start.nix:1-10`.)

## Prepare and retain evidence

Run `workbench-worktree-setup --worktree <returned-checkout-path>` and await its
completion. Setup defaults to the current directory, but a runner should pass
its actual checkout path rather than derive one from the branch name.
(`modules/registry/_worktree.nix:63-74`.)

Built-in preparation repairs worktree Git configuration, disables and stops the
linked checkout's fsmonitor, performs flake discovery when applicable, discovers
and initializes selected submodules, copies declared files, isolates writable
`.direnv`/`.devenv` state, installs isolated Git hooks, allows direnv if present,
and warms the declared shell before setup hooks. Missing flake shell attributes
are not-applicable, not failures. Discovery and warm-up use `shell.required`;
other built-in steps are required. (`modules/registry/_worktree.nix:178-188,230-480`.)

After Git discovery, an EXIT trap atomically writes
`<absolute-git-dir>/workbench-setup.json`, including on setup failure. Retain this
record with the checkout. Record v2 has:

- `schema: "workbench.worktree-setup/2"`;
- ordered `steps` with `name`, `applies`, `outcome`
  (`ok|failed|blocked|not-applicable`), `required`, and optional `needs`,
  `exitCode`, `reason`, `message` and service result fields;
- overall `status: "ok"|"degraded"|"blocked"|"failed"`, `failedStep`,
  `warmUp: {status, exitCode}`, UTC `startedAt`/`finishedAt`, and `setupCommand`;
- `submodules: {configured, initialized, excluded, skipped}`,
  `fsmonitor.staleSocketRemoved`, `services.<name>.env`, and an optional `blocker`.

Degraded means non-required failures only; a required failure stops setup.
The record identifies the rendered setup executable, not just a protocol version.
(`modules/registry/_worktree.nix:160-227,493-494,505-513`.)

Typed blockers stop setup even when the dependent hook or shell is optional.
They have `kind: "environment"` and one of these codes:

| Code | Meaning and evidence |
| --- | --- |
| `nix-relativeworktrees` | Nix stderr contains `unsupported extension name extensions.relativeworktrees` (case-insensitive). Includes `step`, `nixVersion`, bounded `detail` and `remediation`. Setup exits 6; it does not rewrite repository-wide Git extensions. Remediation is operator conversion to absolute worktree links and unsetting the extension, or Nix >= 2.34.9. |
| `service-workspace-missing` | A down, autostart-enabled service has no Herdr workspace for the main checkout. |
| `service-unavailable` | Failed probe with autostart disabled, an existing failed-probe lease, a failed/timed-out start, or unavailable service state. |

Service blockers include `step`, `service`, `probe`, `startAttempted`, bounded
`detail` and `remediation`. The setup record becomes blocked and setup exits 6.
(`modules/registry/_worktree.nix:145-158,491-498`;
`modules/registry/_worktree-services.py:104-168,200-207`.)

Check without rerunning setup or hooks:

```sh
workbench-worktree-setup --check --json <checkout-path>
```

| Exit | State | Runner action |
| --- | --- | --- |
| 0 | Current `ok` | Proceed to the launch gate. |
| 1 | Failed or malformed | Investigate and rerun setup. |
| 2 | Missing record | Run setup. |
| 3 | Stale: schema absent or setup store path changed | Rerun the current consumer's setup. |
| 4 | Main checkout or not a repository; not applicable | Do not treat this as prepared worker evidence. |
| 5 | Current degraded | Review; rerun or supply the explicit launch override below. |
| 6 | Current blocked | Resolve the blocker and rerun; never override. |

JSON is `{status, code, digest, record}`. The digest is SHA-256 of the exact
record bytes, not a normalized JSON digest; it is null without a record.
A changed `setupCommand` makes the record stale before its status is considered.
Invalid arguments exit 64. (`modules/registry/_worktree.nix:101-137,139-141`.)

## Shared services across execution boundaries

Today setup ensures each service immediately before its first dependent setup
hook. Dependent hooks receive declared `env`; setup records the same connection
values for workers. Teardown receives that env without ensuring or starting the
service. These are public Nix store and record values: never credentials.
(`modules/registry/_worktree.nix:86-94,480-508,551,671-675,688`.)

A TCP probe connects to the declared host and port with a one-second timeout.
A command probe runs `bash -c` from the main checkout, succeeds on exit zero and
has a five-second timeout. Exceptions count as down. Already-up services attach
without starting anything; without a lease they remain `owner: "external"`.
A failed probe with an existing lease preserves that lease rather than starting
a replacement. (`modules/registry/_worktree-services.py:58-69,100-140`.)

The current start mechanism is Herdr-specific: find a workspace whose
`worktree.checkout_path` resolves to the main checkout, create a
`services:<name>` tab there, and run `start` or `devenv up <process>`. Poll until
ready or `startTimeout`; keep failed tabs and leases for inspection. No workspace
is created implicitly. (`modules/registry/_worktree-services.py:102,142-168`.)

Leases live under
`$XDG_STATE_HOME/workbench/services/<sha256-of-canonical-main-path>/<name>.json`
(default state root `~/.local/state`). Repository locking serializes operations;
writes are atomic. Fields are `service`, `owner`, `startedFor`, `workspace`,
`tab`, `pane`, `command`, `startedAt`, `attached`, plus `state: "start-failed"`
on a failed start. Current owner identity is `COTAL_NAME`, otherwise
`user:<login>`; attach deduplicates checkout paths.
(`modules/registry/_worktree-services.py:23-55,123-132,151-168`.)

A future sandbox or pod runner must preserve these safety semantics while
replacing the Herdr transport:

- Attach to the shared service through its declared non-secret `env`. The host
  and port must be reachable **from the worker boundary**, not just the host:
  for example, allow the necessary sandbox egress or provide a cluster Service.
  Host loopback is not automatically sandbox/pod loopback. Preserve probe
  success/failure semantics and typed blockers; never report an unreachable
  dependency as prepared. This is a future runner obligation, not current
  network provisioning. (Existing env/probe boundary:
  `modules/registry/_worktree.nix:86-94,491-498`;
  `modules/registry/_worktree-services.py:58-69`.)
- Bind owned leases to the runner instance and its actual resource handles,
  replacing Herdr workspace/tab/pane fields as needed. Serialize ownership
  changes, preserve failed-start evidence, and detach the checkout only after
  verified cleanup. Do not silently adopt or overwrite another owner's lease.
  (Current ownership/lifecycle basis:
  `modules/registry/_worktree-services.py:23-55,123-168,171-177,227-237`.)
- Never stop external services. Cleanup only detaches; an explicit stop needs
  an empty attachment list and matching owner (or explicit `--as-owner`
  acknowledgement). Today stop closes only the recorded Herdr tab and removes
  its lease; uncertain Herdr failures retain it. A future runner must provide
  equally scoped ownership checks, not broad process or pod deletion.
  (`modules/registry/_worktree-services.py:222-248`.)

Per-worktree service instances, scope and port allocation are not supported in
Phase 1; the declaration is repository-shared.
(`modules/registry/_worktree.nix:633-676`.)

## Launch gate and launch evidence

Before starting a worker, a runner must enforce the existing worker-start gate:
check the current consumer's setup, reject checks 1/2/3/4 as `setup-failed`, and
reject blocked (6) as `setup-blocked` without an override. Degraded (5) requires
`--accept-setup <current-digest> --reason <non-empty-text>`. The digest must match
exactly and be 64 lowercase hexadecimal characters. Failed and blocked are
never overridable. An ok record needs no override; a supplied override is
recorded as unused. (`modules/registry/_worker-start.py:72-98`.)

The current Herdr command also checks prompt-file readability relative to the
target checkout, refuses a pane with an agent, verifies an available foreground
shell and exact checkout cwd, and launches the argv once without shell
interpolation. It does not retry or answer prompts. It observes native Herdr
state with a bounded timeout; `working` means started, `blocked` means blocked,
and a returned shell, vanished pane or unresolved readiness fails closed.
A future runner needs equivalent exclusive launch, checkout identity and native
readiness evidence, not a mesh roster heuristic. Started is not assignment
acceptance. (`modules/registry/_worker-start.py:1,99-184`.)

Worker-start emits one JSON record with `status`, `pane`, `workspace`,
`worktree`, `agent`, native `session`, `agentStatus`, `evidence`, `reason`,
`fallback_reason`, `visible_blocker`, `diagnostics`, `ts`, and optional
`setupOverride: {digest, reason, status}` (`degraded` or `unused`). Evidence and
diagnostics are ANSI-stripped, bounded to 40 lines, 240 characters per line and
4,096 UTF-8 bytes, with repeated-character compression. Exit codes are 0
`started`, 10 `blocked`, 11 `not-started`, 20 `launch-failed`, 30 `setup-failed`,
31 `setup-degraded`, 32 `setup-blocked`. A future transport must retain equivalent
launch and refusal evidence rather than fabricate Herdr handles.
(`modules/registry/_worker-start.py:18-25,57-70,94-98`.)

## Image tools and secrets

`lib.devImages` exports the consumer-parameterized builder;
`lib.devImages.mkDevImage` accepts `extraPackages`. Supply the consumer's
rendered worktree tool packages there so their store closures and executables
travel with the image. This packages tools; it does not implement a runner.
(`modules/dev-images.nix:1-11,21`;
`modules/_dev-images/builder.nix:234-270`.)

On the current host/Herdr path, `secretDotfiles` are copied from the main
checkout by the same copy loop as `copyFiles`. A sandbox or pod must instead
receive secrets through its secret backend, not through an image layer or a
mount exposing the main checkout. Secret-backend delivery and adaptation of
this copy step are out of scope for Phase 1; there is no implemented backend
switch in that loop. Do not put secrets in service env, Nix declarations or
launch evidence. (`modules/registry/_worktree.nix:411-428,612-617,671-675`.)

## Verified teardown and removal

Run the consumer's teardown before deleting its checkout or runner resources.
Required hooks must exit zero, print a stdout line starting `verified:`, and
not print `skipped` anywhere on stdout (case-insensitive). A required failure
vetoes removal. Non-required hooks need no verification line and report nonzero
exits without stopping standalone teardown. Every stdout line from a
non-required hook is prefixed `optional[<name>]: `, including any `verified:`
line. Removal retains that output but ignores lines starting `optional[` in its
defensive `skipped` scan and collects only unprefixed `verified:` lines as proof.
Required hook output stays unprefixed; a nonzero teardown exit still vetoes
removal regardless of output. With no hooks, teardown succeeds with a note.
Only after hooks pass does it detach from all repository leases; it never
stops services or removes the checkout itself.
(`modules/registry/_worktree.nix:533-583`.)

Current remove is a Herdr-specific fail-closed barrier: verify workspace/path
agreement against Herdr and Git, establish linked membership in the expected
repository, refuse the main checkout, check tracked/untracked and recursive
submodule cleanliness, and refuse working or blocked workspace agents. Run the
baked teardown, retain its stdout/stderr and verification lines, then repeat
cleanliness and agent checks. Only then ask Herdr to remove without deleting
the branch. A force retry is allowed only for Git's exact initialized-submodule
refusal and after fresh safety checks, not for arbitrary removal failures.
It emits `{status, reason, workspace, worktree, teardown, herdr}`; only `removed`
exits zero. (`modules/registry/_worktree-remove.py:13-20,51-79,82-166`;
`modules/registry/_worktree.nix:577-584`.)

A future runner must prove equivalent checkout identity, preserved work and
quiescent worker state, verified repository cleanup and lease detachment before
removing its owned resources. Replace Herdr-specific checks with evidence from
that runtime; do not bypass the barrier just because a sandbox or pod is
throwaway. Keep failed evidence and escalate rather than deleting uncertain
state. (Safety boundary: `modules/registry/_worktree-remove.py:98-153`.)

## Known gaps

- **No OpenShell or pod runner yet (BPH-66 payload).** The service starter,
  worker launcher and removal barrier call Herdr directly; the shared
  declaration and image packaging are not a transport adapter. No sandbox
  reachability validation or runner-instance lease format is implemented.
  (`modules/registry/_worktree-services.py:80-84,142-157`;
  `modules/registry/_worker-start.py:49-55,109-141`;
  `modules/registry/_worktree-remove.py:37-39,143-146`.)
- **Secret delivery is not abstracted.** Setup unconditionally combines
  `copyFiles` and `secretDotfiles` in the main-checkout copy loop. A future
  runner must resolve secret-backend delivery before reusing that step across
  a trust boundary. (`modules/registry/_worktree.nix:411-428`.)
- **Worker service env is evidence, not automatic injection.** Dependent hooks
  receive env and the setup record retains it; worker-start does not load that
  env into its launcher argv. A future runner must arrange worker consumption
  of the declared connection values explicitly.
  (`modules/registry/_worktree.nix:491,508`;
  `modules/registry/_worker-start.py:72-98,133-138`.)
- **Per-worktree services are not built in Phase 1.** There is no declaration
  for instance scope or per-worktree ports.
  (`modules/registry/_worktree.nix:633-676`.)
- **Cotal run integration is not built here and awaits the Cotal upgrade.**
  Preparation, launch and cleanup currently exchange local records and Herdr
  observations, not Cotal run turns. This is a planned integration boundary,
  not a property of record v2.
  (`modules/registry/_worktree.nix:218-227`;
  `modules/registry/_worker-start.py:57-70`;
  `modules/registry/_worktree-remove.py:164-166`.)
