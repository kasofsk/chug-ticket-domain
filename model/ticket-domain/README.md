# Ticket domain

This folder sketches the ticket lifecycle for a new orchestrator. It begins
with domain concepts rather than a source layout, storage schema, or deployment
vocabulary.

One ticket-domain instance is already scoped to one project partition. Project
identity is an application routing and serialization key and does not enter the
domain state, commands, events, or decisions. Cross-project ticket references
are not representable.

The application provides exactly one active writer for that project partition.
It serializes every decision affecting the ticket graph and every ticket within
it. The domain may therefore evaluate a command against one coherent committed
project position. This is an operational correctness assumption, not evidence
that the complete graph is one lifecycle aggregate.

The intended aggregate boundary and the facts required by each command are
recorded in [Ticket aggregate and decision context](ticket-decision-context.md).

## Boundary

The ticket domain decides how a released ticket advances. It owns:

- dependency gating;
- work cycles and conclusive evaluation results;
- finalization after every successful evaluation;
- escalation, resumption, completion, and revocation;
- domain commands, refusals, events, and obligations for those decisions.

The lifecycle core does not define evaluation's internal stage reduction, but
the current ticket embeds that protocol's state and commits its changes with
ticket transitions.

It does not own:

- draft authoring or release validation;
- command acceptance, authentication, or idempotency;
- journals, streams, projections, or databases;
- automatic selection policy, capacity, placement, or worker attempts;
- evaluation stage rules, fan-out, combination, or evaluator attempts;
- artifact transport, secret delivery, or finalizer internals;
- clocks, infrastructure retries, or deployment topology.

Those exclusions are boundaries, not deferred fields on `Ticket`.

## Language

**Ticket graph** is the project-local model containing tickets and immutable
dependency edges. It is the executable model's decision environment, not a
claim that every complete ticket definition must be loaded or locked as one
persisted aggregate. A decision changes one ticket. Dependency existence and
completion are stable facts read when creation or dispatch needs them.

**Ticket** is one released unit of intent. Its identity is stable and unique
within the enclosing ticket graph.

**Dependency** is another ticket that must complete successfully before this
ticket may begin work. Dependencies are immutable after release: a revision may
not add, drop, or exchange one.

**Revision** numbers the definitions a ticket has held. Creation sets it to 1
and every accepted update increments it by one. It is the ticket's concurrency
token: an update names the revision it was authored against, and the domain
refuses one authored against any other.

**Released ticket** is the complete bounded semantic definition submitted with
`CreateTicket` and replaced wholesale by `UpdateTicket` while the ticket is
still `Pending`. `TicketGraph` stores it with the revision that names which
definition is current and with the ticket's mutable lifecycle state:

```text
ReleasedTicket {
  ticket identity
  authored title and instructions (or an explicit legacy combined-content fact)
  and immutable input bindings
  dependencies
  resolved work configuration
  resolved evaluation plan
  resolved finalizer configuration
}

Ticket {
  definition: ReleasedTicket
  revision: int
  state: TicketState
}
```

The definition contains immutable artifact references rather than image, blob,
repository, or other large bodies. It contains no preset lookup, inheritance,
draft state, YAML syntax, or unresolved authoring reference. Those values are
editor concerns and do not participate in runtime decisions.

Work configuration is a resolved task template. `TicketGraph` binds ticket
content, immutable inputs, work-cycle identity, and any evaluation rework
context when it creates a Work task. The resolved evaluation plan similarly
binds the accepted Work result and, for authored tickets, the same released
content facts when Evaluation begins. Execution derives a provider briefing
from those facts; legacy V2 evaluation records retain an explicitly absent
content context rather than inventing title/instructions. Finalizer
configuration binds the exact evaluated result when Finalization begins.
Runtime never repeats authoring resolution.

```text
WorkInput {
  released content and input bindings
  cause: InitialWork | EvaluationRework(entries) | FinalizationRework(evidence)
  retry evidence
}
```

`Work` holds that input and the workspace source for the cycle. The cycle's *number* is the ticket's
Work-cycle counter, which the transition into Work has already advanced; it is
not stored a second time where it could disagree. The Work task identity is
derived from the ticket and that counter for the same reason.

