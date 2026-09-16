# Shared task contract

## Decision

Work and evaluation execute through one shared task contract. This is a shared
kernel of immutable values, not a task domain, aggregate, service, or state
machine.

The owning protocol creates a task identity and definition, emits its
obligation, and interprets its terminal. An accepted executor obtains that
terminal without learning the task's business purpose.

```text
ticket Work --------\
                     -> TaskObligation -> execution -> TaskTerminal
evaluation stage ---/
```

Finalization is not a task. A finalizer may delegate bounded process execution
to the same runner, but its conditional mutation and reconciliation authority
uses a separate invocation and result contract.

## Values

```text
TaskDefinition {
  workload
  immutable inputs
  execution requirements
  result contract
}

TaskIdentity =
  | WorkTask { ticket, cycle }
  | EvaluationTask { ticket, work cycle, stage, generation, evaluator }

TaskObligation {
  task identity
  immutable task definition
  exact workspace source
  immutable runtime context
}

TaskTerminal =
  | ResultProduced(ValidatedTaskResult)
  | ProcessFailed { task identity, process evidence }
  | ExecutionUnavailable { task identity, reason }

ValidatedTaskResult {
  task obligation
  result manifest
  decoded bounded value
  result evidence = Legacy | Admitted { provider revision, canonical admitted result }
}
```

`TaskDefinition` is a value object. A logical task identity denotes exactly one
definition and remains stable across provider-specific retries.

The initial workspace source is a precise repository identity and canonical
Git commit. It is captured when dispatch is decided, not during authoring, so a
pending ticket can start from the finalized commits of its dependencies. The
source remains part of the immutable obligation across physical redelivery.
Evaluation derives the same value from the accepted work output.

Execution requirements contain the repository, its read-only or publish-result
access, and `requiredCapabilities`: an unordered set of opaque, nonempty names.
The empty set adds no placement requirement. Work and each evaluator carry
their own set in their immutable task definition. Updating a pending ticket
can revise that definition; dispatch freezes it for work, evaluation, rework,
and recovery. Physical redelivery carries the same obligation unchanged.

There is no execution mode in this contract. Capability names state what a task
requires; they do not identify a machine or attest its readiness. Provider job
identity, matching, placement deadlines, and secret locations stay outside the
shared model.

The TypeScript domain represents capability sets as copied, sorted, unique,
frozen arrays. The persisted codec omits empty capabilities and interprets an
absent field as empty, retaining existing command and outcome bytes. Nonempty
sets are preserved by the codec and conformance replay. Workload authoring and
Nomad capability enforcement are separate integration work; this contract does
not expose an authoring option for requirements the executor cannot enforce.

Those input kinds and presentation adapters may be extended incrementally.
They do not change the task terminal vocabulary or the ticket and evaluation
state machines.

There is no Work/Evaluation discriminator in a task definition, obligation, or
terminal. A task executes its instructions and produces the output prescribed
by its result contract. “Work task” and “evaluator task” describe the ticket
context that created and will interpret the task, not different executable-unit
types.

`ResultProduced` means the declared result exists and satisfies the immutable
result contract. It does not mean the owning protocol accepts the result's
business content. `ProcessFailed` means execution concluded without producing a
valid result. `ExecutionUnavailable` means the responsible executor
conclusively could not execute the task. Delivery retry or adapter
unavailability does not manufacture this terminal. Cancellation is not a task terminal: the owner has already
withdrawn authority before it emits `CancelTask`, so Execution settles that
instruction without reporting another domain result.

`ValidatedTaskResult` is the only produced-result value admitted to a task
terminal. Its production representation is opaque and can be constructed only
from a `TaskObligation` after validating against that obligation's immutable
result contract. It retains the exact obligation used as the proof input,
including the immutable task definition and runtime context, together with the
immutable manifest and decoded bounded value. Its task identity and context
derive from that obligation. Callers cannot independently supply a second task
identity or result-contract claim.

