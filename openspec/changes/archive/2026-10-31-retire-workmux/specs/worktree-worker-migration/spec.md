## ADDED Requirements

### Requirement: Single-owner replacement workflow
The replacement workflow SHALL assign one accountable owner per responsibility:
Herdr for workspace/worktree/pane lifecycle and terminal inspection; repository
tooling for setup, environment, evidence and integration; existing launchers for
harness and profile selection; each harness for its native reasoning and session
history; Cotal for
addressed messaging and any selected durable coordination journal. Missing
barriers SHALL be explicit named gaps rather than claimed native parity. The
workflow MUST NOT introduce another monolithic manager or competing execution
journal. Installed-version help and source SHALL ground native capability claims.

#### Scenario: Native capability is not sufficient
- **WHEN** a native created event exists but does not wait for repository setup
- **THEN** the capability map identifies the missing setup barrier and its proposed owner instead of claiming the event proves readiness

#### Scenario: Direct native use
- **WHEN** the operator starts Pi or operates Herdr without a mesh workflow
- **THEN** native reasoning, sessions and terminal/worktree operations remain available without a mandatory replacement framework

### Requirement: Observable startup and accepted assignment
Readiness SHALL be distinct from presence, heartbeat, idle, terminal detection
and broker message storage. Before accepting implementation work the workflow
SHALL bind the repository, checkout, workspace, pane, native harness session, peer incarnation,
assignment and attempt; confirm setup; observe trust/auth/setup blockers before
model or project extensions are available; and obtain a correlated acceptance.
Pi trust projection SHALL cover the checkout and its repository worktree parent.
It SHALL preserve explicit denials. Missing or failed projection SHALL only warn
and MUST NOT block launch. An actual harness trust prompt SHALL remain an
acceptance blocker until resolved. No global project auto-trust, implicit
credential or model fallback, or terminal injection presented as an accepted
assignment SHALL be used.

#### Scenario: Trust prompt before startup completes
- **WHEN** a worker stops at a project-trust prompt while roster presence appears idle
- **THEN** the coordinator observes a blocked or unconfirmed launch and routes the decision to the operator seat without dispatching duplicate workers or bypassing trust

#### Scenario: Trust projection failure only warns
- **WHEN** Pi trust projection is missing or fails
- **THEN** the launcher emits a warning and still launches Pi
- **AND** the workflow checks whether the actual harness accepts the assignment rather than treating the warning as a launch gate

#### Scenario: Correlated question and follow-up
- **WHEN** a uniquely addressed worker asks a question about an accepted attempt
- **THEN** the question, operator answer and coordinator follow-up remain correlated to that attempt and reach only its intended worker session

### Requirement: Repository preparation and cleanup survive retirement
Every supported worktree creator SHALL invoke one repository-owned setup
implementation and await its result before harness launch. Submodule setup,
per-worktree hooks, writable environment/service state, safety policy and copied
sensitive-file isolation SHALL remain covered by tests. Shared Nix store caching
MAY be reused; writable worktree state MUST NOT be shared. Repository-owned
external-resource cleanup SHALL complete before native checkout removal; failure
SHALL veto removal. Ambiguous ownership or dirty state MUST NOT trigger automatic
adoption or force-removal.

#### Scenario: Submodule and shared hook regression
- **WHEN** fresh recursive-submodule or linked-submodule worktrees enter their shells repeatedly
- **THEN** preparation either completes with correct per-worktree hooks and state or exposes a failure before work starts, without breaking other worktrees' hooks

#### Scenario: Cleanup fails
- **WHEN** a repository cleanup action fails or resource ownership cannot be established
- **THEN** removal is withheld, evidence and resources are preserved, and the coordinator receives the blocker

### Requirement: Recovery preserves attempt ownership
Reconnect and continuation SHALL reconcile the actual session and resource
bindings before creating or reassigning work. Duplicate/redelivered messages
SHALL NOT create duplicate workers. A held automatic delivery SHALL remain an
explicit blocker even with a healthy transport. Replacement SHALL first fence
the old attempt and explicitly transfer unresolved work; a new same-name peer
MUST NOT be assumed to inherit its predecessor's inbox or session.

#### Scenario: Delivery remains held after reconnect
- **WHEN** transport reconnects but the queued steer has not been accepted or committed
- **THEN** the attempt remains held for reconciliation and is not reported ready or completed merely because presence is fresh