The first Work cycle has an `InitialWork` input. Later cycles distinguish
`EvaluationRework` from `FinalizationRework`, while retry evidence is retained
separately through Work escalation. Each variant binds the released content and
inputs together with only the evidence meaningful for that cause.
The context is part of the task obligation, so Execution does not reconstruct
domain meaning by querying ticket state.

A `Task` is one logical unit of executable work for which the execution system
owes a result. Work and evaluation share the task contract, but the protocol
that creates a task owns its business meaning. Placement and infrastructure
attempts are below this grain.

The common terminal outcomes are neutral: valid result material was produced,
the process failed to produce it, or execution remained unavailable. `Pass` and
`Fail` belong to the owning work or evaluation protocol. Cancellation is an
owner instruction rather than a task result. A successfully produced evaluator
result may itself contain a failing verdict.

Each ticket `Work` cycle owns exactly one logical work task. The ticket domain
creates that task and interprets its conclusive result. Evaluation may create
multiple evaluator tasks internally without exposing them to the ticket core.

V1 has no separate work protocol. The direct mapping is:

| Work task terminal | Ticket decision |
| --- | --- |
| valid result manifest produced | record it and enter `Evaluation` |
| process failed to produce a result | `Escalated(WorkFailureEscalated)` |
| execution remained unavailable | `Escalated(WorkExecutionUnavailableEscalated)` |

The matching work terminal and transition into `Evaluation` are one
`TicketGraph` decision. That decision constructs the embedded evaluation
instance from the exact accepted work provenance and released plan, then emits
the first stage's generic task obligations:

```text
EvaluationInput {
  owning ticket identity
  accepted result manifest
  released evaluation configuration
}
```

A work task with `PublishRepositoryResult` must return exactly one valid Git
output on its required repository; otherwise the domain refuses the result
with `WorkResultMissingExactGitOutput`. Evaluation uses that output's commit.
For `ReadRepository` work, evaluation uses the source held by the Work cycle.
Both paths retain the accepted manifest and the ticket's released inputs.
Authoring rejects non-publishing work paired with a `git-merge` finalizer;
non-publishing operations use a `no-op` finalizer.

A separate work protocol becomes justified only if Work later gains multiple
tasks, sequencing, aggregation, or a DAG.

During `Evaluation`, evaluator task terminals return to the same `TicketGraph`
partition. The ticket verifies the current evaluation and task identities, then
delegates stage reduction to the pure
[evaluation protocol module](evaluation/). Passing a stage emits the
next stage's task obligations in the same committed decision. A conclusive
`Pass`, `Fail`, or `Blocked` result is interpreted by the ticket lifecycle
in that decision; it is not delivered through a second aggregate or callback.
Evaluator definitions are ordered within a stage so obligation creation and
delivery identities are deterministic; every evaluator in the active stage is
still eligible in parallel.

The separate module gives evaluation logic its own vocabulary and tests. It
does not create a separate aggregate, journal, service, or task kind. There is
no `StartEvaluation` obligation or `ReportEvaluationResult` command.

**Finalization** is the mandatory ticket-visible step after evaluation. It may
be implemented by a no-op finalizer, but the ticket lifecycle always enters the
same phase and sees its conclusive result. The protocol that performs an
irreversible external operation is a separate application operation, not a
domain aggregate.

`TicketGraph` retains the current logical finalization identity and emits its
committed `FinalizeTicket` obligation. That identity is the Work-cycle identity
plus a semantic **currentness generation**, incremented every time an operator resumes a
blocked finalization. Without it the escalate/resume cycle would leave the
abandoned request indistinguishable from the live one, and a late `Succeeded`
from the request the operator walked away from would carry the ticket to `Done`.
Evaluation fences its stage runs the same way. The finalization processor owns durable
preparation, conditional external mutation, and reconciliation, then reports a
closed result under that identity. Only the ticket domain interprets
`Succeeded`, `NeedsWork`, or `Unavailable` as a lifecycle transition. A no-op
finalizer follows this same obligation and result path.

**Escalation** is a named wall requiring an external decision. It is domain
state, not an error or a log message.

Each escalation variant contains only the evidence and resume material legal
for that wall: Work failures and evaluation-policy failures carry Work context,
a blocked evaluation carries the blocked Evaluation, and finalization
unavailability carries the blocked Finalization. Reason/resume mismatches and a
non-resumable escalation are not representable.

