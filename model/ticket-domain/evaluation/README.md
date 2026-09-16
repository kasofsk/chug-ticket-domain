# Evaluation protocol

## Boundary

Evaluation is a small pure protocol between the ticket lifecycle and common
task execution. It owns how one accepted work result is examined and reduced to
one conclusive evaluation result.

This is a separately modeled pure protocol embedded in the `TicketGraph`
aggregate, not a separate aggregate, journal, service, or executable-unit type.
The shared task contract contains no Work/Evaluation discriminator. Evaluation
meaning comes from this protocol's interpretation of the prescribed task output.

The ticket domain owns entering `Evaluation` and interpreting the protocol's
conclusive `Pass`, `Fail`, or `Blocked` result. The evaluation protocol owns:

- one stable owning work-cycle identity for one accepted work result;
- an immutable resolved evaluation plan;
- sequential stage activation;
- parallel evaluator tasks within the active stage;
- collecting task terminals in any order;
- stage conclusions and advancement;
- one conclusive evaluation result;
- cancellation of outstanding evaluator tasks when evaluation authority is
  withdrawn.

It does not own the policy that classifies a conclusive failure as rework or
escalation, lifecycle transitions, physical task attempts, provider resolution,
Nomad placement, or runner supervision.

## Aggregate integration

`TicketGraph` embeds the complete `EvaluationInstance` in the ticket's
`Evaluation` state. The evaluation module provides pure operations over that
value; it has no independently committed state.

```text
matching Work task terminal
  -> begin EvaluationInstance
  -> emit first-stage TaskObligations

matching evaluator TaskTerminal
  -> update EvaluationInstance
  -> emit next-stage TaskObligations, or
  -> apply the conclusive result to the ticket lifecycle
```

Each arrow is part of one serialized `TicketGraph` decision. Starting an
evaluation and entering the ticket's `Evaluation` phase commit together. A
stage conclusion and its next-stage task obligations commit together. A
conclusive evaluation result and the resulting ticket transition commit
together.

Evaluator terminals therefore return to `TicketGraph` as task-terminal
commands. The ticket verifies that the task belongs to its current embedded
evaluation and delegates the state reduction to this module. There is no
`StartEvaluation` delivery, separate evaluation journal, or
`ReportEvaluationResult` callback.

Revocation cancels the embedded instance and withdraws its outstanding task
authority in the same ticket decision. Late task terminals are rejected because
their evaluation or task identity is no longer current.

## Ticket document and runtime

Two values have different lifetimes:

```text
ResolvedEvaluationPlan
  complete immutable value embedded in a ticket release

EvaluationInstance
  runtime protocol state for one accepted work result
```

The ticket draft contains the evaluation plan directly. An editor may copy a
saved YAML snippet into that draft, but the draft retains no snippet reference,
inheritance, or provenance. Application-level validation constructs the
complete plan and embeds it unchanged in `ReleasedTicket`. Runtime never
resolves editor material.

## Evaluation identity

One accepted work result creates exactly one evaluation instance. Its identity
is derived from the owning ticket and Work-cycle identity rather than allocated
by Evaluation or supplied by an executor:

```text
EvaluationInstance {
  work cycle identity
  accepted result manifest
  resolved evaluation plan
  protocol state
}
```

Infrastructure attempts retain the same task identity. Resumption after a
conclusive unavailable stage retains the work-cycle identity, starts a new run
generation of that stage, keeps its passed evaluator results, and gives only
the failed or unavailable evaluators new task identities. A conclusive
evaluation failure ends the instance. Rework produces a new work cycle, task,
and result, which create a new work-cycle identity.

Every evaluator task derives authority from the work-cycle identity and reads
the exact accepted result manifest. Evaluation never modifies the work artifact
or advances a ticket branch.

## Plan shape

A resolved plan is an ordered nonempty list of nonempty stages:

```text
ResolvedEvaluationPlan {
  stages: List<EvaluationStage>
}

EvaluationStage {
  key
  evaluators: NonEmptyList<EvaluatorDefinition>
}
```

Stage and evaluator keys are stable and unique in their enclosing plan scope.
The evaluator list order is definition order, not execution order. It gives the
decision a deterministic obligation ordinal while all evaluators in the stage
remain eligible in parallel. An evaluator task identity is derived from the
work-cycle identity, stage key, stage-run generation, and evaluator key.
Completion order never creates identity. The first run has generation one;
only recovery from a conclusive unavailable stage increments it.

An evaluator independently selects an agent or script workload and its task
execution requirements:

