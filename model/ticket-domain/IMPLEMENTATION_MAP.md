# Implementation map

From the four Quint models to the TypeScript implementation. The models are the
specification; this file fixes names and records what a transcription must
decide. Locations are `file:line` as of M1, except in `task-contract/task.qnt`
and `ticket-domain/evaluation/evaluation.qnt`, which moved in M5 (D8) and are
quoted at their current lines here and in the transcribing modules.
Two conventions remove most wrapper noise: a sum whose variant wraps one
record becomes a union of frozen classes with a literal `kind` discriminator; and
`int > 0` means "a present opaque reference", so each becomes a
positive-checked branded number type (`TicketId`, `CycleNumber`, `Generation`, `StageKey`,
`EvaluatorKey`, `ContentRef`, `Digest`) and the model's positivity predicates
disappear into constructors. Modules: `chug.domain.task`,
`chug.domain.evaluation`, `chug.domain.ticket` (pure; no I/O, no clocks, mints
no identifiers), and `chug/app/{store,writer}.ts`; `ticket` imports `task` and
`evaluation`, never the reverse.

Git finalization additionally records the derived release fact by advancing
`refs/chug/release` to its observed merge commit. The ref is outside the ticket
model: it is deployment input produced only by a successful finalization, not
a lifecycle state.

## 1. Task contract — `chug.domain.task` (`task-contract/task.qnt`)

| Model | At | TypeScript | Meaning |
| --- | --- | --- | --- |
| `WorkTaskIdentity`, `EvaluationTaskIdentity` | :4, :6 | `WorkTaskId`, `EvaluationTaskId` | (ticket, cycle); (ticket, cycle, stage, generation, evaluator) |
| `TaskIdentity` | :14 | `TaskId = WorkTaskId \| EvaluationTaskId` | the two logical task kinds |
| `GitAccess`, `ExecutionRequirements` | :18, :20 | same names | repository + read-only or publish-result + required capability set |
| `WorkspaceSource`, `OutputRef`/`GitOutput`, `TaskDefinition` | :22, :24, :26 | same names | repository + exact commit; workload, inputs, requirements, result contract |
| `TaskObligation` | :33 | `TaskObligation` | identity, definition, source, context |
| `ResultFinding` | :43 | `ResultFinding` | one structured item of a produced result; see D8 |
| `ValidatedTaskResult`, `TaskFailure` | :45, :53 | same names | obligation+manifest+outputs+value+findings; task+evidence |
| `TaskTerminal` | :58 | `TaskResultProduced \| TaskProcessFailed \| TaskExecutionUnavailable` | the only conclusive task outcomes |
| `taskOwner`, `terminalTask` | :63, :131 | `task_owner`, `terminal_task` | owning ticket; reported task |
| `taskIdentityValid`, `taskDefinitionValid`, `terminalValid` | :68, :78, :153 | constructors | positivity, on build |
| `taskObligationValid` | :95 | `TaskObligation.__post_init__` | source repository equals the definition's |
| `validatedTaskResult` | :103 | `ValidatedTaskResult.produce` | the only builder, from an obligation |
| `exactGitOutput`, `hasExactGitOutput` | :117, :122 | `exact_git_output -> WorkspaceSource \| None` | one Git output on the obligation's repository |
| `resultFindingValid`, `resultFindingsValid` | :137, :146 | `ResultFinding.__post_init__`, `ValidatedTaskResult.__post_init__` | positive, unique, at most `FINDING_LIMIT` |
| `readsRepository`, `publishesRepositoryResult` | :84, :88 | — | defined, unused by the model; see D4 |

## 2. Evaluation protocol — `chug.domain.evaluation` (`ticket-domain/evaluation/evaluation.qnt`)

| Model | At | TypeScript | Meaning |
| --- | --- | --- | --- |
| `EvaluatorDefinition`, `StageDefinition`, `EvaluationPlan` | :6, :11, :16 | same names | released plan: ordered non-empty stages of non-empty evaluators |
| `EvaluationInput`, `EvaluationReason` | :20, :26 | `EvaluationInput`, `SummaryReason \| ExitCodeReason` | ticket, accepted manifest, accepted source; why an evaluator passed or failed |
| `EvaluationResultDetail`, `EvaluationFailureDetail` | :28, :36 | `PassDetail`, `FailDetail` | only a failure carries findings |
| `EvaluatorResult` | :42 | `EvaluatorPassed \| EvaluatorFailed` | the verdict |
| `EvaluatorStatus` | :46 | `Awaiting \| Produced \| EvaluatorProcessFailed \| EvaluatorExecutionUnavailable` | exactly one per evaluator per stage run |
| `EvaluationFinding`, `EvaluationReworkEntry`, `findingValid`, `findingsValid` | :59, :52, :395, :398 | same names, validity in constructors | a finding (unique ids, at most 32); one failed evaluator's feedback |
| `StageRun`, `EvaluationProgress` | :64, :70 | same names | stage index/generation/statuses; completed + active |
| `EvaluationState` | :75 | `Running \| EvaluationPassed \| EvaluationFailed \| EvaluationBlocked` | one conclusive result |
| `EvaluationInstance` | :81 | `EvaluationInstance` | work cycle, input, plan, state |
| `evaluatorTaskIdentity`, `taskIdentityFor`, `evaluatorKeyForTask` | :88, :102, :119 | `evaluator_task_id`, `task_id_for`, `evaluator_key_for_task` | derive an evaluator task id and invert it |
| `initialStageRun`, `begin`, `statusAwaiting/Failed/Blocked`, `stageHas*`, `stagePassed` | :128, :485, :140-:169, :444 | `initial_stage_run`, `begin`, `is_awaiting`, `is_failed`, `is_blocked`, `stage_has_*`, `stage_passed` | start a stage or instance; status predicates |
| `taskCurrent` | :179 | `task_current` | only an awaiting task of the active stage |
| `decodeEvaluatorResult` | :300 | `decode_evaluator_result` | result contract -> verdict; see D2 |
| `reportProduced`, `reportWithoutResult`, `concludeStage`, `applyTerminal` | :189-:329 | `apply_terminal` and private helpers | the one reduction entry point: record, then conclude |
| `resumeBlocked`, `currentTaskObligations` | :331, :361 | same names | +1 generation, blocked evaluators back to awaiting; obligations for awaiting evaluators |
| `failedEntries`, `reworkEntries` | :379, :408 | `failed_entries`, `rework_entries` | feedback from the concluded failing stage |
| `stageKeysUnique`, `evaluatorKeysUnique`, `planValid`, `planUsesRepository` | :502-:527 | `validate_plan` | release-time plan validation |
| `stageRunInvariant`, `completedHistoryInvariant`, `stateHistoryInvariant`, `invariant` | :418-:533 | `evaluation_invariant` | tests and `chug check`, not every call |