An `Obligation` is an instruction emitted by a decision. It is not a fact and
cannot be replayed into ticket state.

## Commands and decisions

Ticket commands use domain language: create a ticket from a released definition,
dispatch a ready ticket for Work, revoke a ticket, resume an escalation, report
a task terminal, or report
a finalization result. The active ticket context determines whether a task
terminal belongs to Work or the embedded Evaluation protocol. Commands are
authorized before durable application acceptance; `TicketGraph` contains no
role, permission, credential, or transport-access model. Command ticket and
obligation identities are business identities, not HTTP idempotency keys, NATS
message identifiers, or consumer sequence numbers.

Commands contain only partition-local ticket and obligation identities. The
application routing envelope may carry a project key, but that key is removed
before the pure decision is invoked.

The domain interface is pure. The application supplies implementations of the
domain-owned policy interfaces selected for its project partition:

```text
decide(current project tickets, domain command, domain policies)
  -> refused(domain reason)
  | decided(domain event, domain obligations)

evolve(current project tickets, domain event)
  -> next project tickets
```

Events are past-tense facts used to rebuild state. Obligations instruct the
outside world and may fail or be delivered repeatedly. Accepted-input records,
settlement, journal positions, and serialization belong to application
processing rather than this interface.

V1 has one such interface, `EvaluationFailurePolicy`. The ticket decider invokes
it only after the embedded Evaluation protocol has conclusively failed. It
returns `ReworkEvaluationFailure` or `EscalateEvaluationFailure` without
changing state or performing effects. The ticket domain applies that result to
the lifecycle. The resulting event records the chosen consequence, so replay
does not invoke the policy again.

The policy is not ticket configuration or aggregate state. Its implementation
may use project-level configuration or facts derived from the committed project
history, but for one serialized decision turn it must behave as a local,
side-effect-free dependency. If it cannot return a disposition, no domain
decision is committed and the accepted input remains recoverable.

The local executable project's default policy is explicitly bounded at **three
total started Work cycles**. It reworks failures from cycles one and two and
escalates a conclusive evaluation failure from cycle three or any legacy
replayed cycle above that bound. The policy reads the existing Work-cycle
identity; provider retries and evaluation stage-run generations do not start a
Work cycle and therefore do not consume this budget. The selected disposition
is still committed as an event, so replay remains independent of the current
policy. `EvaluationFailureEscalated` retains the ordered evaluator entries and
accepted workspace source; resuming it enters a subsequent Work cycle from
that recorded evidence without resetting the counter. This is a project-owned
pure policy input, not aggregate configuration: a future project policy may
select another validated positive bound.

The complete V1 command vocabulary is:

```text
TicketCommand =
  | CreateTicket(ReleasedTicket)
  | UpdateTicket(ticket, expected revision, ReleasedTicket)
  | DispatchTicket(ticket)
  | RevokeTicket(ticket)
  | ResumeTicket(ticket)
  | ReportTaskTerminal(ticket, terminal)
  | ReportFinalizationResult(ticket, finalization, result)
```

`CreateTicket` creates the runtime ticket in `TicketGraph`. Application-level
authoring has already constructed its exact immutable `ReleasedTicket`. Stable
input identity, delivery retry, and durable command settlement remain
application-processing concerns rather than command names or ticket state.

`UpdateTicket` replaces the whole definition of a ticket that has not yet
started work. It carries a complete `ReleasedTicket`, not a patch, so there is
no partial-update vocabulary and no way to express a definition the release
rules do not admit. Three things stay fixed across a revision: the ticket's
identity, its dependencies, and everything already decided about it. The
command is therefore legal only while the ticket is `Pending`; once a work
cycle has started, the definition the work was dispatched against is a
committed fact and the update is refused. An update that carries a definition
identical to the current one is accepted and numbers a new revision: the domain
records that the author reaffirmed the definition rather than silently
discarding the input.

`DispatchTicket` records an explicit choice of what to run next. The accepted
input records whether that choice came from a human, an agent acting on behalf
of a human, or an agent with its own principal identity. That attribution does
not enter ticket state. The application authorizes the action; the domain checks
that the named ticket is currently ready. Dispatch of a blocked, active,
terminal, or unknown ticket is refused.