```text
EvaluatorWorkload =
  | AgentTask(agent configuration)
  | ScriptTask(script configuration)
```

The common task layer executes both variants. The evaluation protocol sees
their neutral task terminals and interprets evaluator result manifests.

## Sequential stages and parallel tasks

Only the active stage may have live evaluator tasks. All tasks in that stage
become eligible together and may complete in any order. No task in a later stage
becomes eligible until the active stage has concluded `Pass`.

```text
stage 1 task A ─┐
                ├─ stage 1 Pass ─> stage 2 task C ─┐
stage 1 task B ─┘                                  ├─ conclusion
                                  stage 2 task D ─┘
```

Putting evaluators in the same stage expresses parallel independence. Putting
them in successive stages expresses contingency:

```yaml
stages:
  - key: agent-review
    tasks:
      - key: correctness
        workload:
          kind: agent

  - key: ci
    tasks:
      - key: tests
        workload:
          kind: script
```

Here CI starts only if the agent-review stage passes. If agent review fails or
is unavailable, CI never starts.

The only V1 control-flow condition is:

> The next stage starts if and only if the current stage passes.

There are no arbitrary `depends_on` edges, conditional expressions, loops,
joins, evaluator-created stages, or task-produced workflow definitions. Stage
ordering is control flow rather than an artifact-transformation graph.

Every evaluator receives the same immutable accepted work result. Passing a
stage changes only which stage is eligible next; it does not add that stage's
reasons, result manifests, typed outputs, or process evidence to later task
inputs. Those results remain evaluation history. If one task must consume
another task's output, that is explicit dataflow and belongs to a separately
modeled pipeline rather than evaluation stage ordering.

## Evaluator results

Evaluation owns only the small result needed to reduce the protocol and explain
the decision:

```text
EvaluatorResult =
  | Passed { reason, resultManifest }
  | Failed { reason, resultManifest }

EvaluationReason =
  | Summary(bounded text)
  | ExitCode(integer)
```

The evaluator's declared result contract admits only a validated bounded value
to `ResultProduced`; Evaluation then interprets that value as the following
domain result. The enclosing variant makes the verdict explicit. The reason is deliberately
small: an agent or human-oriented evaluator can return a useful summary, while
an exit-status evaluator can retain the exact code without manufacturing prose.
The result manifest points to the common task result and its declared typed
outputs.

The project review-result contract may return ordered structured findings on a
failed verdict. A finding has only an identity stable within that evaluator
result and a concrete bounded description. Passing results cannot carry
findings. Other evaluator contracts may still declare no findings or use typed
outputs such as SARIF, JUnit, reports, or screenshots; those do not become
evaluation control flow.

This supports both a minimal `Pass` or `Fail` with a reason and a rich evaluator
whose typed output happens to contain artifact-anchored locations. Location is
the concern of that output type, not a mandatory field on every evaluation
result.

A stage that cannot conclude is `Blocked`, whether its evaluators process-failed,
were never executed, or both at once. Work splits those two causes into separate
escalations because its evidence is opaque and the variant name is the only place
the cause can live. Evaluation keeps one wall: the retained instance records a
per-evaluator `ProcessFailed` or `ExecutionUnavailable` status, so the cause is
already legible — and a single stage may hold both, which no one variant name
could describe without discarding a true fact.

`Failed { ... }` means the evaluator successfully rejected the work.
`ProcessFailed` means it did not produce a result satisfying its declared
contract. `ExecutionUnavailable` means the responsible executor conclusively
could not obtain one. Those outcomes remain distinct.

## Script result adapters

A script evaluator selects its result adapter in released configuration. V1
supports two shapes:

```text
StructuredResult
  script explicitly produces Passed or Failed with a Summary reason
  and all outputs declared by its result contract

ExitStatusResult
  normal process exit produces Passed or Failed with an ExitCode reason
  according to the evaluator's explicit code mapping
```

For an exit-status adapter, pass and fail code sets are disjoint and every other
code is a process failure. Signals, OOM termination, timeout, cancellation, and
loss of the allocation remain operational outcomes rather than evaluation
verdicts. There is no universal assumption that every nonzero code means the
work failed evaluation.

The runner captures stdout and stderr separately for every script attempt.
Bounded tails and the exact exit code travel with the result context; complete
streams are immutable execution-evidence artifacts subject to retention and
size policy. Rework presentation includes the failing evaluator's reason and
bounded streams by default, so an exit-code result is actionable even when the
script declares no richer output. Declared typed outputs supplement this
standard process evidence rather than replacing it.

