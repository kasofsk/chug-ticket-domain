# Ticket domain

This directory is the pure, project-partitioned ticket domain. Read
`README.md` before changing lifecycle vocabulary and read
`evaluation/README.md` before changing the embedded evaluation protocol.

- Put lifecycle rules, legal transitions, refusals, events, and obligations in
  the domain. Do not introduce persistence, NATS, Nomad, clocks, retries,
  authentication, or UI concepts.
- Model each legal phase as a distinct variant carrying exactly the data valid
  in that phase. Avoid common records filled with optional phase fields.
- Store released inputs and committed facts. Derive readiness, current task
  identities, cycle identities, and other deterministic consequences.
- Project identity is an application routing key and must not enter ticket
  state. Cross-project dependency references must remain unrepresentable.
- Domain decision contexts may rely on the application guarantee that exactly
  one writer serializes all ticket decisions for a project. This does not make
  the graph one aggregate: a lifecycle decision changes one ticket, and its
  only cross-ticket facts are the current states of its immediate immutable
  dependencies.
- Evaluation is an embedded pure protocol, not a second aggregate. It owns
  stages, evaluator task identities, reduction, and its single conclusive
  result; the ticket lifecycle interprets that result.
- A refusal is a domain outcome. Infrastructure inability is not.

When changing the Quint model, update scenarios and invariants in
`ticket_tests.qnt`. From `ticket-domain/`, validate with:

```sh
quint test ticket_tests.qnt
quint run --invariant=modelInvariant --max-steps=25 --max-samples=400 ticket_tests.qnt
```

The implementation transcribes this model and is checked against traces
exported from it; change the model first, then the implementation.