## 3. Ticket domain — `chug.domain.ticket` (`ticket-domain/ticket.qnt`)

| Model | At | TypeScript | Meaning |
| --- | --- | --- | --- |
| `ReleasedContent` | :9 | `AuthoredContent \| LegacyContent` | title+instructions, or one legacy blob; see D1 |
| `ReleasedWorkInput`, `WorkInput`, `WorkExecution` | :13, :23, :29 | same names | released material; + cause + retry evidence; + source |
| `WorkCause` | :18 | `InitialWork \| EvaluationRework \| FinalizationRework` | why this cycle exists |
| `FinalizationOperation` | :31 | `FinalizationOperation` | work cycle, generation, input manifest, source |
| `EvaluationFailureDisposition`, `EvaluationFailurePolicy` | :38, :42 | `FailureDisposition`, `EvaluationFailurePolicy` | project policy, pure, consulted once |
| `WorkEscalation`, `EvaluationFailureEscalation`, `FinalizationEscalation` | :44, :50, :55 | same names | per-wall resume material |
| `Escalation` | :60 | `WorkFailureEscalated \| WorkExecutionUnavailableEscalated \| EvaluationFailureEscalated \| EvaluationBlockedEscalated \| FinalizationUnavailableEscalated` | the five walls |
| `ReleasedTicket`, `Ticket`, `TicketGraph` | :63, :82, :95 | same names | release; + `revision` + `work_cycles_started` + state; tickets by id |
| `TicketState` | :77 | `Pending \| Work \| Evaluation \| Finalization \| Escalated \| Done \| Revoked` | the phases |
| `TaskTerminalReport`, `FinalizationResult`, `FinalizationResultReport` | :94-:104 | same names | inbound reports |
| `TicketCommand` | :108 | `CreateTicket \| UpdateTicket \| DispatchTicket \| RevokeTicket \| ResumeTicket \| ReportTaskTerminal \| ReportFinalizationResult` | the complete vocabulary |
| `TicketRefusal` (15) | :143 | `TicketAlreadyExists \| DependenciesNotFound \| SelfDependency \| TicketNotFound \| TicketNotPending \| TicketIdentityMismatch \| TicketRevisionStale \| TicketDependenciesChanged \| DispatchSourceRepositoryMismatch \| DependenciesIncomplete \| TicketNotRevocable \| TicketNotResumable \| TaskNotCurrent \| WorkResultMissingExactGitOutput \| FinalizationNotCurrent` | state-preserving domain outcomes |
| `TicketEvent` (18) | :195 | `TicketCreated \| TicketUpdated \| TicketDispatched \| TicketRevoked \| TicketWorkResumed \| TicketEvaluationResumed \| TicketFinalizationResumed \| TicketWorkResultAccepted \| TicketWorkProcessFailed \| TicketWorkExecutionUnavailable \| TicketEvaluationProgressed \| TicketEvaluationPassed \| TicketEvaluationReworkStarted \| TicketEvaluationFailureEscalated \| TicketEvaluationBlocked \| TicketFinalizationSucceeded \| TicketFinalizationNeedsWork \| TicketFinalizationUnavailable` | one fact per accepted command |
| `Obligation` | :213 | `ExecuteTask \| FinalizeTicket \| CancelTask` | instructions, never replayed into state |
| `TicketDecision` | :223 | `TicketRefused \| TicketDecided(event, obligations)` | flattened |
| `releasedTicketValid`, `releasedContentValid`, `finalizationResultValid`, `commandValid` | :254-:298 | `validate_release`, `validate_command` | boundary checks; load-bearing, see invariant 4 |
| `workTaskIdentity`, `nextCycleNumber`, `resumedFinalization`, `initialWorkInput`, `evaluationReworkInput`, `finalizationReworkInput`, `retryWorkInput` | :290-:376 | same names | derived identities, +1 currentness generation, next cycle's input |
| `workContext`, `workTaskObligation`, `executeWork`, `executeEvaluationTasks`, `finalize`, `cancelLiveTasks` | :337-:439 | same names | obligation construction |
| `dependencyComplete`, `incompleteDependencies`, `dependenciesComplete`, `isReady`, `revocationAllowed`, `liveTaskList`, `ticketLiveTasks`, `listHasTask` | :399-:434, :1208 | same names | dependency gating (`is_ready` is a read model), revocability, live task authority |
| `decideCreate/Update/Dispatch/Revoke/Resume/WorkTerminal/EvaluationTerminal/TaskTerminal/FinalizationResult` | :446-:769 | private `_decide_*` | one per command shape; `decideUpdate` (:478) is the Pending-only revision ladder |
| `decide` | :773 | `decide(graph, command, policy) -> TicketDecision` | the writer's only decision entry point |
| `evolve` | :813 | `evolve(graph, event) -> TicketGraph` | replay; partial by contract, see D5 |
| `updateTicket`, `enterWorkCycle`, `applyDecision`, `applyCommand` | :788-:1056 | `_update_ticket`, `_enter_work_cycle`, `apply_decision`, `apply_command` | `apply_command` is for tests only |
| `workInputValid`, `workInputMatchesTicket`, `escalationValid`, `ticketInvariant`, `expandDependencies`, `dependencyClosure`, `dependencyGraphAcyclic`, `graphInvariant` | :1065-:1176 | `graph_invariant` | tests and `chug check`; creation order already prevents cycles |
| `obligationValid`, `obligationsUnique`, `obligationAgrees`, `decisionValid` | :1186-:1247 | `decision_valid` | property-test oracle over `decide` |

