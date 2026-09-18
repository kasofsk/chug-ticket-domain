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

The model uses positive integers as opaque immutable references. Application storage and codec code attach meaning to them without changing lifecycle decisions. Work context references are scoped by work task identity; the application commits the referenced bundle with the decision. A produced work event pins its accepted source reference, and an evaluator event pins its verdict. These facts make replay independent of mutable branches, configuration, or result interpretation.