Result evidence distinguishes records created without retained provider output
from records that retain it. Admitted evidence contains the execution provider
revision and the complete, bounded, schema-admitted result value as canonical
JSON. It excludes request credentials and derives the remaining execution
identity from the enclosing accepted input, obligation, and manifest. The
project outcome journal therefore supplies immutable create-or-compare and
replay semantics without a second result-evidence store.

Every terminal carries its task identity exactly once. `ReportTaskTerminal`
therefore adds only the owning ticket routing identity; it does not repeat the
task identity in a sibling field that could disagree with the terminal.

`Pass`, `Fail`, rework, escalation, and lifecycle progression are deliberately
absent. The ticket domain supplies that meaning: its Work lifecycle interprets
a produced result as completion of the current work cycle, while its Evaluation
protocol interprets evaluator output, advances stages, and returns one
conclusive evaluation result to the ticket lifecycle.

## Result manifest

```text
ResultManifest {
  result-contract identity
  bounded structured metadata
  named immutable output references
}
```

The enclosing `ValidatedTaskResult` carries the logical task identity. The
manifest does not repeat it.

The task definition's typed result contract names required outputs, kinds, and
bounds. The executor decodes the bounded value and validates the manifest and
referenced outputs against that
contract before reporting `ResultProduced`. Output bodies remain outside the
domain boundary behind immutable references.

A Git `OutputRef` contains the exact repository identity and canonical commit.
A ticket-scoped branch may be projected as a mutable discovery aid, but it is
not result authority. Evaluation preserves the accepted work manifest across
stages, and finalization consumes the evaluated exact commit and verifies it
against the target before mutation.

Definitive absence, corruption, or contract mismatch means the process did not
produce a valid result and is reported as `ProcessFailed` with evidence.
Temporary inability to retrieve or verify result material remains an
application recovery condition; it does not fabricate either terminal.

Stdout, stderr, logs, and transcripts are execution evidence unless a result
contract explicitly gives them business meaning as declared outputs. Their
capture, storage, and presentation are outside this shared contract.

## Ownership

Ticket Work owns its work-cycle identity and transition on the matching
terminal. Its current task identity derives from the ticket and cycle rather
than being stored beside them. Being in `Work` already means that task is
logically outstanding; no duplicated common `TaskState` is needed.

The shared contract closes the initial identity vocabulary over its two owners.
A Work task derives from its ticket and Work-cycle identity. An evaluator task
derives from its ticket, Work-cycle identity, stage key, stage-run generation,
and evaluator key. Execution may obtain the owning ticket through the shared
contract but does not generate or reinterpret either identity variant.

Evaluation owns stages, evaluator identities, collected evaluator results, and
stage reduction. Evaluator task identities derive from the active stage run. A produced
manifest is decoded according to the evaluator's typed result contract before
Evaluation records `Passed` or `Failed`.

That ownership is modular, not transactional: the Evaluation protocol's state
is embedded in `TicketGraph`, and evaluator terminals are committed through the
same aggregate decision stream as ticket lifecycle transitions.

Execution accepts the durable obligation and returns the terminal through
accepted-input processing. Placement, supervision, retries, and durability are
provider-specific QoS and do not become logical task state.

## Initial invariants

1. One logical task identity denotes one immutable task definition.
2. Work and Evaluation use the same `TaskTerminal` variants and meanings.
3. A task has no independent business lifecycle or aggregate.
4. The owning ticket context alone creates the task and interprets its output.
5. Being in an owner phase determines whether its task is outstanding.
6. Provider-specific retries never change logical task identity or definition.
7. `ResultProduced` proves result-contract validity, not a domain verdict.
8. Cancellation is an owner instruction, not a `TaskTerminal`, and produces no
   owner result.
9. Finalization is not a task.
10. Task identity is created by the owning protocol, never by Execution or an
    execution provider.
11. `ResultProduced` contains only a `ValidatedTaskResult` matching the logical
    task and its immutable result contract.
