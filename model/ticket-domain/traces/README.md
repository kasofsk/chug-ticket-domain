# Exported ticket-model traces

Reproducible ITF traces from `ticket_tests.qnt`, checked in so implementation
tests replay the specification without Quint installed. Generated: regenerate,
never hand-edit.

- `scenario-<name>.itf.json` — one per `run` definition in `ticket_tests.qnt`.
- `simulation-seed-<seed>.itf.json` — seeded random walks over `step`, 25 steps,
  checked against `modelInvariant`.
- `simulation-finalizer-seed-<seed>.itf.json` — seeded random walks over
  `finalizerStep` from `initFinalizing`, a ticket whose first evaluation has
  passed, 25 steps, checked against `finalizerInvariant`. A walk whose ticket
  finishes starts again from there (`restartFinalizing`).
- `index.json` — generated summary: per trace the state count, per step the
  action, decision and each ticket's phase, plus the coverage tables below.

## Regenerating

```sh
npm run export-traces   # from the repository root
```

Needs `quint` on `PATH` (written against 0.32.0). It exits non-zero if a Quint
command fails, if a scenario yields no trace, or if a trace's status is not
`ok`, and it deletes trace files it no longer produces. Rerun it after any model
change: scenarios are discovered from the source, so added, renamed and removed
`run` definitions need no edit to the script. It uses `quint test --out-itf`
for the named scenarios (the only subcommand that runs `run` definitions) and
`quint run --out-itf --seed ... --mbt --invariant=...` for the simulations,
with `--init` and `--step` for the finalizer's.

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

Compact JSON; `npx prettier model/ticket-domain/traces/index.json` renders the index for reading. Two things a
replay harness must know:

- State 0 of every scenario trace is `init`, whose `lastDecision` is the
  `noDecision` sentinel `TicketRefused(TicketNotFound(0))`, not a decision the
  model took. Skip it.
- A `check(...)` step re-emits the previous `lastDecision` unchanged, so equal
  consecutive decisions are normal and are not two decisions.

Simulation traces add two variables from `--mbt`: `mbt::actionTaken`, the
step alternative taken into that state, and `mbt::nondetPicks`, a record of
every name the model picks nondeterministically, each `Some(value)` where that
step picked it and `None` otherwise. Only the finalizer's `stray…` alternatives
pick anything: how far a command's address is from the current operation,
round or task (on it, or off it in one part), and its result or outcome. `actionTaken` and those picks
are the only place a trace names its input — the variables record `priorGraph`
and the resulting `lastDecision`, never the command. `quint test`
has no `--mbt`, so a scenario's inputs come from its `run` definition.

## Coverage

`ticket.qnt` declares no Quint `action`s — it is pure functions over these
types — so coverage is measured over the decision outcomes and lifecycle phases
the command paths produce. Every declared variant of `TicketEvent`,
`TicketState` and `TicketRefusal` is exercised.
`index.json` holds the live tables.

A refusal reaches a trace only when a scenario takes it through `submit`; one
asserted inside `check(decide(...) == TicketRefused(...))` leaves `lastDecision`
untouched and is invisible to replay.

`index.json` lists every scenario with its states and decisions.

Seeds chosen by set cover over decisions, phases and step alternatives, and
for the finalizer's walk over the situations `REQUIRED_FEATURES` in
`test/conformance/replay.ts` lists. A walk over `step` mostly churns in
`Pending` and `Revoked` and seldom reaches Finalization, which is why the
finalizer's walk exists. Consecutive small seeds give walks that share long
runs of steps, so candidates are spread over the seed space.

| walk | seed | phases reached | distinct step actions |
| --- | --- | --- | --- |
| `step` | `0x08d12e65` | Pending, Revoked | 10 |
| `step` | `0x3ba36b82` | Escalated, Evaluation, Pending, Revoked, Work | 13 |
| `step` | `0x7d8562c7` | Evaluation, Pending, Work | 13 |
| `step` | `0x96af9ca5` | Escalated, Evaluation, Pending, Work | 13 |
| `finalizerStep` | `0x54021d70` | Escalated, Evaluation, Finalization, Revoked, Work | 14 |
| `finalizerStep` | `0x7d37a438` | Done, Evaluation, Finalization, Revoked, Work | 11 |
| `finalizerStep` | `0x7f9a3c08` | Escalated, Evaluation, Finalization, Revoked, Work | 13 |
| `finalizerStep` | `0x99c008a8` | Done, Escalated, Evaluation, Finalization, Revoked, Work | 17 |
| `finalizerStep` | `0xbe1e08bb` | Done, Evaluation, Finalization, Revoked | 11 |
| `finalizerStep` | `0xda0af00d` | Escalated, Evaluation, Finalization, Revoked, Work | 15 |
| `finalizerStep` | `0xe25e5511` | Escalated, Evaluation, Finalization, Revoked, Work | 13 |
| `finalizerStep` | `0xfd4fa9a1` | Evaluation, Finalization, Work | 10 |

The `executionRequirementsPreserved` scenario records distinct work and
evaluator execution-requirement references through a pending revision,
dispatch, work failure/resume, evaluation rework, and evaluator
unavailability/resume. The scenario rejects an attempted active-ticket revision
and an absent requirements reference. The reference is opaque: no capability,
execution mode, or provider placement state is modeled.