## 4. Project decision processing — `chug/app/{store,writer}.ts` (`application/project-decision-processing/processing.qnt`)

| Model | At | TypeScript | Meaning |
| --- | --- | --- | --- |
| `AuthorizationRecord`, `AcceptedInput` | :17, :23 | `Authorization`, `AcceptedInput` | principal/operation/policy revision; + id, ordinal, digest |
| `DomainDecisionRecord`, `ObligationRecord`, `DomainOutcome` | :8, :6, :13 | `Outcome = Decided \| Refused` | the domain decision, opaque here |
| `PublishedOutcome`, `DeliverableObligation`, `ProcessingState` | :30, :36, :42 | same names; the `inputs` and `outcomes` tables | position+input+outcome; (position, ordinal, obligation); not an in-memory value |
| `hasOutcome`, `mayAccept`, `accept`, `isHeadUnsettled`, `publishOutcome` | :48-:87 | `admit`, `next_unprocessed`, `commit` | unique input id, equal digest+authorization or conflict; lowest unsettled ordinal; one outcome per input |
| `eventProjection`, `outcomeObligations`, `deliverableObligations` | :102-:123 | `replay`, `deliverable_obligations` | state and delivery work derived from history |
| `positionsAreDense`, `outcomeInputsAreUnique`, `outcomeAttributionMatches`, `outcomesAreValid`, `invariant` | :129-:152 | `chug check` | store constraints, verified by the check command |

## Transaction shape

One accepted input, one decision, one outcome, one state change.
- **Accepted input** (:23) is a decoded, authorized domain command plus its
  identity: an application-minted `input_id` unique per project, an admission
  `ordinal`, the command's `content_digest`, and the immutable
  `Authorization`. Business identities never serve as the input id.
- **Deduplication** is two-layered. `mayAccept` (:52) admits a repeated
  `input_id` only when digest *and* authorization match; a mismatch is a
  conflict, and `accept` (:62) is inert on a known id. A retried business
  command under a *new* input id is not deduplicated — the domain refuses it
  on its own terms (`TaskNotCurrent`, `FinalizationNotCurrent`).
- **Order**: the writer takes the unsettled input with the lowest ordinal
  (`isHeadUnsettled`, :80) — one writer per project, one input at a time.
- **The commit** is one transaction holding exactly the `PublishedOutcome` row
  (position, input attribution, and `Decided(event, obligations)` or
  `Refused(reason)`), the evolved ticket row, and one row per obligation. That
  row *is* the settlement — no second write (`publishOutcome`, :87).
- **Position** (:96) is `len(outcomes) + 1` — 1-based and dense per project
  (:129), which follows from one writer appending one row per settled input in
  the transaction that read the maximum; enforce `UNIQUE(project, position)`.
- **Refusals** occupy a position and settle their input, contribute no event
  to the fold (:102) and emit no obligations (:111).
- **Delivery** needs only committed history: its identity is
  `(position, ordinal)` (:123), stable across redelivery and distinct from the
  task identity in the payload. Before re-offering after a restart, the
  executor port must find no later terminal for that task and no later
  cancellation in the prefix. Delivery status is separate state that never
  rewrites an outcome.

**Rework feedback is ticket state, not obligation payload.** The model is
unambiguous: `EvaluationRework(List[EvaluationReworkEntry])` (`ticket.qnt:18`)
lives in the `WorkInput` held by `Work` (:23, :79) and by
`EvaluationFailureEscalated` (:50); the committed event carries the same
entries (:154, :190) so replay never re-derives them; the obligation receives
only a derived context of manifest references (`workContext`, :337). Store the
entries — evaluator key, reason, manifest, findings — on the current work
input and on the event; the obligation carries only references.

## Identity vocabulary

- **Minted by the domain**: `work_cycles_started` (`ticket.qnt:88`) is the
  only stored counter; the ticket id comes from the release. Nothing random.
- **Derived**: work task id = (ticket, cycle); evaluator task id = (ticket,
  work cycle, stage key, generation, evaluator key); evaluation and
  finalization identity = the work-cycle identity, finalization plus a
  currentness generation. Ready and blocked are views.
- **Minted by the application**: `input_id`, `ordinal`, `position`, obligation
  ordinal. None enters ticket state.
- **Evidence**, opaque references stored and never read: result manifests,
  failure and finalization and retry evidence, title, instructions, input
  bindings, workload, result contract, finalization configuration, findings.

## Invariants the implementation must keep

1. `graph_invariant` (`ticket.qnt:1176`): each ticket's id matches its key,
   dependencies exist and are acyclic, and `ticketInvariant` holds — a phase
   carries exactly the data legal in it, `Pending` implies zero cycles, and an
   escalation's resume material passes the predicate its resume applies.
2. `decision_valid` (`ticket.qnt:1247`): a refusal changes nothing; a decision
   leaves a valid graph with unique, valid obligations agreeing with the state
   it produced — a task requested only if now live, a cancellation only for
   one just withdrawn, a finalization only for the operation now held.
3. `evaluation_invariant` (`evaluation.qnt:533`): plan validity and repository
   agreement, one status per evaluator, dense ordered stage history, and the
   state-specific history rules.
4. Command validity (`ticket.qnt:277`) is load-bearing: admitting a command
   that fails it can put a state in the graph that `graph_invariant` rejects.
   Validate at the edge, before a `TicketCommand` exists.
5. Processing (`processing.qnt:152`): positions dense from 1, at most one
   outcome per input, attribution equal to the retained accepted input, and
   every outcome carrying a present event or refusal reference.
