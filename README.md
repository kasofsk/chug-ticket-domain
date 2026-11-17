# @kasofsk/chug-ticket-domain

The ticket domain: a formal [Quint](https://quint-lang.org) model of a ticket's
lifecycle, a pure TypeScript implementation of that model, and a conformance
harness that replays traces from the model against the implementation.

A ticket is a unit of work with a pinned definition. It runs through work
cycles, gets evaluated, may be reworked or escalated, and is finally applied to
an external destination. This package decides what is legal at each step. It
does not run anything itself.

## The ticket lifecycle

A ticket is always in exactly one of seven phases. Each phase carries only the
data that is valid in that phase.

```
            dispatch                 result accepted          all stages pass
 Pending ────────────────▶ Work ─────────────────▶ Evaluation ────────────────▶ Finalization ──▶ Done
 (waits on                   ▲                         │  ▲                          │  │
  dependencies)              │   rework                │  │   needs evaluation       │  │
                             ├─────────────────────────┤  └──────────────────────────┘  │
                             │   failed (policy chooses rework or escalate)             │
                             └──────────────────────────────────────────────────────────┘
                                 needs work, or a failure that stands

 Escalated  ◀── work failure / execution unavailable / evaluation failed or blocked /
                finalization unavailable;   ResumeTicket continues from where it stopped
 Revoked    ◀── RevokeTicket from any phase except Done and a Finalization that may be completing
```

- **Pending.** The ticket has a released definition and a set of same-project
  dependencies. It can be dispatched once every dependency is Done. While it
  is Pending, its definition and dependencies can be updated, subject to
  revision checks and cycle checks.
- **Work.** A work task runs against a dispatched source. Each cycle has its own
  task identity, `(ticket, cycle)`.
- **Evaluation.** Evaluation is an embedded protocol, not a separate aggregate.
  Stages run in order. Evaluators within a stage run in parallel. The stages
  reduce to one conclusive result: `Passed`, `Failed` or `Blocked`. A
  caller-supplied `EvaluationFailurePolicy` decides whether a failure starts
  rework or escalates.
- **Finalization.** Finalization applies the accepted result to an external
  destination. It has its own authority and generation counter because it
  mutates something outside the domain. Its finalizer reports one of five
  results: `Succeeded`, `NeedsWork` (which starts another work cycle),
  `Unavailable` (which escalates), `NeedsEvaluation` or `FailureStands`.
- **Evaluating again.** `NeedsEvaluation` opens another evaluation of the same
  accepted result, in the same work cycle, with no work in between. The first
  evaluation of a work cycle is round 1 and each requested one is the next
  round. A requested round returns to Finalization however it concludes (a
  blocked one escalates first, as any evaluation does), and the operation it
  returns to says how as its _basis_, and names the request it answers as its
  _origin_:

  | The round                             | Basis       | What the finalizer may report next                         |
  | ------------------------------------- | ----------- | ---------------------------------------------------------- |
  | passed                                | `Passed`    | `Succeeded`, `NeedsEvaluation`, `NeedsWork`, `Unavailable` |
  | failed                                | `Failed`    | `FailureStands`, `NeedsEvaluation`, `NeedsWork`, `Unavailable` |
  | was withdrawn by `InvalidateEvaluation` | `Withdrawn` | `NeedsEvaluation`, `NeedsWork`, `Unavailable`              |

  A requested round's failure is not disposed when it concludes. The failure
  policy is asked only when the finalizer reports `FailureStands`, and then
  chooses rework or escalation; a policy that would invalidate the failure
  escalates instead, because a failure that stands is the ticket's own. The
  domain puts no bound on how many rounds a finalizer requests: that bound is
  the finalizer's.
- **Invalidating an evaluation.** `InvalidateEvaluation` abandons a running
  evaluation without a verdict and cancels its tasks. Where it goes next
  depends on what opened the evaluation:

  | Command                | Evaluation     | Event                         | Next state                    |
  | ---------------------- | -------------- | ----------------------------- | ----------------------------- |
  | `InvalidateEvaluation` | round 1        | `TicketEvaluationInvalidated` | Work, as `EvaluationInvalidated` |
  | `InvalidateEvaluation` | a later round  | `TicketEvaluationWithdrawn`   | Finalization, basis `Withdrawn` |

  Neither is counted as an evaluation failure. For a failed round 1 a failure
  policy may also answer `InvalidateEvaluationFailure`, which records the
  verdict and returns to Work the same way.
- **Escalated.** The ticket is waiting for an operator. Resuming it starts a new
  work cycle, re-runs the blocked evaluators at a new generation, or retries
  finalization at a new generation.
- **Done** and **Revoked** are terminal. Revoking a ticket cancels any
  outstanding tasks. A Finalization on a passed basis cannot be revoked,
  because it may be completing; its finalizer reports `Unavailable` first. On
  a failed or withdrawn basis nothing can complete, so the ticket can be
  revoked where it waits. No obligation is cancelled for that: the finalizer's
  outstanding `FinalizeTicket` is void once the ticket is Revoked, and a later
  report on it is refused.

Task reports are accepted only for the _current_ obligation. Once the state has
moved on, late, stale or mismatched reports are refused.

## The core API

The core follows a decide/evolve design over an immutable graph of tickets:

```ts
decide(graph, command, policy): TicketDecision  // TicketRefused | TicketDecided{ event, obligations }
evolve(graph, event): TicketGraph
apply_command(graph, command, policy): TicketGraph
```

- **Commands** are what callers ask for: `CreateTicket`, `UpdateTicket`,
  `DispatchTicket`, `RevokeTicket`, `ResumeTicket`, `InvalidateEvaluation`, `ReportTaskTerminal` and
  `ReportFinalizationResult`.
- **Refusals** are ordinary domain outcomes, such as `DependenciesIncomplete`,
  `TaskNotCurrent` or `TicketRevisionStale`. They are not exceptions.
- **Events** record the facts that can't be derived from earlier state. `evolve`
  replays them deterministically.
- **Obligations** tell the caller what to do next: `ExecuteTask`,
  `FinalizeTicket` or `CancelTask`. The caller commits the event, the new state
  and the obligations together.

`graph_invariant` and `decision_valid` are checkable predicates that mirror the
model's invariants.

The source is three modules, and dependencies only point one way
(`ticket` → `evaluation`, `task`):

| Module          | Contents                                                                                                                              |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `task.ts`       | The shared task contract: branded identities, task definitions and obligations, neutral task terminals, and structural `equal`/`repr` |
| `evaluation.ts` | The evaluation protocol: stages, evaluator tasks, and reduction to a single conclusion                                                |
| `ticket.ts`     | The lifecycle: commands, events, refusals, obligations, `decide`/`evolve`                                                             |

## What the domain does and doesn't own

The core is pure. It has no I/O, no clock, no randomness, no persistence and
no runtime dependencies. Content, sources, results and execution requirements
are opaque immutable references, which the domain pins and compares but never
interprets.

The domain checks **logical authority**: legal phase, current task identity,
exact obligation, dependency state and finalization generation. The consumer's
adapters check **material authority**: source provenance, repository access,
result decoding and destination policy. The consumer also owns codecs,
persistence, projections and execution.

## The model leads

`model/` is the specification, and `src/` is a transcription of it.

| Path                                        | Contents                                                         |
| ------------------------------------------- | ---------------------------------------------------------------- |
| `model/ticket-domain/ticket.qnt`            | The lifecycle model                                              |
| `model/ticket-domain/evaluation/`           | The evaluation protocol model                                    |
| `model/task-contract/task.qnt`              | The shared task contract model                                   |
| `model/ticket-domain/ticket_tests.qnt`      | Scenarios and invariants                                         |
| `model/ticket-domain/traces/`               | Golden ITF traces exported from the model                        |
| `model/ticket-domain/IMPLEMENTATION_MAP.md` | Mapping from each model definition to its TypeScript counterpart |

`test/conformance/` replays every trace against `src/`. **When the model and
the implementation disagree, the implementation is wrong.** A behaviour change
follows this order:

1. Edit the `.qnt`.
2. Add scenarios and invariants to `ticket_tests.qnt`.
3. Run `npm run check-model`.
4. Run `npm run export-traces`.
5. Change `src/` until replay passes.

The traces are generated artifacts. Don't edit them by hand.

## Install and use

```sh
npm i github:kasofsk/chug-ticket-domain#v0.9.0
```

`dist/` isn't committed. The `prepare` script builds it at install time.

```ts
import { ticket, task, evaluation } from "@kasofsk/chug-ticket-domain";
import * as t from "@kasofsk/chug-ticket-domain/ticket";

const decision = t.decide(
  graph,
  new t.DispatchTicket(id, source),
  t.rework_policy,
);
```

The package also exports these entry points:

- `@kasofsk/chug-ticket-domain/itf` decodes ITF trace JSON. It doesn't depend
  on Quint or on the domain.
- `@kasofsk/chug-ticket-domain/testing` provides fixtures and a `Driver` for
  tests.
- `@kasofsk/chug-ticket-domain/model/...` points at the `.qnt` sources and
  traces, so a consumer can run `quint` against the copy in `node_modules`.

## Development

```sh
npm test                # domain tests, trace conformance, generator tests
npm run typecheck
npm run build
npm run check-model     # the model's own checks (needs quint on PATH)
npm run export-traces   # regenerate traces from the model (needs quint on PATH)
```

`npm run check-model` runs `model/ticket-domain/check.sh`: the scenarios, a
simulation over every command from an empty graph, and a second simulation
that starts at a finalizer and so reaches the requested-evaluation states the
first seldom does. The second must reach each of those states in the run that
checks its invariants.
