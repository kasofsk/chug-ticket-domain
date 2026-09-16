# Ticket aggregate and decision context

## Problem

`TicketGraph` currently performs two different roles:

- it is the project-local identity and dependency environment; and
- it contains every ticket's mutable lifecycle state.

This makes the graph appear to be a project-sized aggregate even though a
domain decision changes one ticket. Reconstructing the entire graph for every
command is a recovery strategy, not an inherent domain requirement.

For example, creating a ticket with no dependencies requires only these facts:

- the ticket identity does not already exist; and
- the released ticket definition is valid.

No existing ticket lifecycle state is relevant. Creating a ticket with
dependencies additionally requires proof that each named dependency exists.
Because forward references are forbidden, requiring dependencies to exist at
admission also prevents a newly admitted ticket from introducing a cycle.

Other commands also have narrow decision contexts:

| Command | Required domain state |
| --- | --- |
| Create without dependencies | Absence of the proposed ticket identity |
| Create with dependencies | Identity absence and existence of each dependency |
| Update | The named ticket: its phase, its revision, and its dependency set |
| Dispatch | The named ticket and current state of its direct dependencies |
| Revoke or resume | The named ticket |
| Report task terminal | The named ticket |
| Report finalization result | The named ticket |

Update has the narrowest context of the definition-bearing commands. It reads
one ticket and nothing else: no dependency lifecycle state, because a revision
may not change the dependency set, and no other ticket, because the definition
it carries is already whole and valid on its own. The ticket's revision is the
concurrency token that makes the read sufficient — an update authored against a
definition that has since been replaced is refused with the current revision
rather than merged.

Accepted-input settlement and attribution are application reliability state.
They are not part of either a ticket or its dependency model.

## Recommended model

Treat one ticket as the normal lifecycle aggregate and separate the other
project-local facts by responsibility:

```text
Ticket                    one lifecycle aggregate
TicketDependencyIndex     ticket identities and immutable dependency edges
SettledInputIndex         application idempotency and attribution
```

`TicketDependencyIndex` names a domain decision environment or projection. It
does not imply that every ticket lifecycle must be loaded or persisted as one
aggregate.

Domain decisions should receive only their required context:

```text
decide_create(definition, identity_and_dependency_facts)
decide_dispatch(ticket, dependency_statuses)
decide_lifecycle(ticket, command)
```

Dependency rules remain domain-owned. The application gathers precise facts
and supplies them to the pure domain function; it does not interpret those
facts or decide whether a command is legal.

The executable domain exposes opaque, checked create, dispatch, and lifecycle
contexts. Their constructors reject missing, extra, duplicate, or mismatched
facts before a decision can run. The complete `TicketGraph` decision and
checked-evolution entry points remain temporarily as an equivalence oracle and
full-replay fallback while application materialization is introduced.

## Serialization is separate

Exactly one active writer owns a project ticket graph, every ticket within it,
and the derived decision materializations advanced from its outcomes. All
ticket decisions for that project are serialized through that writer. This is
an operational correctness assumption: overlapping writers, independently
advancing caches, or concurrent materializers are outside the supported model
until an explicit ownership and fencing design replaces it.

The project outcome journal is the serialized commit mechanism. A serialized
project stream and single writer do not make the entire project one aggregate.
They ensure that identity admission, dependency reads, and the changed ticket
state are based on one committed project order.

Within that order, dependency is the only cross-ticket relationship. Dispatch
loads the target ticket and the current states of exactly its immediate,
immutable dependencies. It does not need every unrelated ticket or a transitive
dependency traversal: a dependency can reach `Done` only through its own valid
lifecycle decisions, and `Done` cannot later be revoked. Create needs only
proof that its identity is absent and that its named dependencies exist at the
same committed position.

The current full replay exists because the outcome journal is the only durable
source from which decision state and settled-input attribution are rebuilt. It
is not required by the semantics of an independent ticket creation.

## Materialized recovery state

Do not cement the current all-ticket `TicketGraph` representation into a
monolithic checkpoint. Materialize journal-derived decision state by
responsibility:

- complete ticket aggregates keyed by `TicketId`, including each released
  definition, lifecycle state, counters, and embedded protocol state;
- project-local ticket identities and immutable dependency edges;
- exact settled `AcceptedInput` attribution keyed by `InputId`; and
- an anchored prefix proof binding the project, dense project position,
  materialization schema version, opaque adapter cursor, and exact identity and
  digest of the outcome at that position.

For each command, load only the ticket and dependency facts that its domain
decision requires, then validate and fold any journal suffix after the proven
materialization cursor.

The outcome journal remains authoritative. Materialized state is a replaceable
accelerator: a missing or stale materialization causes suffix or full replay,
while a corrupt, future, or mismatched materialization is rejected.

The opaque adapter cursor is location evidence, not proof by itself. Recovery
must verify the anchor and its project-local position against the journal before
trusting the materialized prefix or skipping any outcome.

All parts must represent one proven project prefix. The single-writer
assumption makes live in-process advancement serial, but it does not make
independently persisted keys atomic. Durable storage must publish one complete
generation or a commit marker that makes partial generations invisible.

## Implementation sequence and known limits

The implementation proceeds in evidence-preserving chunks:

1. make complete-prefix recovery linear and keep it as the correctness
   fallback;
2. introduce checked narrow domain contexts and prove them equivalent to the
   current full-graph decisions;
3. build one pure project materialization and verified suffix replay;
4. retain that materialization in the long-lived single writer;
5. measure restart state before selecting a durable checkpoint layout; and
6. implement the selected versioned accelerator and test stale, missing,
   corrupt, partial-write, write-conflict, and crash-at-each-boundary recovery.

Durable checkpointing is not assumed to be necessary or to fit one broker KV
value. The present complete replay accepts at most 10,000 project outcomes and
64 MiB of retained decoded record bodies. Those are correctness limits, not
performance targets: recovery may become operationally expensive before either
limit. Multiple writers, partial materialization generations, and trusting an
unproven cursor are outside the supported correctness envelope.

## Consequence

The architectural correction is not merely to replay the same project-sized
model faster. It is to stop treating reconstruction of every project ticket as
the universal decision context. This narrows aggregate boundaries, avoids
unnecessary reads, and permits recovery and checkpoint storage to follow the
facts each command actually needs.