6. One decision changes one ticket; its only cross-ticket reads are its
   immediate dependencies' states (`ticket-decision-context.md:26`).

## Decisions the implementation must resolve
- **D1 `LegacyReleasedContent`** (`ticket.qnt:9`) has no producer in a fresh
  store. Transcribe both so exported traces decode, let authoring build only
  `AuthoredContent`, revisit at M4.
- **D2 verdict decoding** (`evaluation.qnt:300`, see D8): the model always produces
  `SummaryReason`, never `ExitCodeReason`, and reads `value > 0` as a pass.
  Keep both variants; the real decoding is an adapter chosen by the
  evaluator's result contract, and the protocol sees only the verdict.
- **D3 findings validity** (`evaluation.qnt:398` vs `ticket.qnt:1065`):
  `stageRunInvariant` requires `findingsValid`, `workInputValid` does not
  re-check the entries it carries. Reachable through a command since D8;
  `commandValid` refuses it and the constructors enforce it.
- **D4 access kinds** (`task.qnt:84`): nothing requires work to publish and
  evaluators to read. Do not enforce it ahead of the model; if we want it, add
  it to `releasedTicketValid` first.
- **D5 `evolve` partiality** (`ticket.qnt:808`): every branch is inert on a
  pairing `decide` could not produce, and it reads a missing ticket id
  unguarded. Writer and replay use a checked `evolve` that raises on an
  impossible pairing; keep inert behaviour only where a trace asserts it.
- **D6 unbounded finalization rework**: the failure policy is consulted only
  on a conclusive *evaluation* failure (`ticket.qnt:608`), so
  `FinalizationNeedsWork` can start cycles without bound. Leave the domain
  alone, surface the cycle count.
- **D8 findings enter through a command** (`task.qnt:43`, M5). The model had
  no route for structured findings: `decodeEvaluatorResult` always produced
  `findings: []`, yet `FailDetail.findings` feed the rework entries of the
  next work cycle and D2 says the real decoding is an adapter. The model was
  changed first. `ValidatedTaskResult` now carries
  `findings: List[ResultFinding]` in the neutral task contract,
  `decodeEvaluatorResult` maps each to an `EvaluationFinding`, and
  `terminalValid` — and so `commandValid` — requires `resultFindingsValid`, a
  restatement of `findingsValid` over the neutral vocabulary, because the task
  contract cannot import the protocol that consumes it. Without that clause an
  admitted terminal could put a stage run in the graph that `stageRunInvariant`
  rejects, which is invariant 4 exactly.
  `evaluatorFindingsReachTheNextWorkCycleTest` carries a finding from a
  produced result into the next cycle's rework entry
  and asserts a duplicate id is not a valid command; the exported traces and
  the conformance corpus now reach both `ResultFinding` and
  `EvaluationFinding`. The service is the adapter D2 named:
  `chug/service/verdict.ts` reads a manifest's `verdict` and `findings`,
  stores each description as a `text/plain` blob, and builds the
  `ResultFinding`s the terminal carries. It accepts `pass`/`passed` and
  `fail`/`failed`, because this repository's own `review-result-v2` and
  `ci-result-v2` contracts and its CI script spell them long, and a manifest
  with no `verdict` is a pass, which is what a work result is. A contract may
  also label its findings with strings — this repository's does — and a label
  is not an identity the domain can hold, so the entry's position becomes the
  `ResultFinding` id and the label stays readable in the stored manifest every
  rework entry references.

- **D7 `processing.qnt` is unexercised**: no state machine, so `mayAccept`,
  `isHeadUnsettled`, `eventProjection` and `deliverableObligations` are prose
  nothing runs, and nothing asserts positions follow admission ordinals. M3
  encodes them as store constraints, tested for idempotent admission,
  conflicting re-admission, ordering, and restart mid-batch.

## Authored names

The model keeps positive `StageKey` and `EvaluatorKey` identities and has no
operator-facing names. M4 keeps those names in `CreateTicketRequest.stage_names`
and `CreateTicketRequest.evaluator_names`, both read-only maps whose keys cover
the released plan exactly. The canonical create command in `inputs.command` is
their authority. Writer replay rebuilds the tables from that command and every
projection uses them to populate `ticket_stages.stage_name` and
`ticket_evaluators.evaluator_name`; `chug check` performs the same replay and
comparison. Keys are assigned by first appearance, with an evaluator name used
in later stages retaining its first key.

## Input request identity

Schema version 1 stores a non-null, 64-character `inputs.request_digest` beside
the canonical command's `content_digest`. HTTP ticket creation hashes the raw
YAML before resolving catalog references and checks a known id and its stored
authorization through `Writer.readmission`, so an exact retry can replay or
finish its original input without reopening the catalog. Callers without a
separate request body pass `content_digest(command)`. The source request bytes
are not retained; `chug check` can verify a distinct request digest's format,
but cannot recompute it.

The *catalog* commit a create resolved at is not recorded. A project's
`.chug/` is read through a tree source (`chug/trees.ts`) which, for a Git
tree, resolves its ref once per resolution, so one create reads one commit and
a merge landing mid-request cannot mix versions — but the commit is not stored
beside the input. What the resolution produces is: every referenced fragment
becomes an immutable blob the command names, so the ticket carries the catalog
content it was created from whether or not the commit that held it is known.
Recording the commit would need a new `inputs` column and would answer a
different question — which revision of the catalog an author was reading —
and no reader asks it yet. Dispatch is separate: with no `--commit`, a ticket
starts from the commit the project's tree resolves to *at dispatch time*, which
for the local runtime is the mirror's `main`.

## Terminal input identity

A task terminal's accepted-input id is derived from the task identity alone:
`terminal:WorkTaskId:<ticket>:<cycle>` or
`terminal:EvaluationTaskId:<ticket>:<workCycle>:<stage>:<generation>:<evaluator>`
(`chug/app/task_codec.ts`). The same string is the task component of
`GET /api/v1/projects/{name}/tasks/{task}`, so a runner names its task once.

