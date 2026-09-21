# Ticket lifecycle

The ticket model is the specification of record for release, dispatch, work cycles, embedded evaluation, rework, escalation, finalization, dependencies, revocation, decisions, events, and obligations. `ticket.qnt` is checked by `ticket_tests.qnt` and transcribed into the TypeScript core.

A released ticket pins one opaque immutable content reference, an input-bindings reference, the work task definition, evaluation plan, finalization configuration, and same-project dependencies. The referenced content retains its exact authored or historical shape. The application interprets it when preparing task context; the domain does not invent missing fields.

Dispatch accepts an opaque immutable source reference after the application validates source policy. A work obligation contains the work task identity, pinned definition, and a single context reference scoped by `(ticket, cycle)`. The application commits the immutable context bundle under that identity with the accepted decision. Structured `WorkInput` retains the released content reference, rework causes, and retry evidence so the bundle can be recreated and checked without relying on mutable configuration.

A produced work report carries the validated result and an accepted source reference. The application validates provenance and any repository access or destination policy before submission. The accepted event pins both references; evaluation receives the exact result reference, while rework and finalization retain the accepted source reference. The source and finalization destination may name different repositories outside this model.

A produced evaluator report carries the validated result and an explicit pass or fail verdict. The evaluation protocol records the exact result reference and reduces stages. Rework retains each failed evaluator's identity and result reference. Process failure and execution unavailability carry only task identity and evidence; they do not imply a verdict or accepted source.

The domain accepts a produced report only when its full task obligation equals the current obligation. Task failures require the current task identity. Late, stale, or mismatched reports are refused. Accepted commands, their events, and their resulting obligations are deterministic from pinned inputs and state. Finalization records an explicit succeeded, needs-work, or unavailable outcome and never infers success from infrastructure inability.

Repository identities, Git output checks, result decoding, context rendering, and execution placement belong to authoring and application adapters. They must validate against the pinned ticket and task contracts and report failures explicitly.

## Decision ownership

A single project writer serializes every accepted input and commits its event, resulting ticket state, and obligations together. A ticket decision changes one ticket. It may read only the current states of that ticket's immediate immutable dependencies. A pending ticket is ready when those dependencies are Done; an updated pending ticket cannot change its dependency set. Dependency references remain same-project by construction, because project identity is an application routing key outside ticket state.

The seven lifecycle phases are Pending, Work, Evaluation, Finalization, Escalated, Done, and Revoked. Each phase carries only facts that are valid there. Work cycle numbers, evaluator task identities, and finalization generations derive from committed state. Revocation withdraws active task authority and emits cancellation obligations. Late reports are refused after the state has moved on.

Evaluation is embedded in the ticket, not independently committed. Stages run in order; evaluators within a stage may report in any order. The ticket owns the policy choice between immediate rework and escalation when evaluation concludes with a failed verdict. A blocked evaluation can resume the same stage at a new generation while keeping already passed evaluator results. A new work cycle begins after rework or an operator's Work failure resumption.

Finalization has separate authority because it can conditionally mutate an external destination. Its operation pins work cycle, generation, accepted result reference, and accepted source reference. The finalizer reports Succeeded, NeedsWork, or Unavailable with immutable evidence. NeedsWork starts another work cycle with that evidence. Unavailable escalates, and a resumed finalization increments generation without changing its pinned input. The finalizer's destination and Git policy are resolved from the ticket's pinned configuration by the application.

## Replay and boundaries

Every event stores the facts that cannot be rederived from prior domain state: a released definition, dispatch source, accepted work result and source, explicit evaluator verdict and result, and finalization outcome. `evolve` applies those facts without reading a mutable branch, configuration, or result payload. The application's versioned codec or data migration must preserve historical accepted meanings, including combined released content and old result structures. It must never reinterpret them using today's result contract.

The domain checks logical authority: current identity, exact obligation for produced results, legal phase, dependency state, and finalization generation. Adapters check material authority: source provenance, repository access, typed result contract, and finalization destination policy. A material validation failure is not converted into a successful produced terminal. This keeps a gate that cannot run from reporting success.
