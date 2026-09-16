# Exported ticket-model traces

Reproducible ITF traces from `ticket_tests.qnt`, checked in so implementation
tests replay the specification without Quint installed. Generated: regenerate,
never hand-edit.

- `scenario-<name>.itf.json` — one per `run` definition in `ticket_tests.qnt`.
- `simulation-seed-<seed>.itf.json` — seeded random walks over `step`, 25 steps,
  checked against `modelInvariant`.
- `index.json` — generated summary: per trace the state count, per step the
  action, decision and each ticket's phase, plus the coverage tables below.

## Regenerating

```sh
node ticket-domain/export_traces.ts   # from the repository root
```

Needs `quint` on `PATH` (written against 0.32.0). It exits non-zero if a Quint
command fails, if a scenario yields no trace, or if a trace's status is not
`ok`, and it deletes trace files it no longer produces. Rerun it after any model
change: scenarios are discovered from the source, so added, renamed and removed
`run` definitions need no edit to the script. It uses `quint test --out-itf`
for the named scenarios (the only subcommand that runs `run` definitions) and
`quint run --out-itf --seed ... --mbt --invariant=modelInvariant` for the
simulations.

## Reproducibility

Two consecutive runs produce byte-identical files. Quint's own output is not,
so the script makes two normalizations, and only these two:

- `#meta.description` and `#meta.timestamp` hold the wall-clock generation
  time. Dropped, replaced by `generator`, `kind`, and `scenario` or
  `seed`/`maxSteps`/`invariant`.
- Quint 0.32.0 lists each `mbt::` name twice in `vars`. Duplicates are removed.

State contents are already deterministic, including `#map` and `#set` element
order — but do not depend on that order; compare maps and sets by content.

## Format