This is deliberate and is the only identity rule here that is not
application-minted. A task is reported at most once — `taskCurrent`
(`evaluation.qnt:179`) and the work-cycle identity make a second report for the
same identity refusable — so deriving the input id from it makes a retried
POST a duplicate that replays the original outcome, and a *different* body for
the same task a conflict rather than a second decision. The request digest is
taken over the canonical JSON of `{task, outcome}`, so formatting differences
are not a conflict. It also makes the service's own reconciliation and a late
runner POST the same input: when the delivery loop admits
`TaskProcessFailed` for a dead job under this id, the runner's later POST
deduplicates against it instead of racing it.

Business identities never serving as the input id (`processing.qnt` transaction
shape) still holds for everything an operator submits: creates, dispatches,
revocations and resumes carry a caller-supplied `Idempotency-Key` or a minted
UUID. A terminal is not operator input; it is the one report a task may make.

## Runner authentication

A task identity is derivable by anyone who can read a ticket, and the terminal
input id above is derived from it, so an unauthenticated `POST .../terminals`
would let any network client commit the first — and therefore authoritative —
terminal for a live task and turn the real runner's report into a 409. Both
runner-facing routes therefore need a bearer token.

When the delivery loop dispatches an execution obligation it mints one token
(`secrets.token_urlsafe(32)`), stores only its sha256 in
`obligations.dispatch_token_hash`, and puts the token in the dispatch payload.
The runner sends `Authorization: Bearer <token>` on `GET .../tasks/{task}` and
on `POST .../terminals`. The service hashes what it is offered and compares
with `hmac.compare_digest`, **before the idempotency lookup and before any
write**, so a caller without the token can never create an input row and never
takes the task's input id. A wrong or missing token is `401`; a task with no
execution obligation at all is `404`, which reveals nothing a ticket read does
not.

Three consequences worth stating. The hash is looked up over *every* delivery
state, not only `dispatched`, so a runner retrying a terminal that already
settled its obligation still authenticates and has its original outcome
replayed — which is why `settled` and `cancelled` keep the column. An
obligation that was never dispatched holds no hash, so no token authenticates
against it and both routes refuse everyone. And Nomad answers a dispatch
before the allocation starts, so a runner can reach the service in the window
before the hash is recorded; the runner retries a `401` on the task view under
the same bounded backoff it uses for the terminal, and a token that is
genuinely wrong exhausts that bound and becomes a reported process failure.

The token is a bearer credential in a dispatch payload, so whoever can read
the Nomad API can read it. That API must be reachable only from the host
running the service; `infra/local/compose.yaml` publishes 4646 on `127.0.0.1`
for exactly this reason. Provider credentials never travel that way at all:
they are mounted into the allocation as a file and only its path is passed.

## Delivery facts

`obligations` carries delivery state as facts, not a status word, and the
CHECK constraints make an illegal combination unstorable. `delivery` is one of
five values and each fixes exactly which columns are present:

| delivery | attempts | nomad_job_id, dispatched_at | settled_position, settled_input_id | last_error | dispatch_token_hash |
| --- | --- | --- | --- | --- | --- |
| `pending` | >= 0 | null | null | null | null |
| `dispatched` | >= 1 | set | null | null | set |
| `settled` | >= 0 | null | set | null | kept if it was dispatched |
| `cancelled` | >= 0 | null | null | null | kept if it was dispatched |
| `undeliverable` | >= 1 | null | null | set | kept if it was dispatched |

`read.ObligationView.delivery` decodes the row into the matching variant, so
no reader sees the string. A sixth column, `task_key`, is not a delivery fact
but the identity a lookup uses: it is `task_codec.task_key` of the task the
obligation concerns, present on `ExecuteTask` and `CancelTask` and NULL on
`FinalizeTicket`, which the schema's CHECK makes the only storable combination.
It exists so the runner-facing routes and the writer's settlement find an
obligation by index rather than by decoding every obligation the project ever
emitted; `chug check` re-derives it from `task_json` (`writer.obligation_task_key`),
so it stays a derivation and not a second copy that could drift. `dispatch_token_hash` is deliberately not projected
into that read model: it is a secret's shadow, not an operator-facing fact,
and the HTTP detail endpoint would otherwise publish it. The transitions are: the delivery loop dispatches a
pending `ExecuteTask` and records `dispatched` with Nomad's `DispatchedJobID`;
a failed dispatch increments `attempts` and, at the `--dispatch-attempts`
bound, becomes `undeliverable` with the last error; a `CancelTask` stops the
matching dispatched job and marks both rows `cancelled`.

`undeliverable` is at rest, not still trying: the loop reports the exhausted
bound once — the terminal input is what says it already did — and a later
terminal for that task is still accepted, because the bound says the service
could not reach Nomad, not that no allocation ran. Such a row keeps its
`last_error` instead of being rewritten to `settled`, so why delivery failed
survives beside the domain fact in the outcome log; `check`'s settlement rule
therefore covers only rows that say `settled`.

Settlement is not a second write. `Writer._settle` marks the obligation
`settled` with the position and input id **inside the transaction that appends
the outcome**, so a crash cannot leave a committed terminal beside an
unsettled obligation. `FinalizeTicket` settles the same way when its
`ReportFinalizationResult` commits. `chug check` re-derives what the columns
cannot: that a settled obligation's position holds an input which is a task
terminal for that task or a finalization report for that ticket, cycle and
generation, and it repeats the state-shape rule so a row corrupted with the
constraints disabled is named rather than trusted. It checks the token hash
the same way: present on a dispatched row, absent from one that was never
dispatched, and a sha256 digest wherever it appears.


## Dispatch facts before Nomad answers

