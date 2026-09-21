# Conformance harness

`itf.ts` decodes the traces in `ticket-domain/traces/` into TypeScript values
without importing Quint or the domain. `convert.ts` maps them into domain
values, and `replay.test.ts` checks their decisions and transitions.

## What the decoder guarantees

`load_trace(path)` returns a `Trace` (`name`, `kind`, `vars`, `states`, `meta`,
`path`) and `load_traces()` decodes the directory, both failing loudly rather
than decode something they do not understand:

- `#bigint` becomes a safe integer only from a strict decimal string; a record becomes
  `Record<string, Value>`; `#set` becomes `ReadonlySet`; `#map` becomes `ReadonlyMap`; both
  `#tup` and a plain JSON array become readonly arrays; `{"tag": …, "value": …}`
  becomes the frozen `Variant`, so a nullary variant is `new Variant(tag, [])`.
- No `#bigint`, `#map`, `#set` or `#tup` object survives decoding; an unknown
  `#`-marker, a float, a null, a bare tag, or a marker object carrying extra
  keys raises `ItfError`.
- Every state carries exactly the variables in `vars`, its `#meta.index`
  equals its position, and `#meta.kind` agrees with the presence of the two
  `mbt::` variables. Duplicate `vars` names (Quint 0.32.0 lists each `mbt::`
  name twice) are removed, first occurrence kept.
- Decoded values are immutable and compare by content, so two states compare
  with `==`, and sets and maps never compare by the order the file lists them.

Three shapes exist: a scenario over `graph`, `lastDecision` and `priorGraph`; a
simulation adding the two `mbt::` variables; and the no-variable scenario
`failedEvaluatorFindingsAreCarriedIntoReworkEntryTest`, one empty state long.

## Map keys

A decoded record or map is a `ReadonlyMap` and cannot be a key, so every `#map` key is
frozen: a record or map key becomes a `FrozenMapping` of its pairs sorted by
the `repr` of the key (`.as_dict()` gives the record back), a list key becomes
a readonly arrays, everything else is already hashable and is used as it is. Every key
in the traces is a `#bigint`, so `graph["tickets"]` is keyed by a safe integer ids.

## How replay consumes this

`steps(trace)` yields a `DecisionStep` (`index`, `decision`, `action`,
`nondet_picks`) for every state after `init`, one per step the model took.
`decisions(trace)` yields the same minus a state whose `lastDecision` equals
its predecessor's — a `check(...)` re-emitting the previous decision, not a
second decision. For each yielded step, replay calls `decide` on the *previous*
state's `graph` and compares with `decision`, then `evolve`s and compares with
this state's `graph`; `priorGraph` is the model's own copy of the input state
and checks that pairing again. Two things it must not get wrong:

- The first step is always yielded, even when it equals `NO_DECISION`, the
  `init` sentinel `TicketRefused(TicketNotFound(0))`. A scenario asserting
  wholly inside `check(...)` — `stageKeyContractTest`,
  `workOutputRepositoryContractTest` — commits no decision at all, so check a
  step against `NO_DECISION` before treating it as one.
- Drive a simulation from `steps`, not `decisions`: 22 of the 100 simulation
  steps repeat the previous decision exactly and `decisions` collapses them,
  fourteen of them under a *different* `mbt::actionTaken`.
- No command is in a trace. A scenario's inputs live in its `ticket_tests.qnt`
  `run` definition; a simulation names only its `step` alternative.

## Replay

`convert.ts` converts decoded values into domain values (`graph_from_itf`,
`decision_from_itf`). `replay.ts` rebuilds the command behind a step
(`command_from_step`); `replay.test.ts` replays all 29 traces, 325 steps. Per
step — the triple (`priorGraph`, `lastDecision`, `graph`) the model recorded,
which a `check(...)` step repeats rather than extends — it asserts:

- `graph_invariant` on `priorGraph` and on `graph`;
- `decision_valid(priorGraph, lastDecision)`, the model's `decisionInvariant`;
- `apply_decision(priorGraph, lastDecision) == graph`, and on a decided step
  that `evolve_checked` agrees with it;
- `decide(priorGraph, command, policy) == lastDecision` wherever the command
  is recoverable, which is 303 of the 325 steps.

No command is in a trace. A simulation names its `step` alternative in
`mbt::actionTaken` and each alternative builds one command over the prior
graph, so all 100 simulation steps rebuild — through the fixtures
`tests-ts/domain/builders.ts` transcribes from `ticket_tests.qnt`. A
scenario names nothing, so its command comes from the committed event, which
carries the whole report for all eighteen; the policy is the one input no
report holds, and the event names it — `TicketEvaluationReworkStarted` was
decided under `reworkPolicy`, `TicketEvaluationFailureEscalated` under
`escalatePolicy`.

**Evolve-only** is a step whose command the trace does not determine: the four
state assertions still run, only `decide` is out of reach. Twenty-two of the 225
scenario steps are in that class, no simulation step is:

- `repositoryContract[1]`, `stageKeyContract[1]` and
  `workOutputRepositoryContract[1]`, whose scenarios assert wholly inside
  `check(...)`, commit no decision, and still hold the `init` sentinel;
- `happyPath[3]` and the `check(...)` at `[4]` repeating it, refused with
  `DependenciesIncomplete` — which names the ticket and its unfinished
  dependencies, never the dispatch source the command carried;
- the twelve refused steps of `updateRefusalLadder`. A refusal names the ticket
  and, for `TicketRevisionStale`, the two revisions — never the definition the
  `UpdateTicket` carried. The simulation's `updateOne` covers `decide` over the
  command, and `tests-ts/domain/domain.test.ts` covers the whole ladder.
- the two refused steps of `publishingMissingOutput`, whose refusal carries
  the ticket identity without the submitted result. The domain regression test
  exercises that command directly and rejects a missing Git output.

`npx vitest run tests-ts/conformance` runs the harness.

The execution-requirements scenario preserves distinct work and evaluator
references across pending revision, dispatch, work recovery, rework, and
evaluator recovery. Conversion requires the field and carries the reference
unread; it cannot satisfy replay by dropping the placement data. Three steps in
this scenario are
evolve-only: the initial state assertion and the refused active-ticket update
plus its repeated check.