Only a committed dispatch moves the ticket from `Pending` to `Work` and emits
its work-task obligation. A readiness projection may help principals choose,
but observing readiness never starts work.

`ReportTaskTerminal` is shared by Work and Evaluation; the current ticket
context assigns its meaning. `ReportFinalizationResult` remains separate because
finalization is not a task. There are no commands for retrying attempts,
retrying infrastructure attempts, advancing evaluation stages, marking
completion, or revoking dependent tickets: those are infrastructure operations
or separate domain decisions.

`ResultProduced` reaches this boundary only with an opaque
`ValidatedTaskResult` constructed from the task's obligation after its released
result contract was satisfied. Every terminal carries its logical task identity
exactly once. The ticket domain checks whether that task is current, then
interprets the bounded value in its Work or Evaluation context. It never fetches
artifacts, parses unchecked output, or validates execution-attempt fencing.

## Refusals

The complete initial domain refusal vocabulary is:

```text
TicketRefusal =
  | TicketAlreadyExists(ticket)
  | DependenciesNotFound(ticket, missing dependencies)
  | SelfDependency(ticket)
  | TicketNotFound(ticket)
  | TicketNotPending(ticket)
  | TicketIdentityMismatch(ticket)
  | TicketRevisionStale(ticket, expected revision, current revision)
  | TicketDependenciesChanged(ticket)
  | DependenciesIncomplete(ticket, incomplete dependencies)
  | TicketNotRevocable(ticket)
  | TicketNotResumable(ticket)
  | TaskNotCurrent(ticket, task)
  | FinalizationNotCurrent(ticket, work cycle, generation)
```

Create reports every missing dependency together in one deterministic refusal.
A released ticket may depend only on tickets already present in the graph, and
dependencies never change. A newly admitted node therefore cannot introduce a
cycle, so `DependencyCycle` would be unreachable refusal vocabulary. Graph
acyclicity remains an explicit invariant.

Update refuses in a fixed order: an unknown ticket is `TicketNotFound`, a
ticket past `Pending` is `TicketNotPending`, a definition whose id is not the
named ticket is `TicketIdentityMismatch`, a definition authored against another
revision is `TicketRevisionStale`, and a definition whose dependency set differs
from the stored one is `TicketDependenciesChanged`. `TicketRevisionStale` is the
one refusal that reports state — the current revision — because an author who
lost the race needs it to re-author against.

This admission ordering is an intentional V1 constraint. Forward dependency
references and atomic submission of an unordered DAG are outside V1.

Refusals are state-preserving domain decisions. They are neither exceptions nor
successful no-ops. A repeated business command submitted under a new application
input identity is evaluated against current state: creating an existing ticket
is `TicketAlreadyExists`, while reporting a consumed or superseded obligation is
`TaskNotCurrent` or `FinalizationNotCurrent`.

A refusal retains only the immutable facts needed to explain it. The aggregate's
current state is derived from its preceding event prefix and is not copied into
a refusal payload.

Malformed wire input never becomes a domain command. Authorization denial and
input-identity conflict are application outcomes. Broker, storage, and executor
failures are operational failures. Exact delivery retries reuse their input
identity and observe the original durable settlement rather than invoking the
domain again.

## Events

Every successful V1 command produces exactly one semantic event describing its
complete atomic domain consequence. A refusal produces no event.

```text
TicketEvent =
  | TicketCreated(definition)
  | TicketUpdated(ticket, revision, definition)
  | TicketDispatched(ticket)
  | TicketRevoked(ticket)
  | TicketWorkResumed(ticket)
  | TicketEvaluationResumed(ticket)
  | TicketFinalizationResumed(ticket)
  | TicketWorkResultAccepted(ticket, result)
  | TicketWorkProcessFailed(ticket, task, evidence)
  | TicketWorkExecutionUnavailable(ticket, task, evidence)
  | TicketEvaluationProgressed(terminal)
  | TicketEvaluationPassed(terminal)
  | TicketEvaluationReworkStarted(terminal, rework entries)
  | TicketEvaluationFailureEscalated(terminal, rework entries)
  | TicketEvaluationBlocked(terminal)
  | TicketFinalizationSucceeded(ticket, finalization, evidence)
  | TicketFinalizationNeedsWork(ticket, finalization, evidence)
  | TicketFinalizationUnavailable(ticket, finalization, evidence)
```

