# Quint to TypeScript implementation map

The executable specification is `task-contract/task.qnt`, `ticket-domain/evaluation/evaluation.qnt`, and `ticket-domain/ticket.qnt`. The TypeScript transcription is `src/task.ts`, `src/evaluation.ts`, and `src/ticket.ts` respectively. `test/conformance` replays traces exported from Quint against those modules.

| Quint value or operation | TypeScript counterpart |
| --- | --- |
| `TaskDefinition`, `TaskObligation`, `ValidatedTaskResult` | Same classes in `src/task.ts`; obligation has one `context_ref`, result has one `result_ref` |
| `WorkTask`, `EvaluationTask` | `WorkTaskId`, `EvaluationTaskId` |
| `EvaluationInstance`, `applyProduced`, `applyFailure`, `resumeBlocked` | `EvaluationInstance`, `apply_produced`, `apply_failure`, `resume_blocked` |
| `EvaluationReworkEntry` | `EvaluationReworkEntry(evaluator, result_ref)` |
| `ReleasedTicket`, `WorkInput`, `FinalizationOperation` | Same classes in `src/ticket.ts` |
| `TaskTerminalReport` variants | `WorkResultReport`, `EvaluationResultReport`, `TerminalFailureReport` |
| `decide`, `evolve`, `applyDecision`, `graphInvariant` | `decide`, `evolve`, `apply_decision`, `graph_invariant` |
| `finalizationCurrent` | `_finalization_current` in `src/ticket.ts`; guards both the finalization refusal and the three finalization `evolve` branches |
| `reportAdmissible` | inlined as `task_current(...)` in the evaluation branches of `_evolve` in `src/ticket.ts` |

A released ticket pins its content reference and nothing else about its material: task inputs are `workConfiguration.inputs` and each evaluator's `task.inputs`, so `WorkInput.released` is that one content reference rather than a record.

`TaskDefinition.executionRequirements` is an opaque reference like `workload`, `inputs`, and `resultContract`: the domain carries it into the obligation unchanged and never reads it, so capability, placement, and repository-access policy live in the application blob it names.

The model uses positive integers as opaque immutable references. Application storage and codec code attach meaning to them without changing lifecycle decisions. Work context references are scoped by work task identity; the application commits the referenced bundle with the decision. A produced work event pins its accepted source reference, and an evaluator event pins its verdict. These facts make replay independent of mutable branches, configuration, or result interpretation.
