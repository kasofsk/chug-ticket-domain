# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
npm test                       # vitest: domain tests + trace conformance + generator tests
npx vitest run test/conformance # one directory
npx vitest run -t "happyPath"  # one test by name (replay names tests after the trace file)
npm run typecheck              # tsc over src/, test/ and model/*.ts (build config only covers src/)
npm run build                  # emits dist/ from src/ (also run by `prepare` on install)
npm run format                 # prettier over src, test, and the config files
npm run export-traces          # regenerate model/ticket-domain/traces/ from the Quint model; needs `quint` on PATH
```

Model-level checks, run from `model/ticket-domain/`:

```sh
quint test ticket_tests.qnt
quint run --invariant=modelInvariant --max-steps=25 --max-samples=400 ticket_tests.qnt
```

## The central rule: the model leads

`model/` is the specification; `src/` is a transcription of it. Golden ITF
traces are exported from the model into `model/ticket-domain/traces/` and
replayed against `src/` by `test/conformance/`. **When the two disagree, the
implementation is wrong.** Any change to lifecycle behaviour goes: edit the
`.qnt`, add/adjust scenarios and invariants in `ticket_tests.qnt`, run the
Quint checks, `npm run export-traces`, then change `src/` until replay passes.
`model/ticket-domain/IMPLEMENTATION_MAP.md` is the name-by-name mapping from
each model definition to its TypeScript counterpart; keep it current.

Traces are generated artifacts — never hand-edit them. `export_traces.ts` is
deterministic (two runs are byte-identical) and is itself covered by
`test/export_traces.test.ts`, which drives it with a fake `quint`, so the
generator can be tested without Quint installed.

## Architecture

Three pure modules under `src/`, with dependencies pointing one way only —
`ticket` → `evaluation`, `task`; never the reverse:

- `task.ts` — the shared task-contract kernel: branded positive-int identities
  (`TicketId`, `CycleNumber`, `StageKey`, `Generation`, `EvaluatorKey`,
  `ContentRef`), `TaskDefinition`/`TaskObligation`/`TaskTerminal`, plus the
  structural `equal()` and `repr()` helpers everything else compares with.
  Task terminals are neutral (produced / process failed / execution
  unavailable); pass-fail meaning belongs to the owning protocol.
- `evaluation.ts` — the embedded evaluation protocol: stages, evaluator tasks,
  reduction to one conclusive `Passed`/`Failed`/`Blocked`. It is a pure
  protocol embedded in the ticket's `Evaluation` state, not a second aggregate,
  and has no independently committed state.
- `ticket.ts` — the lifecycle. The core shape is
  `decide(graph, command, policy) -> TicketDecision` (`TicketRefused |
  TicketDecided{event, obligations}`), `evolve(graph, event) -> TicketGraph`,
  with `apply_decision`/`apply_command` composing them and `graph_invariant` /
  `decision_valid` as the checkable predicates. `EvaluationFailurePolicy` — the
  rework-vs-escalate choice — is a caller-supplied function, not domain state.

`src/itf.ts` (exported as `@kasofsk/chug-ticket-domain/itf`) decodes ITF trace
JSON into immutable values without importing Quint or the domain;
`test/conformance/convert.ts` maps those into domain values and `replay.ts`
reconstructs the command behind each step. `src/testing.ts` holds the fixtures
and `Driver` that both the domain tests and the replay share; it is published
as `/testing` so consumers can reuse them.

### The purity line

The domain core has no I/O, no clock, no randomness, no persistence and no
third-party dependencies — that is what makes trace replay possible, and it is
the line to defend. Codecs, projections, persistence and execution adapters
belong to the consumer, not this package. Project identity is an application
routing key and must not enter ticket state.

### Value conventions

Every domain value is a frozen class with a literal `readonly kind`
discriminator and a union type over the variants; collections are copied and
frozen in the constructor. Model a legal phase as its own variant carrying
exactly the data valid in that phase rather than a common record with optional
fields. `int > 0` in the model becomes a positive-checked branded number, so
the model's positivity predicates live in constructors. Store released inputs
and committed facts; derive readiness, current task identities and other
deterministic consequences. A refusal is a domain outcome; infrastructure
inability is not. Function names are `snake_case`.

## Replay caveats

`test/conformance/README.md` is the detailed guide; the traps that bite:

- State 0 of a scenario is `init`, whose `lastDecision` is the `NO_DECISION`
  sentinel `TicketRefused(TicketNotFound(0))` — check for it before treating a
  step as a decision.
- A `check(...)` step re-emits the previous decision unchanged. Drive
  simulations from `steps()`, not `decisions()`, which collapses them.
- 20 of 345 steps are *evolve-only*: the trace does not determine the command,
  so only the state assertions run. Their `decide` coverage has to come from
  direct tests in `test/domain.test.ts`.
- Replaying the traces does **not** cover `SelfDependency`, `TaskNotCurrent` or
  `FinalizationNotCurrent`; those need direct `decide` tests.
- Compare maps and sets by content (`equal` from `task.ts`), never by the order
  a trace file lists them.

Note that `test/conformance/README.md` still refers to the harness files by
their pre-extraction paths (`tests-ts/…`, `itf.ts` inside the harness); the
real locations are `test/conformance/` and `src/itf.ts`.

## Scope guards

The directory `AGENTS.md` and `README.md` files state what each area owns and
refuses. Before changing lifecycle vocabulary read
`model/ticket-domain/README.md`; before touching the evaluation protocol read
`model/ticket-domain/evaluation/README.md`; before changing shared task
vocabulary read `model/task-contract/README.md`. `model/ticket-domain/` and
`model/task-contract/` must stay siblings — the `.qnt` files import across them
by relative path.
