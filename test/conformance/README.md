# Conformance harness

`src/itf.ts` decodes the traces in `model/ticket-domain/traces/` into TypeScript values
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

Two shapes exist: a scenario over `graph`, `lastDecision` and `priorGraph`, and
a simulation adding the two `mbt::` variables.

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
and checks that pairing again. Things it must not get wrong:

- The first step is always yielded, even when it equals `NO_DECISION`, the
  `init` sentinel `TicketRefused(TicketNotFound(0))`. A scenario asserting
  wholly inside `check(...)`, such as `stageKeyContractTest`, commits no
  decision at all, so check a step against `NO_DECISION` before treating it as
  one.
- Drive a simulation from `steps`, not `decisions`: many simulation steps
  repeat the previous decision exactly and `decisions` collapses them, some
  under a *different* `mbt::actionTaken`.
- No command is in a trace. A scenario's inputs live in its `ticket_tests.qnt`
  `run` definition; a simulation names its step alternative and, for the
  finalizer simulation's `stray…` alternatives, what the step picked.

## Replay

`convert.ts` converts decoded values into domain values (`graph_from_itf`,
`decision_from_itf`). `replay.ts` rebuilds the command behind a step
(`command_from_step`); `replay.test.ts` replays every trace and pins how many
steps it rebuilt a command for. Per step — the triple (`priorGraph`,
`lastDecision`, `graph`) the model recorded, which a `check(...)` step repeats
rather than extends — it asserts:

- `graph_invariant` on `priorGraph` and on `graph`;
- `decision_valid(priorGraph, lastDecision)`, the model's `decisionInvariant`;
- `apply_decision(priorGraph, lastDecision) == graph`, and on a decided step
  that `evolve_checked` agrees with it;
- `decide(priorGraph, command, policy) == lastDecision` wherever the command
  is recoverable.

A simulation names its step alternative in `mbt::actionTaken`, and each
alternative builds one command over the prior graph, a `stray…` alternative
also over what `mbt::nondetPicks` records it picked, so every simulation step
rebuilds, through the fixtures `src/testing.ts` transcribes from
`ticket_tests.qnt`. The finalizer simulation's `restartFinalizing` step is the
one exception: it decides nothing, and replay checks instead that it returned
to the graph that simulation starts from.

A scenario names nothing, so its command comes from the committed event, which
carries the whole report. The policy is the one input no report holds, and the
event names it: `TicketEvaluationReworkStarted` was decided under the rework
policy, `TicketEvaluationFailureEscalated` under the escalating one. A decided
`TicketFinalizationFailureEscalated` is replayed under every policy that is
not rework, the invalidating one and one the domain does not recognise among
them, because all of them must decide it.

A rebuilt `stray…` command is only as checked as its decision depends on it: a
refusal names the address and nothing else. So `replay.test.ts` requires the
corpus to hold the situations where it does depend on it
(`REQUIRED_FEATURES` in `replay.ts`): a stray evaluator result and a stray
evaluator failure that are accepted, a stray report with each result it can
carry addressed to the current operation, a stray invalidation that is
accepted, each of them refused while its target is live, a report for another
work cycle at the current generation, and each non-rework policy meeting a
failure that stands. The simulation seeds in `export_traces.ts` are chosen to hold
them; a change to the walk that loses one fails the suite until seeds that
hold it are chosen again.

**Evolve-only** is a step whose command the trace does not determine: the four
state assertions still run, only `decide` is out of reach. Some scenario steps
are in that class and no simulation step is:

- a scenario that asserts wholly inside `check(...)` commits no decision and
  still holds the `init` sentinel;
- a refused step: a refusal names the ticket and at most an address, never the
  command that was refused. The simulations cover `decide` over such commands,
  and `test/domain.test.ts` covers the refusal ladders directly.

`npx vitest run test/conformance` runs the harness.
