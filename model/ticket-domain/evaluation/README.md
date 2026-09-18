# Evaluation protocol

Evaluation is a pure protocol embedded in the ticket state. Its immutable plan contains sequential stages, each with parallel evaluators. A stage concludes after every evaluator has reported. Any explicit evaluator failure makes the evaluation fail; process failure or execution unavailability blocks it unless an evaluator has already failed. All passes advance to the next stage or conclude evaluation.

Each evaluator obligation derives its logical identity from the ticket, work cycle, stage key, stage generation, and evaluator key. Its single context reference identifies the exact accepted work result. A produced evaluator report supplies an explicit `EvaluatorPass` or `EvaluatorFail` verdict together with the validated task result. The adapter interprets the pinned result contract before submitting that verdict; the protocol never decodes exit codes, summaries, or findings.

A failed evaluator is retained as `{ evaluator, resultRef }` for rework. The immutable referenced result contains any reasons, findings, and process evidence for presentation to the next work task. The ticket chooses whether a concluded evaluation failure starts rework or escalates. Resuming a blocked stage increments its generation and reissues only blocked evaluators; passed results retain their exact references.

The ticket commits every accepted evaluator report, stage transition, next-stage obligation, and lifecycle decision through its one serialized decision stream. Stale task identities and produced results whose obligation differs from the current obligation are refused.

## Stage authority

The active stage run records one status per evaluator: Awaiting, Produced with a passed or failed result, ProcessFailed, or ExecutionUnavailable. A stage cannot conclude while any evaluator is Awaiting. A failed verdict is conclusive after the stage completes, even when another evaluator was blocked. Without a failed verdict, a blocked status yields EvaluationBlocked. Only a stage with all passes advances.

A task identity includes stage generation. Resumption increments that generation and resets only blocked statuses to Awaiting, so a late report from the prior generation is refused. The exact obligation is checked for produced reports, including task definition, result contract, and context reference. This prevents a current identity from admitting a result validated against a different pinned contract.
