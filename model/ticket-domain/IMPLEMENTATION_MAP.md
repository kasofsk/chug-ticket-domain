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
| `decideDependencies`, `dependencyClosure` | `decide_dependencies`, `_dependency_closure` in `src/ticket.ts`; the success decision is passed in rather than returned as an option |
| `finalizationCurrent` | `_finalization_current` in `src/ticket.ts`; guards both the finalization refusal and every finalization `evolve` branch |
| `EvaluationOrigin` (`OpenedByWork`, `Requested`), `originValid`, `evaluationRequested` | `OpenedByWork`, `Requested`, `origin_valid` in `src/evaluation.ts`; `evaluation_requested` in `src/ticket.ts` |
| `round` on `EvaluationTaskIdentity`, `EvaluationInstance`, `FinalizationOperation` | the `Round` brand in `src/task.ts`, a `round` field on `EvaluationTaskId`, `EvaluationInstance` and `FinalizationOperation` |
| `origin` on `FinalizationOperation`, `finalizationOriginValid` | an `origin` field on `FinalizationOperation`, `_finalization_origin_valid`; the origin of the evaluation the operation follows, kept across a resumed finalization |
| `FinalizationBasis` (`PassedVerdict`, `FailedVerdict`, `WithdrawnVerdict`) | Same classes in `src/ticket.ts`; only `FailedVerdict` carries a value, the evaluation that failed |
| `finalizationAfter`, `requestedEvaluation`, `failedBasisEntries` | `finalization_after`, `requested_evaluation`, `failed_basis_entries` |
| `FinalizationNeedsEvaluation`, `FinalizationFailureStands`, `FinalizationResultNotAllowed` | Same names in `src/ticket.ts`; the `ReportFinalizationResult` branch of `decide` reads the failure policy only for `FinalizationFailureStands`, where any disposition but rework escalates |
| `TicketEvaluationFailureReturned`, `TicketEvaluationWithdrawn`, `TicketFinalizationNeedsEvaluation`, `TicketFinalizationFailureReworked`, `TicketFinalizationFailureEscalated` | Same names in `src/ticket.ts` |
| `revocationAllowed` | `revocation_allowed` in `src/ticket.ts`; a Finalization is revocable on any basis but a pass |
| `decideInvalidated`, `invalidationCurrent` | inlined in the `InvalidateEvaluation` branch of `decide`, which picks the event by the evaluation's origin |
| `finalizationOperationValid`, `finalizationBasisValid`, `completionFollowsAPass` | `_finalization_operation_valid`, `_finalization_basis_valid`, `_completion_follows_a_pass` |
| `obligationAgrees`, `ticketLiveObligations` | `_obligation_agrees`, `_ticket_live_obligations` in `src/ticket.ts`; an `ExecuteTask` is the whole obligation of a task the decision made live, and a `FinalizeTicket` carries the ticket's own configuration |
| `obligationsComplete`, `obligationsExecute`, `obligationsFinalize` | `_obligations_complete` in `src/ticket.ts`, with the two lookups inlined; a decision obliges every task it makes live and every finalization operation it opens |
| the `evolved != graph` conjunct of `decisionValid` | `!equal(evolved, g)` in `decision_valid`; a decided event applies where it was decided |
| `InvalidateEvaluation`, `EvaluationNotCurrent`, `TicketEvaluationInvalidated`, `EvaluationInvalidated`, `invalidatedWorkInput` | Same names in `src/ticket.ts` (`invalidated_work_input`); cancels the live evaluation tasks and never consults the failure policy; an evaluation a work result opened starts a work cycle from the accepted source, a requested one is withdrawn to Finalization |
| `InvalidateEvaluationFailure(evidence)`, `TicketEvaluationFailureInvalidated` | Same names in `src/ticket.ts`; a failed verdict the policy answers this way is recorded and enters a `EvaluationInvalidated` work cycle instead of a rework or an escalation |
| `reportedTasks`, `orphansCancelled` | `_reported_tasks`, `_orphans_cancelled` in `src/ticket.ts`; a decision drops no live task without cancelling it, but for the task its report was about |
| `reportAdmissible` | inlined as `task_current(...)` in the evaluation branches of `_evolve` in `src/ticket.ts` |

A released ticket pins its content reference and nothing else about its material: task inputs are `workConfiguration.inputs` and each evaluator's `task.inputs`, so `WorkInput.released` is that one content reference rather than a record.

`TaskDefinition.executionRequirements` is an opaque reference like `workload`, `inputs`, and `resultContract`: the domain carries it into the obligation unchanged and never reads it, so capability, placement, and repository-access policy live in the application blob it names.

The model uses positive integers as opaque immutable references. Application storage and codec code attach meaning to them without changing lifecycle decisions. Work context references are scoped by work task identity; the application commits the referenced bundle with the decision. A produced work event pins its accepted source reference, and an evaluator event pins its verdict. These facts make replay independent of mutable branches, configuration, or result interpretation.