Each variant represents one legal fact rather than pairing a terminal or result
with an independently selectable consequence. Replay derives the fixed
lifecycle meaning of that fact: for example, `TicketWorkProcessFailed` always
enters the Work-failure escalation, while `TicketEvaluationPassed` always enters
Finalization. The event vocabulary therefore cannot represent a Work process
failure that entered Evaluation or a successful finalization that started
rework.

These events carry causes and selected consequences, never derived post-state.
`evolve` applies the same pure protocol reduction used by `decide`; therefore a
terminal cannot be paired with an independently supplied `EvaluationInstance`
that says something else. A terminal that passes an evaluation stage and
creates the next stage's tasks is one `TicketEvaluationProgressed` fact.
Revoking one ticket is one `TicketRevoked` fact. `TicketUpdated` carries the
new revision, so replay does not recompute it: an event whose revision is not
one past the stored one names no reachable state and is ignored. The event carries every newly
chosen domain identity needed for deterministic replay, but never repeats an
identity already carried by a terminal or validated result.

A committed successful decision stores the event beside zero or more
obligations. Replaying the event rebuilds `TicketGraph`; recovering the
obligations rebuilds external delivery work. Replaying an event never executes
an obligation.

Reconstruction uses checked semantic constructors. A task-bearing command or
event must route through the same ticket that owns its task identity, Work and
Evaluation payloads must carry the corresponding task kind, and every
obligation in a successful decision must belong to that decision's ticket.
Consequently persisted outcomes cannot represent cross-kind or cross-owner
task combinations even when their bytes are hostile.

## Obligations

The complete V1 obligation vocabulary is deliberately small:

```text
TicketObligation =
  | ExecuteTask(ticket, task obligation)
  | FinalizeTicket(ticket, finalization operation, configuration)
  | CancelTask(ticket, task)
```

`ExecuteTask` requests one logical task using the shared task contract. The
obligation carries its owning ticket so Execution can return a terminal without
interpreting the event or querying ticket state. Work and Evaluation emit the
same obligation; their ticket context determines what the terminal means.

`FinalizeTicket` requests one logical, statically defined finalization. The
operation contains its immutable accepted input exactly once; the obligation
adds the released configuration. It is handled by
finalization processing rather than treated as an ordinary task.

`CancelTask` withdraws authority from one logical task. It may be emitted for a
revoked Work task or for outstanding parallel evaluators when their evaluation
is abandoned. The state change makes the task non-current immediately;
cancellation merely stops unnecessary external work. A late terminal remains
`TaskNotCurrent` even if physical cancellation is delayed or fails.

Escalation does not emit a `RequestIntervention` obligation. It is already a
durable domain fact and state. User-interface queues, notifications, assignment,
and paging are application projections and policy rather than a required ticket
effect.

Task and finalization identities are semantic domain identities. Delivery
identity is application provenance: the committed decision position plus the
obligation's zero-based ordinal within that decision. Redelivery therefore
addresses the same instruction, while a new domain task or finalization always
has a new semantic identity. Transport message IDs, broker sequence numbers,
executor attempts, and Nomad allocation IDs never enter the obligation.

## Logical identities

`TicketGraph` creates every runtime logical identity. Commands do not supply
child identities, and the pure decision does not call a random or external ID
allocator. Identities are structured by semantic parentage:

```text
WorkCycleIdentity = (ticket, ticket-local cycle number)

TaskIdentity =
  | WorkTask(ticket, work cycle)
  | EvaluationTask(ticket, work cycle, stage key, stage-run generation, evaluator key)

EvaluationIdentity = WorkCycleIdentity

FinalizationIdentity = WorkCycleIdentity
```

Each ticket retains the number of Work cycles it has started. Dispatch, rework,
finalization-requested work, and resumption into Work increment it exactly once.
All other decisions preserve it. The first Work cycle is number one.

Everything else derives without another ticket-level counter. One Work cycle
owns one Work task and can create one Evaluation from its accepted result.
Stable stage and evaluator keys distinguish evaluator tasks within that
Evaluation; a stage-run generation distinguishes tasks recreated after
unavailability. A passed Evaluation creates one Finalization. Application
validation and the `CreateTicket` boundary require the keys used by these
identities to be unique.