When evaluation fails, the next work cycle receives at least one bounded entry
for every evaluator that returned `Failed`:

```text
EvaluationReworkEntry {
  evaluator identity
  reason
  result manifest and declared typed outputs
  ordered structured findings // project review results
  stdout tail? // scripts
  stderr tail? // scripts
}
```

The executable model carries evaluator key, reason, result manifest, and exact
ordered findings as `EvaluationReworkEntry`, and the ticket domain binds that
list into the next Work cycle's `EvaluationRework` cause. Legacy failed results
without findings remain readable as explicit empty structured feedback; their
summary remains the reason rather than an invented finding. Stream tails and
declared typed outputs are specified here but sit below the model's grain.

The complete retained streams remain linked artifacts. This is automatic
rework context, not an output schema every script author must declare. Passing
results remain available in evaluation history but are not required in the
next work task's prompt.

Each evaluator in a stage run occupies exactly one protocol status. The task
identity derives from the enclosing ticket, Work cycle, stage, generation, and
evaluator key; operational failures retain only their authoritative evidence:

```text
EvaluatorStatus =
  | Awaiting
  | Produced(evaluator result)
  | ProcessFailed(evidence)
  | ExecutionUnavailable(evidence)

StageRun {
  stage index
  generation
  evaluator key -> EvaluatorStatus
}
```

The released evaluator list remains the source of deterministic obligation and
evidence ordering; the status map is keyed by those same evaluator keys. One
evaluator therefore cannot be outstanding, passed, failed, and unavailable at
the same time.

Each phase owns exactly the history and active stage meaningful in that phase:

```text
EvaluationState =
  | Running { completed stages, active stage run }
  | Passed { completed stages }
  | Failed { completed stages }
  | Blocked { completed stages, blocked stage run }
```

Stage conclusions are derived from their evaluator statuses rather than stored
as a second value that could disagree with them. Concluding a stage appends its
complete result record before activating a later stage or concluding the
evaluation. Revocation belongs to the ticket lifecycle:
the ticket becomes `Revoked` and emits cancellation obligations for live
evaluator tasks rather than storing an evaluation cancellation state.

## Stage conclusion boundary

Every active-stage task reaches a terminal state before the stage concludes.
V1 has one fixed reduction rule rather than configurable criteria:

```text
any Failed result                           -> Fail
otherwise, any missing result               -> Blocked
otherwise, every evaluator produced Passed  -> Pass
```

`Pass` starts the next stage or concludes the evaluation successfully after the
last stage. `Fail` and `Blocked` conclude the evaluation without starting a
later stage. A known evaluator failure takes precedence over concurrent process
failure or unavailability because rework is already known to be necessary.
There are no quorum, threshold, weighted, optional, or author-defined reduction
policies.

## Initial invariants

1. One accepted work result identifies one evaluation instance.
2. An evaluation's identity, input, and resolved plan never change.
3. A plan has at least one stage, and every stage at least one evaluator.
4. Stage keys are unique within a plan and evaluator keys within a stage.
5. Only tasks from the active stage may be outstanding or report terminals.
6. Every active-stage evaluator task has one stable identity.
7. Every active-stage evaluator has exactly one status, and only `Awaiting`
   accepts a terminal for its task identity.
8. Active-stage task terminals may arrive in any order and are idempotent by
   evaluator task identity.
9. A stage cannot conclude while one of its tasks remains outstanding.
10. A stage passes exactly when every evaluator produces `Passed` with a valid
   result manifest.
11. Any `Failed` result fails the stage; absent a fail, any task that cannot
    produce a valid result makes the stage unavailable.
12. A later stage starts only after the immediately preceding stage passes.
13. Every evaluator reads the same accepted work result; prior-stage results
    never become implicit inputs to a later stage.
14. Completed stage records are retained in stage order for the lifetime of the
    evaluation instance.
15. Stage failure or unavailability starts no later stage.
16. An evaluation has exactly one current protocol state; recovery replaces an
    `Blocked` state with one new `Running` stage run.
17. Resuming an unavailable stage retains produced results, retries only
    process-failed or execution-unavailable evaluators, and increments the
    stage-run generation.
18. Every evaluator task identity includes its stage-run generation, so a
    resumed evaluator is distinct from the task it replaces.
19. Agent and script evaluators obey the same stage protocol while retaining
    their distinct workload definitions and execution requirements.
20. Evaluation never modifies the accepted work artifact.
21. Rework creates a new work-cycle identity; infrastructure recovery does not.

## Open decisions

- The initial registry of reusable evaluator output contracts and which receive
  dedicated UI renderers.