A dispatch is two facts and one network call, in that order. The delivery loop
first renders and stores the briefing (`chug.app.briefing`, from the graph as
of the obligation's emitting position via `chug.app.history.ticket_graph_at`,
never the current graph), mints the bearer token, and moves the row from
`pending` to `dispatching` with the token's hash and the briefing blob
(`Writer.record_dispatching`). Only then is Nomad asked, under the idempotency
token `project:position:ordinal`. On acceptance the row becomes `dispatched`
with the job id (`Writer.record_dispatched`), whose recorded hash is that of
the token the job's payload carries (`NomadClient.dispatched_token`): after a
lost answer the next pass re-dispatches under the same idempotency token, Nomad
answers with the job it already has, and its allocation holds the earlier
token, so that hash, not the retry's, is the fact. A failed call leaves the row
`dispatching` (or `pending`) and counts an attempt; the bound makes it
`undeliverable` with the reason. The CHECK constraints admit `dispatching` with
exactly a token hash and a briefing and nothing of a dispatch, `check` repeats
the shape, and every obligation row's `task_json` is compared byte for byte
with the obligation the outcome emitted so a retargeted row cannot carry a
briefing that agrees with itself.

## File ownership

The store is one SQLite file written by one process. Nothing in the schema said
*which* process, and three things need to know: `chug repair`, which rewrites
the projection a live writer owns; a second service started against the same
file by mistake; and the writer itself, which must not keep writing once
something else has taken the file over.

`service_owner` is one row — `generation`, pid, host, `started_at`,
`heartbeat_at`, `heartbeat_seconds` — claimed by `_Service.start`, refreshed by
`_Service._beat`, and deleted by `_Service.close`.

**Claiming is compare-and-claim, not overwrite.** `claim_ownership` runs
`BEGIN IMMEDIATE`, and refuses with `OwnershipRefused` when the row it finds is
still held; it replaces only a stale one. `_Service.start` therefore fails the
lifespan, so a second `chug serve` against one database prints who holds it and
exits non-zero instead of running a second delivery loop beside the first —
whose shutdown would then have deleted the only marker.

**One exception to the freshness rule: a predecessor with our own identity.**
A restarted container keeps its hostname and starts the service as pid 1 again,
so the marker its killed process left names the process that is about to
replace it. Two live processes cannot share a pid on one host, so such a marker
cannot belong to anything running and its heartbeat says nothing;
`claim_ownership` supersedes it whatever its age. "A predecessor's" is decided
by the marker's `started_at` against this module's import instant: written
before the process existed, it is a predecessor's; written after, it is this
process's own, and a *second* service inside one process stays refused, which
is a real mistake and not a restart. Every other case keeps the sixty-second
rule, so a host process that crashed comes back under a different pid and
waits its predecessor out; under compose `restart: unless-stopped` is what
turns that wait into a recovery. The rule assumes host and pid together name a
process, which holds while each container has its own hostname.

**The generation is the fence.** It is the claim instant in microseconds,
forced above whatever generation the row already held, so it only ever
increases. A counter would do while the row survives, but `repair` deletes a
stale marker, and a counter restarting at one would let a wedged service whose
generation was one pass the next service's fence. The holder keeps its `Owner`;
`refresh_ownership`, `release_ownership` and `verify_ownership` all match on
the generation, and a row that does not match — or is not there — is
`LostOwnership`.