Events record their required semantic parents; child identities derive from
those parents, so evolution performs no allocation and replay is deterministic.
Provider-specific retry retains the logical task identity. It creates no
application or domain generation.
Committed decision positions, obligation ordinals, UUID encodings, NATS IDs,
and Nomad allocation IDs remain separate identities at their own boundaries.

## Lifecycle

`Ready` and `Blocked` are derived views over `Pending`, not stored phases.

```text
                         dependencies incomplete
                                  |
                                  v
CreateTicket(ReleasedTicket) ─> Pending <─ UpdateTicket, a new revision
                                  |
                                  | dependencies complete
                                  | + explicit DispatchTicket
                                  v
                                 Work
                                  |
                                  | work passed
                                  v
                              Evaluation
                                  |
                                  | evaluation passed
                                  v
                             Finalization
                            /      |       \
             needs rework /       |        \ infrastructure failure
                         v         |         v
                       Work        |      Escalated
                                   | succeeded
                                   v
                                  Done

An active `Work`, `Evaluation`, or `Finalization` phase may reach `Escalated`
when a modeled wall is hit.
Escalated may resume only at the recorded lifecycle point. Revocation is legal
from every non-terminal phase except `Finalization`; it settles a ticket without
success and makes every live task non-authoritative. Once finalization begins,
only a finalization result may advance the ticket: success enters `Done`, a
content conflict requiring new work returns to `Work`, and an infrastructure
failure enters `Escalated`.
```

Revocation changes only the named ticket. A pending dependent of a revoked
ticket remains `Pending` and is consequently blocked because not every
dependency is `Done`. It can be revoked later through its own command. No
invariant requires a transitive closure to change atomically, and leaving a
blocked ticket inert cannot start work or grant task authority.

Revocation is intentionally unavailable during active `Finalization`. An
external mutation may already be ambiguous, so the operator must let processing
reach a conclusive result or `Escalated(FinalizationUnavailableEscalated)`.
Revocation is legal from that escalation.

Failure and identity terms are deliberately distinct:

- a **provider retry** repeats infrastructure execution of the same logical
  task and does not change ticket state;
- **rework** starts a new `Work` cycle because completed output must change;
- **resume** is an authorized exit from `Escalated` to its recorded phase.

Provider retry retains the work-cycle and task identities without changing the
domain model. Evaluation rework and finalization-requested
work each create a new work-cycle identity and a new task identity.

The initial result policy is:

| Phase | Conclusive result | Next phase |
| --- | --- | --- |
| `Work` | passed | `Evaluation` |
| `Work` | failed | `Escalated(WorkFailureEscalated)` |
| `Work` | execution unavailable | `Escalated(WorkExecutionUnavailableEscalated)` |
| `Evaluation` | passed | `Finalization` |
| `Evaluation` | criteria failed; policy returns rework | start a new `Work` cycle |
| `Evaluation` | criteria failed; policy returns escalate | `Escalated(EvaluationFailureEscalated)` |
| `Evaluation` | an evaluator failed to produce a result | `Escalated(EvaluationBlockedEscalated)` |
| `Evaluation` | an evaluator was never executed | `Escalated(EvaluationBlockedEscalated)` |
| `Finalization` | succeeded | `Done` |
| `Finalization` | content needs modification | a new `Work` cycle |
| `Finalization` | infrastructure unavailable | `Escalated(FinalizationUnavailableEscalated)` |

Rework invalidates the prior evaluation result. After the new work passes, its
accepted result creates a new embedded evaluation instance and first-stage task
obligations.
An executor may report `ExecutionUnavailable` only as its conclusive terminal;
delivery retry and adapter unavailability are not ticket transitions.

Only a conclusive evaluation failure consults `EvaluationFailurePolicy`.
Provider retry, operational unavailability, Work failure, operator resume, and
finalization-requested work do not. A policy-selected evaluation-failure
escalation carries only Work resumption context, so resumption returns to
`Work`, never directly to `Evaluation`.

The initial phase set is:

| Phase | Meaning |
| --- | --- |
| `Pending` | Created and either dependency-blocked or ready for explicit dispatch |
| `Work` | Holds one work cycle with exactly one logical work task |
| `Evaluation` | Embeds the evaluation protocol state for the accepted work result |
| `Finalization` | Retains the logical finalization identity while its processor obtains a conclusive result |
| `Escalated` | Parked at a named wall with an explicit resume target, if any |
| `Done` | Successfully complete |
| `Revoked` | Settled without success by explicit authority |