#### Scenario: Create result is uncertain
- **WHEN** a worktree creation response is lost or the coordinator restarts
- **THEN** the coordinator inspects existing owned Herdr/Git resources and resumes the binding or escalates uncertainty instead of blindly creating a second worker

### Requirement: Evidence and integration retain governance
Workers SHALL report results/blockers/questions to their coordinator. Decisions
SHALL route through the operator seat. Repository coordinators SHALL inspect
actual changes and verification evidence independently and serialize integration
within their authorized repository scope. Cross-repository changes SHALL be
coordinated with the owners. Terminal idle/done, notifications, expiry or stored
messages MUST NOT authorize merge or deployment. Existing checks, applicable CI
and approval boundaries SHALL survive migration. `/worktree` SHALL mean coordinator-run
Herdr worktree creation. `/merge` SHALL mean the coordinator's reviewed merge.
Workers MUST NOT self-merge. Rewritten coordinator, merge and rebase skills SHALL
follow those meanings and MUST NOT retain legacy verification-bypass defaults.

#### Scenario: Worker reports completion
- **WHEN** a worker reports a result or a pane becomes idle
- **THEN** the coordinator verifies the diff, exact HEAD and check evidence before authorized integration, rerunning required checks after rebase

### Requirement: Reversible staged retirement qualification
Retirement SHALL cover Pi, Claude Code, Codex and OpenCode together. Each
harness SHALL qualify its launch, status, blocked-input and recovery paths.
Retirement SHALL require a reviewed scope, additive compatibility, disposable
recovery and cleanup tests, one useful change end to end, and a two-worker
routing and writable-worktree isolation test. Each stage SHALL have a rollback path
that preserves active worktrees, branches, sessions and attempts. Selected
rollout repositories SHALL cease requiring Workmux before final removal;
any dependency found during migration SHALL be recorded with its owning
repository and removed before final retirement. There SHALL be no non-Pi
carve-out. Removals outside core SHALL remain proposals until approved and
performed by those owners.
Implementation and retirement approval SHALL be separate from planning artifact
completeness.

#### Scenario: Two workers qualify routing
- **WHEN** two workers receive interleaved assignments, questions and follow-ups
- **THEN** each produces independently inspected evidence in its own writable worktree with no cross-routing, shared state or duplicate worker creation

#### Scenario: Qualification fails or compatibility remains
- **WHEN** recovery, cleanup, checks or a selected consumer fails qualification
- **THEN** retirement stops for all harnesses, the dependency remains explicit until resolved, and prior configuration can be restored for future launches without stealing active attempts

#### Scenario: One harness still needs a Workmux status hook
- **WHEN** any Pi, Claude Code, Codex or OpenCode path still needs a Workmux hook, profile, skill or registry entry
- **THEN** the shared retirement gate fails even if the other three harnesses pass

### Requirement: Independent watcher escalates coordinator attention
The infrastructure repository SHALL provide a bounded non-LLM watcher under
G3/G4. It SHALL run outside model turns and observe connector queue progress,
held-delivery reasons, bound Herdr pane state, explicit harness conditions and
assignment or authoritative run deadlines. It SHALL report missing diagnostics
as unavailable rather than infer health from presence. The watcher SHALL DM the
bound operator-seat coordinator when work is held or expires, or a session
stops consuming turns, including a provider rate limit. The seat SHALL raise
the issue with the operator.

The DM SHALL identify the escalation, assignment, attempt, peer incarnation,
native session, workspace and pane. It SHALL include a bounded reason, observation
time, applicable deadline and evidence references. It MUST NOT expose credentials
or raw terminal dumps. Retries and replies SHALL retain correlation and tolerate
duplicate transport delivery. A missing or stale supervisor binding SHALL remain
a visible routing blocker; a human toast alone MUST NOT count as DM delivery.
The watcher MUST NOT inject prompts, answer trust dialogs, replace workers,
merge code or deploy. It SHALL use existing attempt and run evidence rather
than create a competing journal.

#### Scenario: Provider rate limit stops turn consumption
- **WHEN** a bound coordinator reports a provider rate limit and stops consuming turns
- **THEN** the watcher DMs the correct operator seat with the attempt and observations, and the seat raises the issue with the operator
- **AND** no watcher action restarts the model or creates another worker

#### Scenario: Observer restarts with a held delivery
- **WHEN** the watcher restarts while an escalation remains unresolved
- **THEN** it reuses the attempt binding, deadlines and escalation identity and reconciles the operator-seat binding before retrying
- **AND** duplicate DM delivery does not repeat recovery actions