`Writer._writing` is the fence in the write path: every durable write —
`admit`, `process_next` (which is settlement, including a terminal's), and the
three delivery-fact updates — is one `BEGIN IMMEDIATE` that verifies the owner
row's generation before it writes anything. The check is inside the transaction
and after the write lock, so nothing can claim the file between the check and
the write. It costs one single-row read under a lock the writer already holds:
no second lock, no lease, no coordination. A `Writer` with `owner` unset — the
store tests and the replays — is unfenced, which is what a writer with no
service around it should be.

**Losing the file stops the process.** `_Service.lose_ownership` runs when the
heartbeat or a delivery write raises `LostOwnership`, and its default action is
`os._exit(EXIT_LOST_OWNERSHIP)`, which is `4`. Not a graceful shutdown: that
exits `0`, and a service that stopped because its file was taken did not stop
successfully; and the graceful path would try to release a marker this process
no longer holds. An HTTP handler that hits the fence fails its request with the
exception, and the heartbeat stops the process within one interval.

**The threshold.** A marker is *held* while its heartbeat is younger than
`max(60 seconds, 4 * heartbeat_seconds)`. Sixty is the floor; the holder's own
refresh interval is stored so that `--reconcile-seconds 600` widens the window
instead of making a working service look dead. The holder refreshes at a
quarter of its threshold (`heartbeat_interval`), on a dedicated asyncio task —
**not** on the reconcile pass, because a pass that waits on a slow Nomad or
works through many live obligations can itself exceed the threshold, and a
heartbeat carried by that pass would let a live, writing service be declared
dead. A heartbeat this build cannot parse counts as held: a marker no tool can
date is one no tool should declare dead.

**What follows.** `repair` refuses while a marker is held and names the pid,
host, generation and heartbeat age. A crashed service leaves its row behind and
it goes stale one threshold after the last refresh, so nothing is unlocked by
hand. A clean shutdown deletes the row, so `repair` runs immediately after a
stop. `backup` and `check` ignore the marker entirely: a check is read-only and
a backup is `sqlite3.Connection.backup`, a consistent copy of the committed
state taken while a writer is mid-transaction.

**`repair` is one transaction.** Ownership check, replay, comparison, rewrite
and commit are one `BEGIN IMMEDIATE` on one connection (`open_writer`, which
does not migrate — a file at an unknown version is to be reported, not
upgraded). The write lock is taken before the marker is read, so no service can
claim the file or commit an outcome between the judgement and the rewrite; a
repair can never overwrite a newer projection with an older replay. When the
marker is stale the repair deletes it inside that same transaction, so a
service wedged past its threshold is fenced out for good rather than coming
back to write over what the repair rebuilt. `--dry-run` runs the identical
transaction and rolls it back.

## Briefing facts

The text an allocation is handed is rendered once, by the service, in
`chug.app.briefing.render_briefing` over the graph and the blobs, and stored as
a `text/markdown` blob whose id is the delivery fact `obligations.briefing_blob`.
It exists exactly when `dispatch_token_hash` does (both are minted by the
dispatch), which the schema's CHECK enforces; a `FinalizeTicket` never carries
one. The runner reads it from the task view's `briefing` and passes it to the
agent unchanged. Rendering is deterministic over its inputs, so a retried
dispatch of the same obligation in the same state reuses the same blob, and
`chug check` renders it again from the graph the log had reached at the
emitting position (`Replay.graphs_after`) and compares bytes. A briefing that
cannot be rendered or exceeds `BRIEFING_LIMIT` (256 KiB) refuses the obligation
as undeliverable with the reason; nothing is truncated.

## Progress facts

What an allocation reported it was doing, normalized by the runner into the
provider-neutral events of `chug.app.progress`: `{sequence, at, kind, text,
detail}` with `kind` one of `assistant_message`, `reasoning_summary`,
`command`, `command_output`, `provider_notice`, `tool_call`, `tool_result`,
`harness`, `session` and `truncated`. `chug.runner.progress` reads each
provider's stream once —
`codex exec --json` thread and item events, `claude -p --output-format
stream-json` system, assistant, user and result messages — redacting each line
before it is written through to the allocation's own stdout and stderr, kept as
a tail, or normalized. A non-JSON line, or JSON envelope type the normalizer
has never heard of, becomes a `provider_notice` carrying the line verbatim,
marked with the provider and, for an envelope, its claimed type. Unknown item
types and content blocks are likewise notices carrying their own JSON. Only
the envelope events it names in `CODEX_IGNORED` and `CLAUDE_IGNORED` are
dropped. The runner's own phase lines are `harness` events
in the same sequence. The provider fixtures under `tests/runner/fixtures/` and
the accepted-argument lists were captured from codex-cli 0.152.0 and Claude
Code 2.1.259 on 2026-09-03.

Redaction is one `Redactor`, built before anything runs and applied first
everywhere: it registers every exported credential value, every string of
`MIN_NESTED_LENGTH` characters or more found inside a credential that parses as
JSON (so the `access_token` inside `CODEX_AUTH_JSON` is replaced on its own),
and the dispatch bearer token, which the allocation's payload file holds.
Redaction runs over the whole pending buffer before it is cut into anything,
and an unterminated piece holds back the longest registered secret minus one
character, so a secret that straddles a cut is matched whole rather than
emitted as two fragments. Because every line is redacted as it arrives, every
later truncation — event text, rendered detail, evidence tails — cuts text that
no longer contains a secret. The tee decodes with one incremental UTF-8 decoder
per pipe, so a character across a cut is one character; the presentation tail
carries `CONTINUED_MARKER` where a line was too long, and a `script`
workload's result is parsed from a separate unmarked tail of what the child
actually wrote.

Progress is not authoritative and `check` never compares it with anything: it
is what an allocation said, like a blob is what an allocation produced. It is
keyed by `(project_id, task_key, token_hash, sequence)`, so a superseded
dispatch's events cannot be read as the current attempt's; a batch offering any
other dispatch's token is refused 401 exactly as a terminal is, and the token
is authenticated from the header before the body is read at all. The store
holds a transcript to being a sequence: a batch must be contiguous and
ascending and begin no later than one past the stored highest, and a resend
must be byte-identical to what is stored, or it is a 409 carrying that highest,
which the runner resynchronizes from. The runner asks for the stored highest
before it records anything, so a restarted allocation continues one attempt.

Bounds, all in `chug.app.progress` and enforced by the runner *and* the route:
8 KiB of text per event, truncated from the front; 64 bytes of instant; 1 KiB
of rendered detail; 4,000 events and 4 MiB per attempt, counting every stored
field of every event (`stored_bytes`) and not the text alone. An event that
would take the attempt past either bound is not stored, none of its batch is,
the attempt is marked `truncated` by one generated marker — exempt from both
bounds, being the record of why the rest is missing — and every later batch is
refused 413; filling a bound exactly is not truncation. 50 events per POST and
2 MiB per request body, sized so a maximal batch fits with room for JSON
escaping, the body checked against `Content-Length` before it is read and again
while reading it; 500 events per read page. Reads: `GET …/tasks/{task}/progress?after=N`
for one attempt's page and `GET …/tickets/{n}/progress` for the ticket's whole
transcript as SSE, whose event id is `<task_key>:<attempt>:<sequence>` — the
attempt being the first `ATTEMPT_PREFIX` characters of the token hash, so a
`Last-Event-ID` cannot resolve to another attempt's identical sequence and skip
a range. Each ticket has its own wake condition, so a stored batch wakes only
the streams following that ticket. The history read model carries, per
dispatched obligation, the attempt's event count, byte count and truncation
state; the events themselves are one route away.

## Agent session facts

What the provider CLI itself wrote while one attempt ran, kept whole in
`agent_sessions` (schema version 4) and bound to the attempt by the sha256 of
that dispatch's bearer token: provider, model, provider session id, the CLI's
own `--version` at save time, the source commit, the briefing blob, the file
name the provider gave it, the content as a blob, its byte size and sha256,
`saved_at`, `resumed_from` and `resume_outcome` (`fresh`, `resumed`, or
`fallback:<reason>`). One session per attempt, worker and evaluator alike, so a
retrospective has every attempt including the ones that failed. There is no size
cap on a saved session -- a session cut in half can be neither resumed nor read
back -- so the visibility is the size instead: it is in the history read model
per attempt, in the ticket header as a total, in the UI, and in `chug status N
--history`. Retention by count and offload to object storage are later work.

Like progress, sessions are the runner's own facts and `check` never re-derives
them from the log; it asks only that each row is attached to something real --
one session per attempt, a `content_blob` still in that project's blob store, a
`token_hash` that is the hash of a dispatch of that same task on an obligation
of the ticket it claims, and a `resumed_from` that names a dispatch of this
project. The content goes through the ordinary blob store, so a re-upload of the
same bytes under one dispatch token costs one blob and a different upload for
the same attempt replaces the row and is logged. `chug backup` carries the table
because it is SQLite's own page copy.

Where each CLI keeps its session was captured from the real CLIs into
`tests/runner/fixtures/codex-session-layout.txt` and
`claude-session-layout.txt`: codex-cli 0.152.0 writes
`$CODEX_HOME/sessions/<Y>/<M>/<D>/rollout-<local stamp>-<session id>.jsonl`, and
Claude Code 2.1.259 writes `$CLAUDE_CONFIG_DIR/projects/<cwd with each of `/`,
`.` and `_` replaced by `-`>/<session id>.jsonl`. The runner now sets
`CLAUDE_CONFIG_DIR` to the allocation's own control directory for the same
reason it already set `CODEX_HOME`. Both were confirmed to resume from nothing
but the restored file in an otherwise empty home, and both append to that same
file when resumed. The runner finds the file by globbing for the session id
rather than recomputing a local-time name, restores a Codex rollout under the
name it saved (whose date directories are read out of that name) and a Claude
transcript under the *resuming* allocation's own working directory.

The routes. `POST /api/v1/projects/{name}/tasks/{task}/session` takes the raw
bytes as the body with the metadata in `x-chug-session-*` headers -- the one
envelope that leaves the body exactly what the provider wrote -- authenticated
against this dispatch's token hash and refused 401 on a stale one before any
body is read, with `MAX_SESSION_BODY_BYTES` (256 MiB) as the transport bound and
the declared sha256 checked against the bytes. `GET
…/tasks/{task}/session/{token_hash}` serves one to the allocation resuming into
it; `GET …/tickets/{n}/sessions/{token_hash}` serves the same bytes to an
operator with no bearer and a filename. Both are bounded to the sessions of one
ticket. The blob API takes and returns `bytes`, so a large session is buffered
in memory on both paths even though the downloads write to the socket in
chunks; making that a real stream is a change to the blob store.

Resuming for rework. The task view of a work cycle whose cause is evaluation
rework carries `resume: {token_hash, provider, model, session_id,
provider_version, source_commit, file_name, size, task_key, message}` when the
previous cycle's work task saved a session of the same provider and the
workload's optional `resume` (default true) is not false. `message` is what the
runner sends as the new prompt: one sentence naming the commit the source has
moved to, the rework section of the briefing verbatim, and the same submit
instruction -- never the whole briefing, which the session already holds. The
runner downloads, restores, compares the recorded CLI version with the running
one, and runs the provider's resume command; the transcript of a resumed attempt
opens with a `session` event carrying the provider session id and a `harness`
event naming the attempt it resumed from. It falls back to a fresh run with the
full briefing on `fallback:download`, `fallback:restore`,
`fallback:provider_version` or `fallback:no_stream` (the resumed process
produced no provider stream event at all), recording the reason as a harness
event. A session the runner cannot find is a harness event and a phase line and
never a failed attempt: the terminal goes out either way. The nudge keeps
working on a resumed session because the session id is the same one.

Offline. `chug sessions export DB DIR` writes, per project and ticket,
`tickets/<n>/history.json`, `tickets/<n>/outcomes.jsonl` and every session as
`attempts/<token hash>.<provider>.jsonl` with a `.meta.json` sidecar, read-only
on the database the way `check` is.

## Rework limit

`.chug/project.yaml` carries `rework_limit` (integer >= 1, default 3): how many
work cycles one ticket may run. `chug.app.policy.rework_limit_policy` turns a
number into the domain's `EvaluationFailurePolicy` — rework while `work_cycle <
limit`, escalate otherwise, so the failure that would start cycle `limit + 1`
escalates instead.

A ticket document may declare its own top-level `rework_limit` (integer >= 0),
carried on `CreateTicketRequest.rework_limit` and encoded only when declared.
Zero is a ticket that must not be reworked — its work performs an external
operation — so its first evaluation failure escalates, with the same evidence a
rework would have carried, and no further work cycle starts. Only the ticket
declaration accepts zero; the project field keeps its floor of 1.

The number a *ticket* runs under is stamped on `tickets.rework_limit` in the
transaction that creates it, from the declared limit when there is one and
from the project's configured default otherwise, and is never changed
afterwards: an update document may restate the limit and the resolver refuses
one that differs. `projects.rework_limit`, which the service writes at every
start, is only that default. It has to be the ticket's, because the
decisions in the log were made under it: a project row an operator lowered
would otherwise make `chug check` re-decide an older ticket's conclusive
failure as an escalation, disagree with the rework the log holds, and leave
`chug repair` refusing a discrepancy it cannot derive. `tickets.rework_limit`
is therefore not in `PROJECTED_TABLES` — it is not derivable from the log —
and `chug.app.projection.replace_ticket_rows` carries it across the rewrite it
does on every settlement (`UNPROJECTED_TICKET_COLUMNS`). NULL means unbounded,
which is what every ticket released before the column existed keeps after
migration. The writer decides under `chug.app.policy.ticket_policy`, which
answers from the deciding ticket's own row; `check` and `repair` re-decide the
same way and read no project configuration. The ticket detail and the history
both show the bound.

## Ticket history

`outcomes.ticket_number` is the decided event's ticket (`event_ticket`), NULL
for a refusal, written in the settling transaction and verified by `check`
against the stored outcome. With `outcomes_by_ticket` it makes one ticket's
history an index range. `chug.app.history.ticket_history` walks those outcomes
in order, places the obligations each emitted (`obligations_by_ticket`) into
cycles, stage runs and finalizations by their task identities, fills each
evaluator's outcome from the terminal events, and records what each generation
led to; it decides nothing and inlines no evidence. The released definition
(`chug.app.definition`) is the `TicketCreated` event and its blobs rendered as
deterministic YAML with userinfo redacted.