[ITF](https://apalache-mc.org/docs/adr/015adr-trace.html). `vars` names the
state variables; `states` is the sequence, each with `#meta.index` — the one raw
JSON integer in the file — and one entry per variable. As encoded here:

| Quint | JSON |
| --- | --- |
| int | `{"#bigint":"501"}` — decimal **string**, parse it |
| record | plain object, keys as declared |
| list | plain array |
| set | `{"#set":[...]}` |
| map | `{"#map":[[key,value],...]}` — pairs, keys are encoded values too |
| tuple | `{"#tup":[...]}` |
| variant | `{"tag":"Name","value":<payload>}`; nullary payload is `{"#tup":[]}` |

```json
{"tag":"TicketRefused","value":{"tag":"TicketNotFound","value":{"#bigint":"0"}}}
```

Compact JSON; `npx prettier ticket-domain/traces/index.json` renders the index for reading. Two things a
replay harness must know:

- State 0 of every scenario trace is `init`, whose `lastDecision` is the
  `noDecision` sentinel `TicketRefused(TicketNotFound(0))`, not a decision the
  model took. Skip it.
- A `check(...)` step re-emits the previous `lastDecision` unchanged, so equal
  consecutive decisions are normal and are not two decisions.

Simulation traces add two variables from `--mbt`: `mbt::actionTaken`, the
`step` alternative taken into that state, and `mbt::nondetPicks` (always `{}`).
`actionTaken` is the only place a trace names its input — the variables record
`priorGraph` and the resulting `lastDecision`, never the command. `quint test`
has no `--mbt`, so a scenario's inputs come from its `run` definition.

## Coverage

`ticket.qnt` declares no Quint `action`s — it is pure functions over these
types — so coverage is measured over the decision outcomes and lifecycle phases
the command paths produce. Over the 29 traces: `TicketEvent` 18/18,
`TicketState` 7/7, `TicketRefusal` 11/15. `index.json` holds the live tables.

Never exercised: `SelfDependency`, `DispatchSourceRepositoryMismatch`,
`TaskNotCurrent`, `FinalizationNotCurrent`.
The middle two are asserted inside `check(decide(...) == TicketRefused(...))`,
which by construction leaves `lastDecision` untouched, so the refusal never
reaches a trace; the other two appear in no scenario at all. **Replaying these
traces does not test those four refusals** — they need direct `decide` tests.

Names drop the `Test` suffix, decisions the `Ticket` prefix; equal runs collapse.

| scenario | states | decisions |
| --- | --- | --- |
| `repositoryContract` | 4 | NotFound Created |
| `workOutputRepositoryContract` | 2 | NotFound |
| `stageKeyContract` | 2 | NotFound |
| `happyPath` | 12 | Created DependenciesIncomplete Dispatched WorkResultAccepted EvaluationProgressed EvaluationPassed FinalizationSucceeded |
| `definitionRevisions` | 8 | Created Updated |
| `updateRefusalLadder` | 16 | NotFound Created IdentityMismatch RevisionStale DependenciesChanged Dispatched NotPending |
| `dispatchUsesTheRevisedDefinition` | 6 | Created Updated Dispatched |
| `failedEvaluatorFindingsAreCarriedIntoReworkEntry` | 1 | (pure assertion, no state variables) |
| `evaluatorFindingsReachTheNextWorkCycle` | 9 | Created Dispatched WorkResultAccepted EvaluationProgressed EvaluationReworkStarted |
| `evaluationFailurePolicy` | 13 | Created Dispatched WorkResultAccepted EvaluationProgressed EvaluationReworkStarted WorkResultAccepted EvaluationProgressed EvaluationFailureEscalated WorkResumed |
| `evaluationUnavailableResume` | 13 | Created Dispatched WorkResultAccepted EvaluationProgressed EvaluationBlocked EvaluationResumed EvaluationProgressed EvaluationPassed FinalizationSucceeded |
| `evaluationFailurePrecedesUnavailability` | 7 | Created Dispatched WorkResultAccepted EvaluationProgressed EvaluationReworkStarted |
| `evaluationProcessFailureRecovery` | 12 | Created Dispatched WorkResultAccepted EvaluationProgressed EvaluationBlocked EvaluationResumed EvaluationProgressed |
| `duplicateEvaluatorTerminalIsRefused` | 6 | Created Dispatched WorkResultAccepted EvaluationProgressed |
| `revocationCancelsOutstandingEvaluationTasks` | 8 | Created Dispatched WorkResultAccepted EvaluationProgressed Revoked |
| `finalizationRecovery` | 18 | Created Dispatched WorkResultAccepted EvaluationProgressed EvaluationPassed FinalizationNeedsWork WorkResultAccepted EvaluationProgressed EvaluationPassed FinalizationUnavailable FinalizationResumed FinalizationSucceeded |
| `revocationLeavesDependentsBlocked` | 12 | Created Dispatched Revoked |
| `workFailureEscalation` | 14 | Created Dispatched WorkProcessFailed WorkResumed WorkExecutionUnavailable WorkResumed WorkResultAccepted |
| `staleFinalizationIsRefused` | 13 | Created Dispatched WorkResultAccepted EvaluationProgressed EvaluationPassed FinalizationUnavailable FinalizationResumed FinalizationSucceeded |
| `finalizationResultContract` | 10 | Created Dispatched WorkResultAccepted EvaluationProgressed EvaluationPassed |
| `evolveIgnoresImpossiblePairing` | 20 | Created Dispatched WorkResultAccepted EvaluationProgressed EvaluationPassed FinalizationSucceeded Revoked |

Seeds chosen by set cover: random walks mostly churn in `Pending`/`Revoked`.

| seed | states | phases reached | distinct step actions |
| --- | --- | --- | --- |
| `0x01` | 26 | Pending, Revoked | 6 |
| `0x02` | 26 | Pending, Revoked | 7 |
| `0x07` | 26 | Escalated, Pending, Work | 8 |
| `0x28` | 26 | Evaluation, Pending, Revoked, Work | 9 |

The `requiredCapabilitiesPreserved` scenario records nonempty, distinct work
and evaluator capability sets through a pending revision, dispatch, work
failure/resume, evaluation rework, and evaluator unavailability/resume. The
scenario rejects an attempted active-ticket revision and an empty capability
name. No execution mode or provider placement state is modeled.