`Done` and `Revoked` are the only terminal states, and both are absorbing.

## Initial invariants

- A ticket identity is never reused.
- A newly created ticket has started zero Work cycles; every transition into a
  new Work cycle increments its ticket-local number exactly once.
- Work cycle, task, Evaluation, and Finalization identities follow their
  semantic parentage and are never reused for different logical work.
- Every ticket retains one complete released definition, immutable in place: a
  revision replaces it wholesale while the ticket is `Pending`, and once work
  has started the definition it was dispatched against never changes again.
- A ticket's revision starts at 1 and increases by exactly one per accepted
  update; an update never starts a work cycle, so a `Pending` ticket at any
  revision has still started zero.
- A revision preserves the ticket's identity and its dependency set.
- Runtime obligation construction requires no preset, draft, configuration, or
  artifact-body lookup.
- One ticket graph contains tickets from exactly one application partition and
  carries no project identity of its own.
- Dependencies exist, are acyclic, and are immutable after release.
- A ticket is ready exactly when it is pending and every dependency is done.
- Ready and blocked are derived views; observing readiness does not change
  ticket state.
- Only an application-authorized and durably accepted `DispatchTicket` command
  may reach the domain; only the domain may move a ready ticket from `Pending`
  to `Work` and emit its work-task obligation.
- Dispatching a ticket whose dependencies are incomplete is refused.
- Only `Work` carries a live work task.
- Each work cycle owns exactly one logical task.
- Every live work task belongs to the current work cycle.
- The ticket's Work-cycle counter is the only stored cycle number; the live
  cycle's number, its task identity, and the embedded Evaluation's identity are
  all derived from it.
- Task completion is idempotent by logical task identity.
- A valid produced work result creates Evaluation with the exact work-cycle,
  task, and result-manifest provenance.
- Creating Evaluation and entering its first running stage with task obligations
  are one `TicketGraph` decision.
- An evaluator terminal, the corresponding embedded evaluation update, and any
  next-stage task obligations are one `TicketGraph` decision.
- A conclusive evaluation result and its ticket lifecycle transition are one
  `TicketGraph` decision; no separate evaluation conclusion is delivered.
- A conclusive evaluation failure consults the supplied failure policy exactly
  once during its serialized decision turn and applies either rework or
  escalation in that same decision.
- The committed event records the selected failure consequence; replay never
  invokes the failure policy.
- Process failure and exhausted execution availability enter their distinct
  **work** escalations, because a Work escalation's evidence is opaque and the
  variant name is the only place its cause can live. Evaluation keeps a single
  `EvaluationBlockedEscalated` wall: the retained instance already records each
  evaluator's cause, and one stage may hold both at once.
- Cancellation is not a task terminal. Revocation withdraws task authority in
  the state transition before emitting `CancelTask`.
- Infrastructure retries retain work-cycle and task identity and create no
  domain generation.
- Evaluation rework and finalization-requested work create a new work-cycle and
  task identity.
- `Done` and `Revoked` never transition again.
- Every successful evaluation enters `Finalization`.
- Entering `Finalization` and emitting its stable obligation are one
  `TicketGraph` decision.
- Finalizer preparation, external observations, conditional mutation, and
  reconciliation are application state, not ticket state.
- A reported finalization result is authoritative only for the current logical
  finalization identity **and its currentness generation**. Resuming a
blocked finalization increments that generation, so a result from the
abandoned request is refused as `FinalizationNotCurrent`.
- Only successful finalization enters `Done`.
- Finalization that requires a content change returns to `Work` with a new work
  cycle; a merge conflict that cannot be resolved mechanically is one example.
- Finalization infrastructure failure enters `Escalated`.
- Revocation is legal from every non-terminal phase except `Finalization`.
- A ticket in `Finalization` cannot be revoked.
- Revocation changes only the named ticket and withdraws its live task authority.
- A pending dependent of a revoked ticket remains pending and is not ready.
- Each escalation variant fixes both its reason and its only permitted resume
  phase; mismatched reason/resume combinations are not representable.
