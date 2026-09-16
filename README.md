# @kasofsk/chug-ticket-domain

The Chuggernaut ticket domain, extracted so that Chuggernaut and Chuggy share one
copy instead of two: a Quint model of the ticket lifecycle, the pure TypeScript
core refined from it, and the conformance harness that holds the two together.

**The model leads.** `model/` is proved first and emits golden traces into
`model/ticket-domain/traces/`; `src/` grows up against them. When the two
disagree, the implementation is wrong.

## Layout

| Path | What |
| --- | --- |
| `src/` | The domain core: `ticket.ts`, `task.ts`, `evaluation.ts` |
| `model/ticket-domain/` | `ticket.qnt`, `ticket_tests.qnt`, `evaluation/`, `traces/` |
| `model/task-contract/` | `task.qnt`, imported by the ticket and evaluation modules |
| `test/` | Domain tests and the trace-replay conformance harness |

The two model directories are siblings because the `.qnt` files import across
them by relative path; moving either one breaks the model.

## Install

```sh
npm i github:kasofsk/chug-ticket-domain#v0.1.0
```

`dist/` is not committed. npm runs `prepare` when installing a git dependency,
so the TypeScript is built at install time.

## Use

```ts
import { ticket, task, evaluation } from "@kasofsk/chug-ticket-domain";
// or a single module
import * as k from "@kasofsk/chug-ticket-domain/ticket";
```

The `.qnt` sources and traces resolve through the package too, so a consumer
points `quint` at `node_modules` rather than keeping its own copy:

```
@kasofsk/chug-ticket-domain/model/ticket-domain/ticket.qnt
```

## What belongs here

The domain core is pure: no I/O, no clock, no randomness, and no dependencies —
the only imports are the three files referencing each other. That is what makes
the trace replay possible, and it is the line to defend. Codecs, projections,
persistence and execution adapters are the consumer's, not this package's.

## Gates

```sh
npm test         # domain tests + trace conformance
npm run typecheck
npm run build
npm run export-traces   # regenerates traces from the model; needs quint
```