- An escalation's resume material is judged by the same predicate its resume
  will apply, so a wall cannot hold an input its own resumption would reject.
- Infrastructure failure during evaluation resumes the same embedded evaluation
  identity at its protocol-owned recovery point. It increments the active
  stage-run generation, retains passed evaluator results, and recreates only
  process-failed or execution-unavailable evaluator tasks.
- Rework creates a new embedded evaluation instance after the new work cycle
  passes.
- Policy-selected evaluation rework creates a new `Work` cycle.
- Policy-selected evaluation escalation carries the failed evaluators' rework
  entries; resumption rebuilds the Work input from them and enters `Work`, not
  `Evaluation`.
- The rework entries are recorded on the committed event, so replay replays them
  rather than re-deriving them from evaluation state.
- Revocation cancels the embedded evaluation instance and withdraws the
  authority of its outstanding tasks in the same ticket decision.
- Every emitted obligation is attributable to the decision that emitted it, and
  agrees with the state that decision produced: a task is requested only if the
  evolved state holds it live, a cancellation only for a task the decision
  withdrew, a finalization only for the operation now held.
- Every task obligation and cancellation names its owning ticket and logical
  task; every finalization obligation names its owning ticket and logical
  finalization.

## Executable model

[ticket.qnt](./ticket.qnt) implements the ticket graph as two total pure
functions over well-formed domain values:

```text
decide(graph, command, policies) -> refusal | { event, obligations }
evolve(graph, event)             -> graph
```

The Quint model passes the pure `EvaluationFailurePolicy` function to `decide`.
The decider calls it only after Evaluation reaches a conclusive failure. The
returned disposition is not a field of `TicketCommand`, ticket configuration,
or persisted aggregate state.

`evolve` is **partial by contract**: its domain is exactly the events `decide`
emitted for that graph, applied in commit order. It is written as a total
function because the language requires one, and every branch is inert on a
pairing `decide` could not have produced. The executable implementation also
exposes checked historical evolution: an inert pairing is rejected instead of
being accepted as recovered state. That check covers facts reconstructible
from the preceding graph and immutable event identities, including task,
cycle, generation, result context, and evaluation reduction. It does not rerun
authorization or evaluation-failure policy because their historical inputs are
not stored; the selected policy consequence is already an event fact.
`decisionValid` separately holds live `decide` results to the invariant.

`decide` selects all new semantic identities and returns exactly one event for
a successful command. A refusal emits neither an event nor obligations.
`evolve` consumes events only and performs no lookup, allocation, delivery, or
other effect. `applyCommand` composes the two functions for executable tests;
it is not another production boundary. Boundary validation ensures a
`ReleasedTicket` or `ValidatedTaskResult` is well formed before the domain
command is constructed.

[ticket_tests.qnt](./ticket_tests.qnt) exercises the happy path, both evaluation
failure-policy dispositions, a blocked evaluation and its recovery, Work process
failure and execution unavailability with their resumptions, finalization
recovery, a stale finalization attempt being refused, `evolve` staying inert on
a pairing `decide` could not produce, and blocked dependents after revocation.

Two invocations, and neither subsumes the other:

```sh
quint test ticket_tests.qnt
quint run --invariant=modelInvariant --max-steps=25 --max-samples=400 \
  ticket_tests.qnt
```

The first runs the named scenarios; run names end in `Test` because that is what
Quint's default filter selects, and a suite whose names do not match reports
success having executed nothing.

The second drives random traces from `step`. `modelInvariant` is
`graphInvariant` over the reached state **and** `decisionValid` over the
recorded prior state and decision. `decisionValid` is deliberately not an action
guard: as a guard it removes an offending transition from the search space, so
a defect disables the step instead of failing the trace, and the run reports no
violation. Its obligation clause also requires each obligation to *agree* with
the state the same decision produced — work requested only for a task the
evolved state holds live, cancellation only for one the decision withdrew,
finalization only for the operation now held.

## Decisions outside this model

The initial ticket lifecycle has no remaining qualitative transition decision.
The project supplies the ticket domain's local evaluation-failure policy; the
lifecycle owns applying and recording its returned disposition. Finalizer
recovery belongs to the finalization processor;
durable commit and obligation delivery belong to application-level project
decision processing and its delivery boundary. V1 has no work protocol between
the ticket decision and its one logical work task.
