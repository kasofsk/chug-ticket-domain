module ticket_tests {
  import ticket_domain.* from "ticket"
  import task_contract.* from "../task-contract/task"
  import evaluation_protocol.* from "evaluation/evaluation"

  pure val WORK = {
    workload: 1,
    inputs: 1,
    executionRequirements: 1,
    resultContract: 1,
  }

  pure val EVALUATOR = {
    workload: 2,
    inputs: 2,
    executionRequirements: 2,
    resultContract: 2,
  }

  pure val PLAN = {
    stages: [
      {
        key: 10,
        evaluators: [
          { key: 11, task: EVALUATOR },
          { key: 12, task: EVALUATOR },
        ],
      },
      {
        key: 20,
        evaluators: [{ key: 21, task: EVALUATOR }],
      },
    ],
  }

  pure def source(ticket: int, ref: int): int = ref

  pure def dispatch(ticket: int): TicketCommand =
    DispatchTicket({ ticket: ticket, source: source(ticket, ticket * 1000 + 1) })

  pure def released(
    ticket: int,
    dependencies: Set[int],
  ): ReleasedTicket = {
    id: ticket,
    content: ticket * 100 + 1,
    dependencies: dependencies,
    workConfiguration: WORK,
    evaluationPlan: PLAN,
    finalizationConfiguration: 1,
  }

  pure def revised(
    ticket: int,
    dependencies: Set[int],
  ): ReleasedTicket = {
    ...released(ticket, dependencies),
    content: ticket * 100 + 51,
  }

  pure def updateTo(
    ticket: int,
    expectedRevision: int,
    definition: ReleasedTicket,
  ): TicketCommand = UpdateTicket({
    ticket: ticket,
    expectedRevision: expectedRevision,
    definition: definition,
  })

  var graph: TicketGraph
  var priorGraph: TicketGraph
  var lastDecision: TicketDecision

  pure val noDecision: TicketDecision = TicketRefused(TicketNotFound(0))

  pure def reworkPolicy(
    evaluation: EvaluationInstance,
  ): EvaluationFailureDisposition = ReworkEvaluationFailure

  pure def escalatePolicy(
    evaluation: EvaluationInstance,
  ): EvaluationFailureDisposition = EscalateEvaluationFailure

  pure def invalidateZeroPolicy(
    evaluation: EvaluationInstance,
  ): EvaluationFailureDisposition = InvalidateEvaluationFailure(0)

  pure def invalidatePolicy(
    evaluation: EvaluationInstance,
  ): EvaluationFailureDisposition = InvalidateEvaluationFailure(1601)

  action init = all {
    graph' = { tickets: Map() },
    priorGraph' = { tickets: Map() },
    lastDecision' = noDecision,
  }

  action submitWithPolicy(command, failurePolicy) = all {
    commandValid(command),
    priorGraph' = graph,
    lastDecision' = decide(graph, command, failurePolicy),
    graph' = applyCommand(graph, command, failurePolicy),
  }

  action submit(command) =
    submitWithPolicy(command, reworkPolicy)

  action check(condition) = all {
    assert(condition),
    graph' = graph,
    priorGraph' = priorGraph,
    lastDecision' = lastDecision,
  }

  action blocked = all {
    false,
    graph' = graph,
    priorGraph' = priorGraph,
    lastDecision' = lastDecision,
  }

  action reportWorkResultWithSource(ticketId, resultRef, acceptedSourceRef) = {
    if (not(graph.tickets.keys().contains(ticketId))) blocked
    else {
      val ticket = graph.tickets.get(ticketId)
      match ticket.state {
        | Work(work) => {
            val obligation =
              workTaskObligation(ticket, ticket.workCyclesStarted, work.source, work.input)
            submit(ReportTaskTerminal(WorkResultReport({
              ticket: ticketId,
              result: validatedTaskResult(obligation, resultRef),
              acceptedSourceRef: acceptedSourceRef,
            })))
          }
        | _ => blocked
      }
    }
  }

  action reportWorkResult(ticketId, resultRef) =
    reportWorkResultWithSource(ticketId, resultRef, source(ticketId, resultRef))

  action reportWorkFailure(ticketId, evidence, kind) = {
    if (not(graph.tickets.keys().contains(ticketId))) blocked
    else {
      val ticket = graph.tickets.get(ticketId)
      match ticket.state {
        | Work(work) => {
            val obligation = workTaskObligation(ticket, ticket.workCyclesStarted, work.source, work.input)
            submit(ReportTaskTerminal(TerminalFailureReport({
              ticket: ticketId,
              failure: { task: obligation.task, evidence: evidence },
              kind: kind,
            })))
          }
        | _ => blocked
      }
    }
  }

  action reportWorkProcessFailed(ticketId, evidence) =
    reportWorkFailure(ticketId, evidence, ProcessFailure)

  action reportWorkExecutionUnavailable(ticketId, evidence) =
    reportWorkFailure(ticketId, evidence, ExecutionUnavailableFailure)

  action reportEvaluatorResult(ticketId, resultRef, verdict) =
    reportEvaluatorResultWithFailureDisposition(ticketId, resultRef, verdict, reworkPolicy)

  action reportEvaluatorResultWithFailureDisposition(
    ticketId,
    resultRef,
    verdict,
    failurePolicy,
  ) = {
    if (not(graph.tickets.keys().contains(ticketId))) blocked
    else {
      val ticket = graph.tickets.get(ticketId)
      match ticket.state {
        | Evaluation(evaluation) => {
            val obligation = currentTaskObligations(evaluation)[0]
            submitWithPolicy(ReportTaskTerminal(EvaluationResultReport({
              ticket: ticketId,
              result: validatedTaskResult(obligation, resultRef),
              verdict: verdict,
            })), failurePolicy)
          }
        | _ => blocked
      }
    }
  }

  action reportEvaluatorFailure(ticketId, evidence, kind) = {
    if (not(graph.tickets.keys().contains(ticketId))) blocked
    else {
      val ticket = graph.tickets.get(ticketId)
      match ticket.state {
        | Evaluation(evaluation) => {
            val obligation = currentTaskObligations(evaluation)[0]
            submit(ReportTaskTerminal(TerminalFailureReport({
              ticket: ticketId,
              failure: { task: obligation.task, evidence: evidence },
              kind: kind,
            })))
          }
        | _ => blocked
      }
    }
  }

  action reportEvaluatorUnavailable(ticketId, evidence) =
    reportEvaluatorFailure(ticketId, evidence, ExecutionUnavailableFailure)

  action reportEvaluatorProcessFailed(ticketId, evidence) =
    reportEvaluatorFailure(ticketId, evidence, ProcessFailure)

  action invalidateEvaluation(ticketId, evidence) = {
    if (not(graph.tickets.keys().contains(ticketId))) blocked
    else {
      val ticket = graph.tickets.get(ticketId)
      match ticket.state {
        | Evaluation(evaluation) => submit(InvalidateEvaluation({
            ticket: ticketId,
            workCycle: evaluation.workCycle,
            round: evaluation.round,
            evidence: evidence,
          }))
        | Escalated(escalation) => match escalation {
            | EvaluationBlockedEscalated(saved) => submit(InvalidateEvaluation({
                ticket: ticketId,
                workCycle: saved.workCycle,
                round: saved.round,
                evidence: evidence,
              }))
            | _ => blocked
          }
        | _ => blocked
      }
    }
  }

  action reportFinalization(
    ticketId,
    result,
  ) = {
    if (not(graph.tickets.keys().contains(ticketId))) blocked
    else {
      val ticket = graph.tickets.get(ticketId)
      match ticket.state {
        | Finalization(finalization) => submit(ReportFinalizationResult({
            ticket: ticketId,
            workCycle: finalization.workCycle,
            generation: finalization.generation,
            result: result,
          }))
        | _ => blocked
      }
    }
  }

  def ticketRevision(ticketId: int, revision: int): bool =
    graph.tickets.get(ticketId).revision == revision

  def ticketDefinition(ticketId: int, definition: ReleasedTicket): bool =
    graph.tickets.get(ticketId).definition == definition

  def decidedWorkContexts: List[int] = match lastDecision {
    | TicketDecided(success) => success.obligations.foldl([], (found, obligation) =>
        match obligation {
          | ExecuteTask(execution) => found.append(execution.task.contextRef)
          | _ => found
        })
    | TicketRefused(_) => []
  }

  pure def currentEvaluatorReport(
    ticketId: int,
    evaluation: EvaluationInstance,
    resultRef: int,
    verdict: EvaluationVerdict,
  ): TaskTerminalReport = EvaluationResultReport({
    ticket: ticketId,
    result: validatedTaskResult(
      currentTaskObligations(evaluation)[0],
      resultRef,
    ),
    verdict: verdict,
  })

  pure def graphFinalizing(candidate: TicketGraph, ticketId: int): bool =
    match candidate.tickets.get(ticketId).state {
      | Finalization(_) => true
      | _ => false
    }

  def ticketDone(ticketId: int): bool =
    graph.tickets.get(ticketId).state == Done

  def ticketFinalizing(ticketId: int): bool =
    match graph.tickets.get(ticketId).state {
      | Finalization(_) => true
      | _ => false
    }

  def ticketWorkCycle(ticketId: int, cycle: int): bool = {
    val ticket = graph.tickets.get(ticketId)
    match ticket.state {
      | Work(_) => ticket.workCyclesStarted == cycle
      | _ => false
    }
  }

  def workRetryEvidenceHas(ticketId: int, evidence: int): bool =
    match graph.tickets.get(ticketId).state {
      | Work(work) => work.input.retryEvidence.indices().exists(index =>
          work.input.retryEvidence[index] == evidence)
      | _ => false
    }

  def workUsesSource(ticketId: int, expected: int): bool =
    match graph.tickets.get(ticketId).state {
      | Work(work) => work.source == expected
      | _ => false
    }

  def escalatedWith(
    ticketId: int,
    matcher: Escalation => bool,
  ): bool =
    match graph.tickets.get(ticketId).state {
      | Escalated(escalation) => matcher(escalation)
      | _ => false
    }

  def ticketEvaluationGeneration(
    ticketId: int,
    generation: int,
  ): bool = match graph.tickets.get(ticketId).state {
    | Evaluation(evaluation) => match evaluation.state {
        | Running(progress) => progress.stage.generation == generation
        | _ => false
      }
    | _ => false
  }

  def workInvalidatedWith(ticketId: int, evidence: int): bool =
    match graph.tickets.get(ticketId).state {
      | Work(work) => work.input.cause == EvaluationInvalidated(evidence)
      | _ => false
    }

  def decidedCancels: List[TaskIdentity] = match lastDecision {
    | TicketDecided(success) => success.obligations.foldl([], (found, obligation) =>
        match obligation {
          | CancelTask(cancellation) => found.append(cancellation.task)
          | _ => found
        })
    | TicketRefused(_) => []
  }

  def decidedEvent: TicketEvent = match lastDecision {
    | TicketDecided(success) => success.event
    | TicketRefused(_) => TicketRevoked(0)
  }

  def workReworkRefs(ticketId: int): List[EvaluationReworkEntry] =
    match graph.tickets.get(ticketId).state {
      | Work(work) => match work.input.cause {
          | EvaluationRework(entries) => entries
          | _ => []
        }
      | _ => []
    }

  run opaqueResultContractTest = {
    val obligation = {
      task: workTaskIdentity(1, 1),
      definition: WORK,
      contextRef: 1,
    }
    init.then(check(
      taskObligationValid(obligation)
      and terminalValid(TaskResultProduced(validatedTaskResult(obligation, 101)))
      and not(terminalValid(TaskResultProduced(validatedTaskResult(obligation, 0))))
    ))
  }

  run exactWorkObligationTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(check(decide(graph, ReportTaskTerminal(WorkResultReport({
        ticket: 1,
        result: validatedTaskResult({
          task: workTaskIdentity(1, 1),
          definition: WORK,
          contextRef: 2,
        }, 101),
        acceptedSourceRef: 102,
      })), reworkPolicy) == TicketRefused(TaskNotCurrent({
        ticket: 1,
        task: workTaskIdentity(1, 1),
      }))))
  }

  run stageKeyContractTest = {
    val zeroStageKeyPlan = {
      stages: [{ key: 0, evaluators: [{ key: 11, task: EVALUATOR }] }],
    }
    init.then(check(
      not(taskIdentityValid(evaluatorTaskIdentity(1, 1, 1, 0, 1, 11)))
      and not(planValid(zeroStageKeyPlan))
      and planValid(PLAN)
    ))
  }

  run happyPathTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(CreateTicket(released(2, Set(1)))))
      .then(submit(dispatch(2)))
      .then(check(graph.tickets.get(2).state == Pending))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 101))
      .then(reportEvaluatorResult(1, 111, EvaluatorPass))
      .then(reportEvaluatorResult(1, 112, EvaluatorPass))
      .then(reportEvaluatorResult(1, 121, EvaluatorPass))
      .then(reportFinalization(1, FinalizationSucceeded(131)))
      .then(check(ticketDone(1) and isReady(graph, 2)))
  }

  def decidedExecutionRequirements: List[int] = match lastDecision {
    | TicketDecided(success) => success.obligations.foldl([], (found, obligation) =>
        match obligation {
          | ExecuteTask(execution) => found.append(
              execution.task.definition.executionRequirements)
          | _ => found
        })
    | TicketRefused(_) => []
  }

  run executionRequirementsPreservedTest = {
    val work = { ...WORK, executionRequirements: 31 }
    val evaluator = { ...EVALUATOR, executionRequirements: 32 }
    val definition = {
      ...released(1, Set()),
      workConfiguration: work,
      evaluationPlan: {
        stages: [{
          key: 10,
          evaluators: [{ key: 11, task: evaluator }, { key: 12, task: evaluator }],
        }],
      },
    }
    val invalid = { ...work, executionRequirements: 0 }
    init
      .then(check(taskDefinitionValid(WORK) and not(taskDefinitionValid(invalid))))
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(updateTo(1, 1, definition)))
      .then(submit(dispatch(1)))
      .then(check(decidedExecutionRequirements == [31]))
      .then(submit(updateTo(1, 2, released(1, Set()))))
      .then(check(lastDecision == TicketRefused(TicketNotPending(1))
        and ticketDefinition(1, definition)))
      .then(reportWorkProcessFailed(1, 901))
      .then(submit(ResumeTicket(1)))
      .then(check(decidedExecutionRequirements == [31]))
      .then(reportWorkResult(1, 902))
      .then(check(decidedExecutionRequirements == [32, 32]))
      .then(reportEvaluatorResult(1, 903, EvaluatorFail))
      .then(reportEvaluatorResult(1, 904, EvaluatorPass))
      .then(check(decidedExecutionRequirements == [31]))
      .then(reportWorkResult(1, 905))
      .then(check(decidedExecutionRequirements == [32, 32]))
      .then(reportEvaluatorResult(1, 906, EvaluatorPass))
      .then(reportEvaluatorUnavailable(1, 907))
      .then(submit(ResumeTicket(1)))
      .then(check(decidedExecutionRequirements == [32]
        and ticketDefinition(1, definition)))
  }

  run definitionRevisionsTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(check(ticketRevision(1, 1) and ticketDefinition(1, released(1, Set()))))
      .then(submit(updateTo(1, 1, revised(1, Set()))))
      .then(check(ticketRevision(1, 2) and ticketDefinition(1, revised(1, Set()))))
      .then(submit(updateTo(1, 2, revised(1, Set()))))
      .then(check(ticketRevision(1, 3) and ticketDefinition(1, revised(1, Set()))))
      .then(check(graph.tickets.get(1).state == Pending
        and graph.tickets.get(1).workCyclesStarted == 0))
  }

  run updateRefusalLadderTest = {
    init
      .then(submit(updateTo(1, 1, released(1, Set()))))
      .then(check(lastDecision == TicketRefused(TicketNotFound(1))))
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(CreateTicket(released(2, Set(1)))))
      .then(submit(updateTo(2, 9, released(1, Set()))))
      .then(check(lastDecision == TicketRefused(TicketIdentityMismatch(2))))
      .then(submit(updateTo(2, 9, revised(2, Set()))))
      .then(check(lastDecision == TicketRefused(TicketRevisionStale({
        ticket: 2,
        expected: 9,
        current: 1,
      }))))
      .then(submit(updateTo(2, 1, revised(2, Set(1, 2)))))
      .then(check(lastDecision == TicketRefused(SelfDependency(2))))
      .then(check(ticketRevision(2, 1) and ticketDefinition(2, released(2, Set(1)))))
      .then(submit(dispatch(1)))
      .then(submit(updateTo(1, 1, revised(1, Set()))))
      .then(check(lastDecision == TicketRefused(TicketNotPending(1))))
      .then(check(ticketDefinition(1, released(1, Set()))))
  }

  run dependencyChangeTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(CreateTicket(released(2, Set(1)))))
      .then(submit(CreateTicket(released(3, Set()))))
      .then(submit(updateTo(2, 1, revised(2, Set(3)))))
      .then(check(ticketRevision(2, 2) and ticketDefinition(2, revised(2, Set(3)))))
      .then(submit(updateTo(3, 1, revised(3, Set(2)))))
      .then(check(lastDecision == TicketRefused(DependencyCycle({
        ticket: 3,
        dependencies: Set(2),
      }))))
      .then(submit(CreateTicket(released(4, Set(2)))))
      .then(submit(updateTo(2, 2, released(2, Set(3, 4)))))
      .then(check(lastDecision == TicketRefused(DependencyCycle({
        ticket: 2,
        dependencies: Set(4),
      }))))
      .then(submit(updateTo(2, 2, released(2, Set(3, 9)))))
      .then(check(lastDecision == TicketRefused(DependenciesNotFound({
        ticket: 2,
        dependencies: Set(9),
      }))))
      .then(check(ticketRevision(2, 2) and ticketDefinition(2, revised(2, Set(3)))))
      .then(submit(CreateTicket(released(5, Set()))))
      .then(submit(updateTo(3, 1, revised(3, Set(5)))))
      .then(check(ticketRevision(3, 2) and ticketDefinition(3, revised(3, Set(5)))))
  }

  run revokedDependencyTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(CreateTicket(released(2, Set(1)))))
      .then(submit(CreateTicket(released(3, Set()))))
      .then(submit(RevokeTicket(1)))
      .then(submit(CreateTicket(released(4, Set(1)))))
      .then(check(lastDecision == TicketRefused(DependenciesRevoked({
        ticket: 4,
        dependencies: Set(1),
      }))))
      .then(submit(updateTo(3, 1, revised(3, Set(1)))))
      .then(check(lastDecision == TicketRefused(DependenciesRevoked({
        ticket: 3,
        dependencies: Set(1),
      }))))
      .then(submit(updateTo(2, 1, revised(2, Set(1)))))
      .then(check(ticketRevision(2, 2) and ticketDefinition(2, revised(2, Set(1)))))
      .then(check(not(isReady(graph, 2))))
      .then(submit(updateTo(2, 2, released(2, Set()))))
      .then(check(ticketRevision(2, 3) and isReady(graph, 2)))
      .then(submit(dispatch(2)))
      .then(check(ticketWorkCycle(2, 1)))
  }

  run dispatchUsesTheRevisedDefinitionTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(updateTo(1, 1, revised(1, Set()))))
      .then(submit(dispatch(1)))
      .then(check(decidedWorkContexts == [1]))
      .then(check(ticketWorkCycle(1, 1) and ticketDefinition(1, revised(1, Set()))))
  }

  run failedEvaluatorResultRefReachesReworkTest = {
    init
      .then(check(failedEntries(11, Produced(EvaluatorFailed(102))) == [
        { evaluator: 11, resultRef: 102 },
      ]))
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResultWithSource(1, 1301, 1401))
      .then(reportEvaluatorResult(1, 1311, EvaluatorFail))
      .then(reportEvaluatorResult(1, 1315, EvaluatorPass))
      .then(check(ticketWorkCycle(1, 2)
        and workReworkRefs(1) == [{ evaluator: 11, resultRef: 1311 }]
        and workUsesSource(1, 1401)))
  }

  run evaluationFailurePolicyTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 201))
      .then(reportEvaluatorResult(1, 211, EvaluatorFail))
      .then(reportEvaluatorResult(1, 212, EvaluatorPass))
      .then(check(ticketWorkCycle(1, 2)))
      .then(reportWorkResult(1, 202))
      .then(reportEvaluatorResult(1, 221, EvaluatorFail))
      .then(reportEvaluatorResultWithFailureDisposition(
        1,
        222,
        EvaluatorPass,
        escalatePolicy,
      ))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(submit(ResumeTicket(1)))
      .then(check(ticketWorkCycle(1, 3)))
  }

  run evaluationUnavailableResumeTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 301))
      .then(reportEvaluatorResult(1, 311, EvaluatorPass))
      .then(reportEvaluatorUnavailable(1, 312))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(submit(ResumeTicket(1)))
      .then(check(ticketEvaluationGeneration(1, 2)))
      .then(reportEvaluatorResult(1, 313, EvaluatorPass))
      .then(reportEvaluatorResult(1, 321, EvaluatorPass))
      .then(reportFinalization(1, FinalizationSucceeded(331)))
      .then(check(ticketDone(1)))
  }

  run evaluationFailurePrecedesUnavailabilityTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 601))
      .then(reportEvaluatorResult(1, 611, EvaluatorFail))
      .then(reportEvaluatorUnavailable(1, 612))
      .then(check(ticketWorkCycle(1, 2)))
  }

  run evaluationProcessFailureRecoveryTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 701))
      .then(reportEvaluatorResult(1, 711, EvaluatorPass))
      .then(reportEvaluatorProcessFailed(1, 712))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(submit(ResumeTicket(1)))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => match evaluation.state {
            | Running(progress) => progress.stage.generation == 2
                and progress.stage.evaluators.keys().filter(evaluator => match
                  progress.stage.evaluators.get(evaluator) {
                    | Produced(result) => match result {
                        | EvaluatorPassed(_) => true
                        | _ => false
                      }
                    | _ => false
                  }).size() == 1
                and progress.stage.evaluators.keys().filter(evaluator =>
                  statusAwaiting(
                    progress.stage.evaluators.get(evaluator))).size() == 1
            | _ => false
          }
        | _ => false
      }))
      .then(check(decide(graph, ReportTaskTerminal(EvaluationResultReport({
        ticket: 1,
        result: validatedTaskResult({
          task: evaluatorTaskIdentity(1, 1, 1, 10, 1, 12),
          definition: EVALUATOR,
          contextRef: 701,
        }, 713),
        verdict: EvaluatorPass,
      })), reworkPolicy) == TicketRefused(TaskNotCurrent({
        ticket: 1,
        task: evaluatorTaskIdentity(1, 1, 1, 10, 1, 12),
      }))))
      .then(reportEvaluatorResult(1, 714, EvaluatorPass))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => match evaluation.state {
            | Running(progress) => progress.stage.stageIndex == 1
                and progress.stage.generation == 1
                and progress.stage.evaluators.keys().filter(evaluator =>
                  statusAwaiting(
                    progress.stage.evaluators.get(evaluator))).size() == 1
            | _ => false
          }
        | _ => false
      }))
  }

  run duplicateEvaluatorTerminalIsRefusedTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 801))
      .then(reportEvaluatorResult(1, 811, EvaluatorPass))
      .then(check(decide(graph, ReportTaskTerminal(EvaluationResultReport({
        ticket: 1,
        result: validatedTaskResult({
          task: evaluatorTaskIdentity(1, 1, 1, 10, 1, 11),
          definition: EVALUATOR,
          contextRef: 801,
        }, 811),
        verdict: EvaluatorPass,
      })), reworkPolicy) == TicketRefused(TaskNotCurrent({
        ticket: 1,
        task: evaluatorTaskIdentity(1, 1, 1, 10, 1, 11),
      }))))
  }

  run revocationCancelsOutstandingEvaluationTasksTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 901))
      .then(reportEvaluatorResult(1, 911, EvaluatorPass))
      .then(check(decide(
        graph,
        RevokeTicket(1),
        reworkPolicy,
      ) == TicketDecided({
        event: TicketRevoked(1),
        obligations: [CancelTask({
          ticket: 1,
          task: evaluatorTaskIdentity(1, 1, 1, 10, 1, 12),
        })],
      })))
      .then(submit(RevokeTicket(1)))
      .then(check(graph.tickets.get(1).state == Revoked))
  }

  run finalizationRecoveryTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 401))
      .then(reportEvaluatorResult(1, 411, EvaluatorPass))
      .then(reportEvaluatorResult(1, 412, EvaluatorPass))
      .then(reportEvaluatorResult(1, 421, EvaluatorPass))
      .then(reportFinalization(1, FinalizationNeedsWork(431)))
      .then(check(ticketWorkCycle(1, 2)))
      .then(reportWorkResult(1, 402))
      .then(reportEvaluatorResult(1, 441, EvaluatorPass))
      .then(reportEvaluatorResult(1, 442, EvaluatorPass))
      .then(reportEvaluatorResult(1, 451, EvaluatorPass))
      .then(reportFinalization(1, FinalizationResultUnavailable(461)))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(submit(ResumeTicket(1)))
      .then(reportFinalization(1, FinalizationSucceeded(462)))
      .then(check(ticketDone(1)))
  }

  run revocationLeavesDependentsBlockedTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(CreateTicket(released(2, Set(1)))))
      .then(submit(CreateTicket(released(3, Set(2)))))
      .then(submit(CreateTicket(released(4, Set()))))
      .then(submit(dispatch(1)))
      .then(submit(RevokeTicket(1)))
      .then(check(
        graph.tickets.get(1).state == Revoked
        and graph.tickets.get(2).state == Pending
        and graph.tickets.get(3).state == Pending
        and graph.tickets.get(4).state == Pending
        and not(isReady(graph, 2))
        and not(isReady(graph, 3))
      ))
      .then(submit(RevokeTicket(2)))
      .then(check(
        graph.tickets.get(2).state == Revoked
        and graph.tickets.get(3).state == Pending
        and not(isReady(graph, 3))
      ))
      .then(submit(RevokeTicket(3)))
      .then(check(graph.tickets.get(3).state == Revoked))
  }

  run workFailureEscalationTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(check(workUsesSource(1, source(1, 1001))))
      .then(reportWorkProcessFailed(1, 901))
      .then(check(escalatedWith(1, (escalation) => match escalation {
        | WorkFailureEscalated(_) => true
        | _ => false
      })))
      .then(submit(ResumeTicket(1)))
      .then(check(ticketWorkCycle(1, 2)
        and workRetryEvidenceHas(1, 901)
        and workUsesSource(1, source(1, 1001))))
      .then(reportWorkExecutionUnavailable(1, 902))
      .then(check(escalatedWith(1, (escalation) => match escalation {
        | WorkExecutionUnavailableEscalated(_) => true
        | _ => false
      })))
      .then(submit(ResumeTicket(1)))
      .then(check(
        ticketWorkCycle(1, 3)
        and workRetryEvidenceHas(1, 901)
        and workRetryEvidenceHas(1, 902)
      ))
      .then(reportWorkResult(1, 903))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(_) => true
        | _ => false
      }))
  }

  run staleFinalizationIsRefusedTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResultWithSource(1, 1001, 1099))
      .then(reportEvaluatorResult(1, 1011, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1012, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1021, EvaluatorPass))
      .then(reportFinalization(1, FinalizationResultUnavailable(1031)))
      .then(check(graph.tickets.get(1).workCyclesStarted == 1
        and match lastDecision {
          | TicketDecided(success) => success.obligations == []
          | _ => false
        }))
      .then(submit(ResumeTicket(1)))
      .then(check(graph.tickets.get(1).workCyclesStarted == 1
        and match lastDecision {
          | TicketDecided(success) => success.obligations.length() == 1
            and (match success.obligations.nth(0) {
              | FinalizeTicket(request) => request.finalization.input == 1001
                and request.finalization.source == 1099
              | _ => false
            })
          | _ => false
        }))
      .then(check(match graph.tickets.get(1).state {
        | Finalization(operation) =>
            operation.workCycle == 1 and operation.generation == 2
        | _ => false
      }))
      .then(submit(ReportFinalizationResult({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        result: FinalizationSucceeded(1041),
      })))
      .then(check(lastDecision == TicketRefused(FinalizationNotCurrent({
        ticket: 1,
        workCycle: 1,
        generation: 1,
      }))))
      .then(check(evolve(graph, TicketFinalizationSucceeded({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        evidence: 1041,
      })) == graph))
      .then(check(evolve(graph, TicketFinalizationNeedsWork({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        evidence: 1041,
      })) == graph))
      .then(check(evolve(graph, TicketFinalizationUnavailable({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        evidence: 1041,
      })) == graph))
      .then(reportFinalization(1, FinalizationSucceeded(1042)))
      .then(check(ticketDone(1)))
  }

  run finalizationResultContractTest = {
    val absentEvidence = ReportFinalizationResult({
      ticket: 1,
      workCycle: 1,
      generation: 1,
      result: FinalizationNeedsWork(0),
    })
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 1201))
      .then(reportEvaluatorResult(1, 1211, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1212, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1221, EvaluatorPass))
      .then(check(ticketFinalizing(1)))
      .then(check(not(commandValid(absentEvidence))))
      .then(check(
        not(graphInvariant(applyCommand(graph, absentEvidence, reworkPolicy)))
      ))
  }

  run evolveRejectsMispairedEvaluationTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 1301))
      .then(reportEvaluatorResult(1, 1311, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1312, EvaluatorPass))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => match evaluation.state {
            | Running(progress) => progress.stage.stageIndex == 1
            | _ => false
          }
        | _ => false
      }))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => {
            // The last evaluator of the last stage concludes evaluation, so
            // only Passed may carry this report. Every other pairing would
            // leave a concluded evaluation resting in the Evaluation phase.
            val report =
              currentEvaluatorReport(1, evaluation, 1321, EvaluatorPass)
            and {
              evolve(graph, TicketEvaluationProgressed({
                ticket: 1,
                report: report,
              })) == graph,
              evolve(graph, TicketEvaluationBlocked({
                ticket: 1,
                report: report,
              })) == graph,
              evolve(graph, TicketEvaluationReworkStarted({
                ticket: 1,
                report: report,
                evidence: [{ evaluator: 21, resultRef: 1321 }],
              })) == graph,
              evolve(graph, TicketEvaluationFailureEscalated({
                ticket: 1,
                report: report,
                evidence: [{ evaluator: 21, resultRef: 1321 }],
              })) == graph,
              graphFinalizing(evolve(graph, TicketEvaluationPassed({
                ticket: 1,
                report: report,
              })), 1),
            }
          }
        | _ => false
      }))
      .then(reportEvaluatorResult(1, 1321, EvaluatorPass))
      .then(check(ticketFinalizing(1)))
  }

  run evolveIgnoresImpossiblePairingTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(CreateTicket(released(2, Set()))))
      .then(submit(CreateTicket(released(3, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 1101))
      .then(reportEvaluatorResult(1, 1111, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1112, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1121, EvaluatorPass))
      .then(reportFinalization(1, FinalizationSucceeded(1131)))
      .then(submit(RevokeTicket(2)))
      .then(check(ticketDone(1) and graph.tickets.get(2).state == Revoked))
      .then(check(evolve(graph, TicketDispatched({ ticket: 1, source: source(1, 1001) })) == graph))
      .then(check(evolve(graph, TicketDispatched({ ticket: 2, source: source(2, 2001) })) == graph))
      .then(check(evolve(graph, TicketRevoked(1)) == graph))
      .then(check(evolve(graph, TicketCreated(released(1, Set()))) == graph))
      .then(check(evolve(graph, TicketFinalizationSucceeded({
        ticket: 2,
        workCycle: 1,
        generation: 1,
        evidence: 1141,
      })) == graph))
      .then(check(evolve(graph, TicketUpdated({
        ticket: 4,
        revision: 2,
        definition: revised(4, Set()),
      })) == graph))
      .then(check(evolve(graph, TicketUpdated({
        ticket: 1,
        revision: 2,
        definition: revised(1, Set()),
      })) == graph))
      .then(check(evolve(graph, TicketUpdated({
        ticket: 3,
        revision: 3,
        definition: revised(3, Set()),
      })) == graph))
  }

  def decisionInvariant = decisionValid(priorGraph, lastDecision)

  run invalidationMidStageCancelsAndRestartsInWorkTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResultWithSource(1, 1401, 1499))
      .then(reportEvaluatorResult(1, 1411, EvaluatorPass))
      .then(invalidateEvaluation(1, 1421))
      .then(check(decidedEvent == TicketEvaluationInvalidated({
        ticket: 1,
        workCycle: 1,
        evidence: 1421,
      })))
      .then(check(decidedCancels == [evaluatorTaskIdentity(1, 1, 1, 10, 1, 12)]))
      .then(check(decidedWorkContexts == [2]))
      .then(check(ticketWorkCycle(1, 2)))
      .then(check(workInvalidatedWith(1, 1421)))
      .then(check(workUsesSource(1, 1499)))
      .then(check(workReworkRefs(1) == []))
      .then(check(decisionInvariant))
  }

  run invalidationBeforeAnyEvaluatorReportsCancelsEveryEvaluatorTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 1451))
      .then(invalidateEvaluation(1, 1461))
      .then(check(decidedCancels == [
        evaluatorTaskIdentity(1, 1, 1, 10, 1, 11),
        evaluatorTaskIdentity(1, 1, 1, 10, 1, 12),
      ]))
      .then(check(decisionInvariant))
  }

  run staleVerdictAfterInvalidationIsRefusedTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 1501))
      .then(reportEvaluatorResult(1, 1511, EvaluatorPass))
      .then(invalidateEvaluation(1, 1521))
      .then(submit(ReportTaskTerminal(EvaluationResultReport({
        ticket: 1,
        result: validatedTaskResult({
          task: evaluatorTaskIdentity(1, 1, 1, 10, 1, 12),
          definition: EVALUATOR,
          contextRef: 1501,
        }, 1531),
        verdict: EvaluatorFail,
      }))))
      .then(check(lastDecision == TicketRefused(TaskNotCurrent({
        ticket: 1,
        task: evaluatorTaskIdentity(1, 1, 1, 10, 1, 12),
      }))))
  }

  run invalidationIsRefusedOutsideACurrentEvaluationTest = {
    init
      .then(submit(InvalidateEvaluation({ ticket: 9, workCycle: 1, round: 1, evidence: 1 })))
      .then(check(lastDecision == TicketRefused(TicketNotFound(9))))
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(InvalidateEvaluation({ ticket: 1, workCycle: 1, round: 1, evidence: 1 })))
      .then(check(lastDecision == TicketRefused(EvaluationNotCurrent({ ticket: 1, workCycle: 1, round: 1 }))))
      .then(submit(dispatch(1)))
      .then(submit(InvalidateEvaluation({ ticket: 1, workCycle: 1, round: 1, evidence: 1 })))
      .then(check(lastDecision == TicketRefused(EvaluationNotCurrent({ ticket: 1, workCycle: 1, round: 1 }))))
      .then(reportWorkResult(1, 1601))
      .then(submit(InvalidateEvaluation({ ticket: 1, workCycle: 2, round: 1, evidence: 1 })))
      .then(check(lastDecision == TicketRefused(EvaluationNotCurrent({ ticket: 1, workCycle: 2, round: 1 }))))
      .then(submit(InvalidateEvaluation({ ticket: 1, workCycle: 1, round: 1, evidence: 1611 })))
      .then(submit(InvalidateEvaluation({ ticket: 1, workCycle: 1, round: 1, evidence: 1611 })))
      .then(check(lastDecision == TicketRefused(EvaluationNotCurrent({ ticket: 1, workCycle: 1, round: 1 }))))
      .then(reportWorkResult(1, 1602))
      .then(reportEvaluatorResult(1, 1621, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1622, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1623, EvaluatorPass))
      .then(check(ticketFinalizing(1)))
      .then(submit(InvalidateEvaluation({ ticket: 1, workCycle: 2, round: 1, evidence: 1 })))
      .then(check(lastDecision == TicketRefused(EvaluationNotCurrent({ ticket: 1, workCycle: 2, round: 1 }))))
      .then(reportFinalization(1, FinalizationSucceeded(1631)))
      .then(submit(InvalidateEvaluation({ ticket: 1, workCycle: 2, round: 1, evidence: 1 })))
      .then(check(lastDecision == TicketRefused(EvaluationNotCurrent({ ticket: 1, workCycle: 2, round: 1 }))))
  }

  run invalidationIgnoresTheFailurePolicyTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 1701))
      .then(check(decide(
        graph,
        InvalidateEvaluation({ ticket: 1, workCycle: 1, round: 1, evidence: 1711 }),
        escalatePolicy,
      ) == decide(
        graph,
        InvalidateEvaluation({ ticket: 1, workCycle: 1, round: 1, evidence: 1711 }),
        reworkPolicy,
      )))
      .then(check(decide(
        graph,
        InvalidateEvaluation({ ticket: 1, workCycle: 1, round: 1, evidence: 1711 }),
        invalidatePolicy,
      ) == decide(
        graph,
        InvalidateEvaluation({ ticket: 1, workCycle: 1, round: 1, evidence: 1711 }),
        reworkPolicy,
      )))
  }

  run invalidationRunsEvaluationAgainOnFreshTaskIdentitiesTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 1801))
      .then(invalidateEvaluation(1, 1811))
      .then(reportWorkResult(1, 1802))
      .then(check(ticketEvaluationGeneration(1, 1)))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) =>
            evaluation.workCycle == 2
            and taskCurrent(evaluation, evaluatorTaskIdentity(1, 2, 1, 10, 1, 11))
            and not(taskCurrent(
              evaluation,
              evaluatorTaskIdentity(1, 1, 1, 10, 1, 11),
            ))
        | _ => false
      }))
      .then(reportEvaluatorResult(1, 1821, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1822, EvaluatorPass))
      .then(reportEvaluatorResult(1, 1823, EvaluatorPass))
      .then(check(ticketFinalizing(1)))
      .then(reportFinalization(1, FinalizationSucceeded(1831)))
      .then(check(graph.tickets.get(1).state == Done))
  }

  run failedVerdictInvalidatedByPolicyKeepsTheVerdictAndSkipsReworkTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResultWithSource(1, 1901, 1999))
      .then(reportEvaluatorResult(1, 1911, EvaluatorFail))
      .then(reportEvaluatorResultWithFailureDisposition(
        1,
        1912,
        EvaluatorPass,
        invalidatePolicy,
      ))
      .then(check(match decidedEvent {
        | TicketEvaluationFailureInvalidated(fact) =>
            fact.ticket == 1 and fact.evidence == 1601
        | _ => false
      }))
      .then(check(decidedCancels == []))
      .then(check(decidedWorkContexts == [2]))
      .then(check(ticketWorkCycle(1, 2)))
      .then(check(workInvalidatedWith(1, 1601)))
      .then(check(workUsesSource(1, 1999)))
      .then(check(workReworkRefs(1) == []))
      .then(check(not(isEscalated(graph.tickets.get(1).state))))
      .then(check(decisionInvariant))
  }

  run dropOfALiveTaskWithoutCancellationIsNotAValidDecisionTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 2001))
      .then(check({
        val evolved = evolve(graph, TicketEvaluationInvalidated({
          ticket: 1,
          workCycle: 1,
          evidence: 2011,
        }))
        val ticket = graph.tickets.get(1)
        val restart = executeWork(
          ticket,
          nextCycleNumber(ticket),
          2001,
          invalidatedWorkInput(ticket.definition, 2011),
        )
        and {
          not(decisionValid(graph, TicketDecided({
            event: TicketEvaluationInvalidated({
              ticket: 1,
              workCycle: 1,
              evidence: 2011,
            }),
            obligations: [restart],
          }))),
          decisionValid(graph, decide(
            graph,
            InvalidateEvaluation({ ticket: 1, workCycle: 1, round: 1, evidence: 2011 }),
            reworkPolicy,
          )),
          evolved != graph,
        }
      }))
  }

  run invalidationEvidenceMustBePositiveTest = {
    init.then(check(
      not(commandValid(InvalidateEvaluation({
        ticket: 1,
        workCycle: 1,
        round: 1,
        evidence: 0,
      })))
      and commandValid(InvalidateEvaluation({
        ticket: 1,
        workCycle: 1,
        round: 1,
        evidence: 1,
      }))
    ))
  }

  pure def invalidatedAt(workCycle: int): TicketEvent =
    TicketEvaluationInvalidated({
      ticket: 1,
      workCycle: workCycle,
      evidence: 2411,
    })

  run invalidationEvolveIgnoresStaleOrMisplacedEventsTest = {
    val stale = invalidatedAt(1)
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(check(evolve(graph, stale) == graph))
      .then(submit(dispatch(1)))
      .then(check(evolve(graph, stale) == graph))
      .then(reportWorkResult(1, 2401))
      .then(check(evolve(graph, invalidatedAt(2)) == graph))
      .then(check(evolve(graph, invalidatedAt(1)) != graph))
      .then(invalidateEvaluation(1, 2412))
      .then(reportWorkResult(1, 2402))
      .then(check(evolve(graph, stale) == graph))
      .then(check(evolve(graph, invalidatedAt(2)) != graph))
      .then(reportEvaluatorResult(1, 2421, EvaluatorPass))
      .then(reportEvaluatorResult(1, 2422, EvaluatorPass))
      .then(reportEvaluatorResult(1, 2423, EvaluatorPass))
      .then(check(ticketFinalizing(1)))
      .then(check(evolve(graph, invalidatedAt(2)) == graph))
      .then(reportFinalization(1, FinalizationSucceeded(2431)))
      .then(check(evolve(graph, invalidatedAt(2)) == graph))
  }

  run invalidationFromBlockedEvaluationEscalationTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResultWithSource(1, 2501, 2599))
      .then(reportEvaluatorResult(1, 2511, EvaluatorPass))
      .then(reportEvaluatorUnavailable(1, 2512))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(submit(InvalidateEvaluation({
        ticket: 1,
        workCycle: 2,
        round: 1,
        evidence: 2521,
      })))
      .then(check(lastDecision == TicketRefused(EvaluationNotCurrent({
        ticket: 1,
        workCycle: 2,
      round: 1,
      }))))
      .then(check(evolve(graph, TicketEvaluationInvalidated({
        ticket: 1,
        workCycle: 2,
        evidence: 2521,
      })) == graph))
      .then(submit(InvalidateEvaluation({
        ticket: 1,
        workCycle: 1,
        round: 1,
        evidence: 2521,
      })))
      .then(check(decidedCancels == []))
      .then(check(ticketWorkCycle(1, 2)))
      .then(check(workInvalidatedWith(1, 2521)))
      .then(check(workUsesSource(1, 2599)))
      .then(check(decisionInvariant))
  }

  run invalidationIsRefusedFromAFailureEscalationTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 2601))
      .then(reportEvaluatorResult(1, 2611, EvaluatorFail))
      .then(reportEvaluatorResultWithFailureDisposition(
        1,
        2612,
        EvaluatorPass,
        escalatePolicy,
      ))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(submit(InvalidateEvaluation({
        ticket: 1,
        workCycle: 1,
        round: 1,
        evidence: 2621,
      })))
      .then(check(lastDecision == TicketRefused(EvaluationNotCurrent({
        ticket: 1,
        workCycle: 1,
      round: 1,
      }))))
  }

  run invalidatedWorkFailureResumesWithTheInvalidationCauseTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 2701))
      .then(invalidateEvaluation(1, 2711))
      .then(reportWorkProcessFailed(1, 2721))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(submit(ResumeTicket(1)))
      .then(check(ticketWorkCycle(1, 3)))
      .then(check(workInvalidatedWith(1, 2711)))
      .then(check(workRetryEvidenceHas(1, 2721)))
      .then(check(decisionInvariant))
  }

  run policyEvidenceMustBePositiveToInvalidateTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 2801))
      .then(reportEvaluatorResult(1, 2811, EvaluatorFail))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => and {
            not(decisionValid(graph, decide(
              graph,
              ReportTaskTerminal(
                currentEvaluatorReport(1, evaluation, 2812, EvaluatorPass)),
              invalidateZeroPolicy,
            ))),
            decisionValid(graph, decide(
              graph,
              ReportTaskTerminal(
                currentEvaluatorReport(1, evaluation, 2812, EvaluatorPass)),
              invalidatePolicy,
            )),
          }
        | _ => false
      }))
  }

  // === Requested evaluations ================================================

  action reportFinalizationWithPolicy(ticketId, result, failurePolicy) = {
    if (not(graph.tickets.keys().contains(ticketId))) blocked
    else {
      val ticket = graph.tickets.get(ticketId)
      match ticket.state {
        | Finalization(finalization) =>
            submitWithPolicy(ReportFinalizationResult({
              ticket: ticketId,
              workCycle: finalization.workCycle,
              generation: finalization.generation,
              result: result,
            }), failurePolicy)
        | _ => blocked
      }
    }
  }

  action requestEvaluation(ticketId, evidence) =
    reportFinalization(ticketId, FinalizationNeedsEvaluation(evidence))

  def finalizing(
    ticketId: int,
    matcher: FinalizationOperation => bool,
  ): bool = match graph.tickets.get(ticketId).state {
    | Finalization(operation) => matcher(operation)
    | _ => false
  }

  def evaluating(
    ticketId: int,
    matcher: EvaluationInstance => bool,
  ): bool = match graph.tickets.get(ticketId).state {
    | Evaluation(evaluation) => matcher(evaluation)
    | _ => false
  }

  def decidedTasks: List[TaskIdentity] = match lastDecision {
    | TicketDecided(success) => success.obligations.foldl([], (found, obligation) =>
        match obligation {
          | ExecuteTask(execution) => found.append(execution.task.task)
          | _ => found
        })
    | TicketRefused(_) => []
  }

  def decidedFinalizations: List[FinalizationOperation] = match lastDecision {
    | TicketDecided(success) => success.obligations.foldl([], (found, obligation) =>
        match obligation {
          | FinalizeTicket(request) => found.append(request.finalization)
          | _ => found
        })
    | TicketRefused(_) => []
  }

  pure def basisFailed(operation: FinalizationOperation): bool =
    match operation.basis {
      | FailedVerdict(_) => true
      | _ => false
    }

  // A ticket whose first evaluation has passed and is with its finalizer.
  action passedOnce(resultRef) =
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResultWithSource(1, resultRef, resultRef + 90))
      .then(reportEvaluatorResult(1, resultRef + 1, EvaluatorPass))
      .then(reportEvaluatorResult(1, resultRef + 2, EvaluatorPass))
      .then(reportEvaluatorResult(1, resultRef + 3, EvaluatorPass))

  // ... and whose requested second evaluation has failed.
  action failedTwice(resultRef) =
    passedOnce(resultRef)
      .then(requestEvaluation(1, resultRef + 10))
      .then(reportEvaluatorResult(1, resultRef + 11, EvaluatorFail))
      .then(reportEvaluatorResult(1, resultRef + 12, EvaluatorPass))

  run requestedEvaluationRunsTheSameResultAgainAndCompletesTest = {
    passedOnce(3000)
      .then(check(finalizing(1, operation =>
        operation.round == 1 and operation.generation == 1
        and operation.origin == OpenedByWork
        and operation.basis == PassedVerdict)))
      .then(requestEvaluation(1, 3010))
      .then(check(decisionInvariant))
      .then(check(decidedEvent == TicketFinalizationNeedsEvaluation({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        evidence: 3010,
      })))
      .then(check(decidedTasks == [
        evaluatorTaskIdentity(1, 1, 2, 10, 1, 11),
        evaluatorTaskIdentity(1, 1, 2, 10, 1, 12),
      ]))
      .then(check(decidedWorkContexts == [3000, 3000]))
      .then(check(graph.tickets.get(1).workCyclesStarted == 1))
      .then(check(evaluating(1, evaluation =>
        evaluation.round == 2
        and evaluation.origin == Requested({ generation: 1, evidence: 3010 })
        and evaluation.input.workResult == 3000
        and evaluation.input.acceptedSourceRef == 3090)))
      .then(reportEvaluatorResult(1, 3011, EvaluatorPass))
      .then(reportEvaluatorResult(1, 3012, EvaluatorPass))
      .then(reportEvaluatorResult(1, 3013, EvaluatorPass))
      .then(check(decisionInvariant))
      .then(check(decidedFinalizations == [{
        workCycle: 1,
        round: 2,
        generation: 2,
        input: 3000,
        source: 3090,
        origin: Requested({ generation: 1, evidence: 3010 }),
        basis: PassedVerdict,
      }]))
      .then(reportFinalization(1, FinalizationSucceeded(3020)))
      .then(check(ticketDone(1)))
  }

  run finalizationReportFromBeforeARequestedEvaluationIsRefusedTest = {
    val stale = ReportFinalizationResult({
      ticket: 1,
      workCycle: 1,
      generation: 1,
      result: FinalizationSucceeded(3120),
    })
    val refusal = TicketRefused(FinalizationNotCurrent({
      ticket: 1,
      workCycle: 1,
      generation: 1,
    }))
    passedOnce(3100)
      .then(requestEvaluation(1, 3110))
      .then(submit(stale))
      .then(check(lastDecision == refusal))
      .then(reportEvaluatorResult(1, 3111, EvaluatorPass))
      .then(reportEvaluatorResult(1, 3112, EvaluatorPass))
      .then(reportEvaluatorResult(1, 3113, EvaluatorPass))
      .then(check(finalizing(1, operation => operation.generation == 2)))
      .then(submit(stale))
      .then(check(lastDecision == refusal))
      .then(check(evolve(graph, TicketFinalizationSucceeded({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        evidence: 3120,
      })) == graph))
      .then(check(evolve(graph, TicketFinalizationNeedsEvaluation({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        evidence: 3120,
      })) == graph))
  }

  run evaluatorReportFromAnEarlierRoundIsRefusedTest = {
    val late = evaluatorTaskIdentity(1, 1, 1, 10, 1, 11)
    passedOnce(3200)
      .then(requestEvaluation(1, 3210))
      .then(check(late != evaluatorTaskIdentity(1, 1, 2, 10, 1, 11)))
      .then(submit(ReportTaskTerminal(EvaluationResultReport({
        ticket: 1,
        result: validatedTaskResult({
          task: late,
          definition: EVALUATOR,
          contextRef: 3200,
        }, 3211),
        verdict: EvaluatorFail,
      }))))
      .then(check(lastDecision == TicketRefused(TaskNotCurrent({
        ticket: 1,
        task: late,
      }))))
  }

  run requestedEvaluationFailureReturnsToFinalizationWithoutAPolicyTest = {
    failedTwice(3300)
      .then(check(decisionInvariant))
      .then(check(match decidedEvent {
        | TicketEvaluationFailureReturned(_) => true
        | _ => false
      }))
      .then(check(decidedTasks == []))
      .then(check(graph.tickets.get(1).workCyclesStarted == 1))
      .then(check(finalizing(1, operation =>
        operation.round == 2 and operation.generation == 2
        and operation.origin == Requested({ generation: 1, evidence: 3310 })
        and basisFailed(operation)
        and failedBasisEntries(operation.basis)
          == [{ evaluator: 11, resultRef: 3311 }])))
      .then(check(decidedFinalizations.length() == 1))
  }

  // The policy that would escalate is never asked when a requested
  // evaluation fails.
  run requestedEvaluationFailureIgnoresTheFailurePolicyTest = {
    passedOnce(3400)
      .then(requestEvaluation(1, 3410))
      .then(reportEvaluatorResult(1, 3411, EvaluatorFail))
      .then(reportEvaluatorResultWithFailureDisposition(
        1,
        3412,
        EvaluatorPass,
        escalatePolicy,
      ))
      .then(check(finalizing(1, basisFailed)))
  }

  run finalizationCannotSucceedOnAFailedVerdictTest = {
    failedTwice(3500)
      .then(reportFinalization(1, FinalizationSucceeded(3520)))
      .then(check(lastDecision == TicketRefused(FinalizationResultNotAllowed({
        ticket: 1,
        workCycle: 1,
        generation: 2,
      }))))
      .then(check(finalizing(1, basisFailed)))
      .then(check(evolve(graph, TicketFinalizationSucceeded({
        ticket: 1,
        workCycle: 1,
        generation: 2,
        evidence: 3520,
      })) == graph))
      .then(check(not(decisionValid(graph, TicketDecided({
        event: TicketFinalizationSucceeded({
          ticket: 1,
          workCycle: 1,
          generation: 2,
          evidence: 3520,
        }),
        obligations: [],
      })))))
  }

  run failedVerdictThatStandsReworksUnderThePolicyTest = {
    failedTwice(3600)
      .then(reportFinalization(1, FinalizationFailureStands(3620)))
      .then(check(decisionInvariant))
      .then(check(decidedEvent == TicketFinalizationFailureReworked({
        ticket: 1,
        workCycle: 1,
        generation: 2,
        evidence: 3620,
      })))
      .then(check(ticketWorkCycle(1, 2)))
      .then(check(workReworkRefs(1) == [{ evaluator: 11, resultRef: 3611 }]))
      .then(check(workUsesSource(1, 3690)))
      .then(reportWorkResult(1, 3630))
      .then(check(evaluating(1, evaluation =>
        evaluation.round == 1 and evaluation.origin == OpenedByWork)))
  }

  run failedVerdictThatStandsEscalatesUnderThePolicyTest = {
    failedTwice(3700)
      .then(reportFinalizationWithPolicy(
        1,
        FinalizationFailureStands(3720),
        escalatePolicy,
      ))
      .then(check(decisionInvariant))
      .then(check(decidedEvent == TicketFinalizationFailureEscalated({
        ticket: 1,
        workCycle: 1,
        generation: 2,
        evidence: 3720,
      })))
      .then(check(escalatedWith(1, escalation => escalation ==
        EvaluationFailureEscalated({
          evidence: [{ evaluator: 11, resultRef: 3711 }],
          source: 3790,
        }))))
      .then(submit(ResumeTicket(1)))
      .then(check(ticketWorkCycle(1, 2)))
      .then(check(workReworkRefs(1) == [{ evaluator: 11, resultRef: 3711 }]))
  }

  // A failure that stands is the ticket's own, so the policy that would
  // invalidate it escalates instead and no work cycle starts.
  run failedVerdictThatStandsIsNeverInvalidatedTest = {
    failedTwice(3800)
      .then(reportFinalizationWithPolicy(
        1,
        FinalizationFailureStands(3820),
        invalidatePolicy,
      ))
      .then(check(decisionInvariant))
      .then(check(decidedEvent == TicketFinalizationFailureEscalated({
        ticket: 1,
        workCycle: 1,
        generation: 2,
        evidence: 3820,
      })))
      .then(check(graph.tickets.get(1).workCyclesStarted == 1))
      .then(check(escalatedWith(1, escalation => escalation ==
        EvaluationFailureEscalated({
          evidence: [{ evaluator: 11, resultRef: 3811 }],
          source: 3890,
        }))))
  }

  run failureStandsIsRefusedWithoutAFailedVerdictTest = {
    val refusal = TicketRefused(FinalizationResultNotAllowed({
      ticket: 1,
      workCycle: 1,
      generation: 1,
    }))
    passedOnce(3900)
      .then(reportFinalization(1, FinalizationFailureStands(3920)))
      .then(check(lastDecision == refusal))
      .then(check(evolve(graph, TicketFinalizationFailureReworked({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        evidence: 3920,
      })) == graph))
      .then(check(evolve(graph, TicketFinalizationFailureEscalated({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        evidence: 3920,
      })) == graph))
  }

  run failedVerdictMayBeEvaluatedAgainWithoutAWorkCycleTest = {
    failedTwice(4000)
      .then(requestEvaluation(1, 4020))
      .then(check(decisionInvariant))
      .then(check(graph.tickets.get(1).workCyclesStarted == 1))
      .then(check(evaluating(1, evaluation =>
        evaluation.round == 3
        and evaluation.origin == Requested({ generation: 2, evidence: 4020 }))))
      .then(reportEvaluatorResult(1, 4021, EvaluatorPass))
      .then(reportEvaluatorResult(1, 4022, EvaluatorPass))
      .then(reportEvaluatorResult(1, 4023, EvaluatorPass))
      .then(check(finalizing(1, operation =>
        operation.round == 3 and operation.generation == 3
        and operation.basis == PassedVerdict)))
      .then(reportFinalization(1, FinalizationSucceeded(4030)))
      .then(check(ticketDone(1)))
  }

  run failedVerdictMayStillNeedWorkTest = {
    failedTwice(4100)
      .then(reportFinalization(1, FinalizationNeedsWork(4120)))
      .then(check(decisionInvariant))
      .then(check(ticketWorkCycle(1, 2)))
      .then(check(match graph.tickets.get(1).state {
        | Work(work) => work.input.cause == FinalizationRework(4120)
        | _ => false
      }))
  }

  run invalidatingARequestedEvaluationReturnsItToFinalizationTest = {
    passedOnce(4200)
      .then(requestEvaluation(1, 4210))
      .then(reportEvaluatorResult(1, 4211, EvaluatorPass))
      .then(submit(InvalidateEvaluation({
        ticket: 1,
        workCycle: 1,
        round: 1,
        evidence: 4220,
      })))
      .then(check(lastDecision == TicketRefused(EvaluationNotCurrent({
        ticket: 1,
        workCycle: 1,
        round: 1,
      }))))
      .then(invalidateEvaluation(1, 4220))
      .then(check(decisionInvariant))
      .then(check(decidedEvent == TicketEvaluationWithdrawn({
        ticket: 1,
        workCycle: 1,
        round: 2,
        evidence: 4220,
      })))
      .then(check(decidedCancels == [evaluatorTaskIdentity(1, 1, 2, 10, 1, 12)]))
      .then(check(decidedTasks == []))
      .then(check(graph.tickets.get(1).workCyclesStarted == 1))
      .then(check(finalizing(1, operation =>
        operation.round == 2 and operation.generation == 2
        and operation.origin == Requested({ generation: 1, evidence: 4210 })
        and operation.basis == WithdrawnVerdict)))
      .then(check(match graph.tickets.get(1).state {
        | Finalization(operation) => decidedFinalizations == [operation]
        | _ => false
      }))
      .then(reportFinalization(1, FinalizationSucceeded(4230)))
      .then(check(lastDecision == TicketRefused(FinalizationResultNotAllowed({
        ticket: 1,
        workCycle: 1,
        generation: 2,
      }))))
      .then(reportFinalization(1, FinalizationFailureStands(4231)))
      .then(check(lastDecision == TicketRefused(FinalizationResultNotAllowed({
        ticket: 1,
        workCycle: 1,
        generation: 2,
      }))))
      .then(requestEvaluation(1, 4240))
      .then(check(evaluating(1, evaluation => evaluation.round == 3)))
      .then(check(decidedTasks == [
        evaluatorTaskIdentity(1, 1, 3, 10, 1, 11),
        evaluatorTaskIdentity(1, 1, 3, 10, 1, 12),
      ]))
  }

  // The work-opened event sends a ticket to Work, so it never applies to a
  // requested evaluation, and the requested one's event never to a work-opened.
  run invalidationEventsDoNotCrossOriginsTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 4300))
      .then(check(evolve(graph, TicketEvaluationWithdrawn({
        ticket: 1,
        workCycle: 1,
        round: 1,
        evidence: 4310,
      })) == graph))
      .then(reportEvaluatorResult(1, 4301, EvaluatorPass))
      .then(reportEvaluatorResult(1, 4302, EvaluatorPass))
      .then(reportEvaluatorResult(1, 4303, EvaluatorPass))
      .then(requestEvaluation(1, 4320))
      .then(check(evolve(graph, TicketEvaluationInvalidated({
        ticket: 1,
        workCycle: 1,
        evidence: 4330,
      })) == graph))
      .then(check(evolve(graph, TicketEvaluationWithdrawn({
        ticket: 1,
        workCycle: 1,
        round: 3,
        evidence: 4330,
      })) == graph))
      .then(check(evolve(graph, TicketEvaluationWithdrawn({
        ticket: 1,
        workCycle: 1,
        round: 2,
        evidence: 4330,
      })) != graph))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => {
            val report =
              currentEvaluatorReport(1, evaluation, 4331, EvaluatorFail)
            evolve(graph, TicketEvaluationReworkStarted({
              ticket: 1,
              report: report,
              evidence: [{ evaluator: 11, resultRef: 4331 }],
            })) == graph
          }
        | _ => false
      }))
  }

  run blockedRequestedEvaluationResumesOrIsWithdrawnTest = {
    passedOnce(4400)
      .then(requestEvaluation(1, 4410))
      .then(reportEvaluatorResult(1, 4411, EvaluatorPass))
      .then(reportEvaluatorUnavailable(1, 4412))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(submit(ResumeTicket(1)))
      .then(check(evaluating(1, evaluation => evaluation.round == 2)))
      .then(check(decidedTasks == [evaluatorTaskIdentity(1, 1, 2, 10, 2, 12)]))
      .then(reportEvaluatorUnavailable(1, 4413))
      .then(submit(InvalidateEvaluation({
        ticket: 1,
        workCycle: 1,
        round: 2,
        evidence: 4420,
      })))
      .then(check(decisionInvariant))
      .then(check(decidedCancels == []))
      .then(check(finalizing(1, operation =>
        operation.round == 2 and operation.generation == 2
        and operation.basis == WithdrawnVerdict)))
      .then(check(match graph.tickets.get(1).state {
        | Finalization(operation) => decidedFinalizations == [operation]
        | _ => false
      }))
  }

  // A finalization on a passed basis may be completing, so it cannot be
  // revoked and a ticket waiting there leaves by its finalizer reporting that
  // it cannot proceed.
  run passedFinalizationLeavesThroughUnavailableTest = {
    passedOnce(4500)
      .then(requestEvaluation(1, 4510))
      .then(reportEvaluatorResult(1, 4511, EvaluatorPass))
      .then(reportEvaluatorResult(1, 4512, EvaluatorPass))
      .then(reportEvaluatorResult(1, 4513, EvaluatorPass))
      .then(submit(RevokeTicket(1)))
      .then(check(lastDecision == TicketRefused(TicketNotRevocable(1))))
      .then(check(evolve(graph, TicketRevoked(1)) == graph))
      .then(reportFinalization(1, FinalizationResultUnavailable(4520)))
      .then(check(decisionInvariant))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(submit(ResumeTicket(1)))
      .then(check(finalizing(1, operation =>
        operation.round == 2 and operation.generation == 3
        and operation.origin == Requested({ generation: 1, evidence: 4510 })
        and operation.basis == PassedVerdict)))
      .then(reportFinalization(1, FinalizationResultUnavailable(4521)))
      .then(submit(RevokeTicket(1)))
      .then(check(graph.tickets.get(1).state == Revoked))
  }

  // An operation that resumes is the one that escalated: its basis is still a
  // failure, so it still cannot complete and the failure may still stand.
  run failedBasisSurvivesAFinalizationEscalationTest = {
    failedTwice(4550)
      .then(reportFinalization(1, FinalizationResultUnavailable(4570)))
      .then(check(decisionInvariant))
      .then(submit(ResumeTicket(1)))
      .then(check(decisionInvariant))
      .then(check(finalizing(1, operation =>
        operation.round == 2 and operation.generation == 3
        and operation.origin == Requested({ generation: 1, evidence: 4560 })
        and basisFailed(operation)
        and failedBasisEntries(operation.basis)
          == [{ evaluator: 11, resultRef: 4561 }])))
      .then(reportFinalization(1, FinalizationSucceeded(4571)))
      .then(check(lastDecision == TicketRefused(FinalizationResultNotAllowed({
        ticket: 1,
        workCycle: 1,
        generation: 3,
      }))))
      .then(reportFinalization(1, FinalizationFailureStands(4572)))
      .then(check(ticketWorkCycle(1, 2)))
      .then(check(workReworkRefs(1) == [{ evaluator: 11, resultRef: 4561 }]))
  }

  // No finalization completes on a failed basis, so nothing is being
  // finalized and the ticket may be revoked where it waits.
  run failedFinalizationMayBeRevokedTest = {
    failedTwice(4600)
      .then(submit(RevokeTicket(1)))
      .then(check(decisionInvariant))
      .then(check(lastDecision == TicketDecided({
        event: TicketRevoked(1),
        obligations: [],
      })))
      .then(check(graph.tickets.get(1).state == Revoked))
      .then(submit(ReportFinalizationResult({
        ticket: 1,
        workCycle: 1,
        generation: 2,
        result: FinalizationNeedsEvaluation(4620),
      })))
      .then(check(lastDecision == TicketRefused(FinalizationNotCurrent({
        ticket: 1,
        workCycle: 1,
        generation: 2,
      }))))
  }

  run withdrawnFinalizationMayBeRevokedTest = {
    passedOnce(4700)
      .then(requestEvaluation(1, 4710))
      .then(invalidateEvaluation(1, 4720))
      .then(check(finalizing(1, operation =>
        operation.basis == WithdrawnVerdict)))
      .then(submit(RevokeTicket(1)))
      .then(check(decisionInvariant))
      .then(check(graph.tickets.get(1).state == Revoked))
  }

  // A report for an operation that is not the current one is refused as not
  // current whatever it says, before its result is judged against the basis.
  pure def firstOperationReport(result: FinalizationResult): TicketCommand =
    ReportFinalizationResult({
      ticket: 1,
      workCycle: 1,
      generation: 1,
      result: result,
    })

  run staleFinalizationReportIsRefusedBeforeItsResultIsJudgedTest = {
    val refusal = TicketRefused(FinalizationNotCurrent({
      ticket: 1,
      workCycle: 1,
      generation: 1,
    }))
    failedTwice(4800)
      .then(submit(firstOperationReport(FinalizationSucceeded(4820))))
      .then(check(lastDecision == refusal))
      .then(submit(firstOperationReport(FinalizationFailureStands(4821))))
      .then(check(lastDecision == refusal))
      .then(requestEvaluation(1, 4830))
      .then(invalidateEvaluation(1, 4831))
      .then(submit(firstOperationReport(FinalizationFailureStands(4832))))
      .then(check(lastDecision == refusal))
  }

  // `evolve` applies an event only in the state `decide` produces it from: a
  // requested evaluation's failure is never disposed by the events of a
  // work-opened one, and no finalization completes on a withdrawn basis.
  run finalizationEventsApplyOnlyWhereDecidedTest = {
    val succeeded = TicketFinalizationSucceeded({
      ticket: 1,
      workCycle: 1,
      generation: 2,
      evidence: 4920,
    })
    passedOnce(4900)
      .then(requestEvaluation(1, 4910))
      .then(reportEvaluatorResult(1, 4911, EvaluatorPass))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => {
            val report =
              currentEvaluatorReport(1, evaluation, 4912, EvaluatorFail)
            val entries = [{ evaluator: 12, resultRef: 4912 }]
            evolve(graph, TicketEvaluationFailureEscalated({
              ticket: 1,
              report: report,
              evidence: entries,
            })) == graph
            and evolve(graph, TicketEvaluationFailureInvalidated({
              ticket: 1,
              report: report,
              evidence: 4913,
            })) == graph
            and evolve(graph, TicketEvaluationReworkStarted({
              ticket: 1,
              report: report,
              evidence: entries,
            })) == graph
            and evolve(graph, TicketEvaluationFailureReturned({
              ticket: 1,
              report: report,
            })) != graph
          }
        | _ => false
      }))
      .then(invalidateEvaluation(1, 4915))
      .then(check(finalizing(1, operation =>
        operation.generation == 2 and operation.basis == WithdrawnVerdict)))
      .then(check(evolve(graph, succeeded) == graph))
      .then(check(not(decisionValid(graph, TicketDecided({
        event: succeeded,
        obligations: [],
      })))))
  }

  // A work-opened evaluation's failure never returns to a finalizer, and a
  // blocked requested evaluation is never invalidated back to Work.
  run evaluationEventsDoNotCrossOriginsTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResult(1, 5000))
      .then(reportEvaluatorResult(1, 5001, EvaluatorPass))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) =>
            evolve(graph, TicketEvaluationFailureReturned({
              ticket: 1,
              report: currentEvaluatorReport(1, evaluation, 5002, EvaluatorFail),
            })) == graph
        | _ => false
      }))
      .then(reportEvaluatorResult(1, 5003, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5004, EvaluatorPass))
      .then(requestEvaluation(1, 5010))
      .then(reportEvaluatorResult(1, 5011, EvaluatorPass))
      .then(reportEvaluatorUnavailable(1, 5012))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(check(evolve(graph, TicketEvaluationInvalidated({
        ticket: 1,
        workCycle: 1,
        evidence: 5013,
      })) == graph))
  }

  // Every round continues the cycle's count, so an operation is current, and
  // completes, however many evaluations were requested before it.
  run finalizationCompletesAfterManyRequestedEvaluationsTest = {
    passedOnce(5100)
      .then(requestEvaluation(1, 5110))
      .then(reportEvaluatorResult(1, 5111, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5112, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5113, EvaluatorPass))
      .then(requestEvaluation(1, 5120))
      .then(reportEvaluatorResult(1, 5121, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5122, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5123, EvaluatorPass))
      .then(requestEvaluation(1, 5130))
      .then(reportEvaluatorResult(1, 5131, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5132, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5133, EvaluatorPass))
      .then(requestEvaluation(1, 5140))
      .then(reportEvaluatorResult(1, 5141, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5142, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5143, EvaluatorPass))
      .then(check(finalizing(1, operation =>
        operation.round == 5 and operation.generation == 5
        and operation.origin == Requested({ generation: 4, evidence: 5140 }))))
      .then(reportFinalization(1, FinalizationSucceeded(5150)))
      .then(check(decisionInvariant))
      .then(check(ticketDone(1)))
  }

  // A work cycle's operations are numbered from 1 again, so a report is
  // current only for its own cycle as well as its own generation.
  run finalizationReportFromAnEarlierWorkCycleIsRefusedTest = {
    val late = ReportFinalizationResult({
      ticket: 1,
      workCycle: 1,
      generation: 1,
      result: FinalizationSucceeded(5220),
    })
    passedOnce(5200)
      .then(reportFinalization(1, FinalizationNeedsWork(5210)))
      // The new cycle starts from the source the result was accepted at, not
      // from the result.
      .then(check(match graph.tickets.get(1).state {
        | Work(work) => work.source == 5290
        | _ => false
      }))
      .then(reportWorkResult(1, 5211))
      .then(reportEvaluatorResult(1, 5212, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5213, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5214, EvaluatorPass))
      .then(check(finalizing(1, operation =>
        operation.workCycle == 2 and operation.generation == 1)))
      .then(submit(late))
      .then(check(lastDecision == TicketRefused(FinalizationNotCurrent({
        ticket: 1,
        workCycle: 1,
        generation: 1,
      }))))
      .then(check(evolve(graph, TicketFinalizationSucceeded({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        evidence: 5220,
      })) == graph))
      .then(reportFinalization(1, FinalizationSucceeded(5221)))
      .then(check(ticketDone(1)))
  }

  pure def decisionEvent(decision: TicketDecision): TicketEvent =
    match decision {
      | TicketDecided(success) => success.event
      | TicketRefused(_) => TicketRevoked(0)
    }

  pure def decisionObligations(decision: TicketDecision): List[Obligation] =
    match decision {
      | TicketDecided(success) => success.obligations
      | TicketRefused(_) => []
    }

  pure def withObligations(
    decision: TicketDecision,
    obligations: List[Obligation],
  ): TicketDecision = TicketDecided({
    event: decisionEvent(decision),
    obligations: obligations,
  })

  // A decision is valid only with every obligation it owes and none it does
  // not: each task it starts, whole, and each finalization it opens.
  run decisionOwesExactlyWhatItStartsTest = {
    passedOnce(5300)
      .then(check({
        val request = decide(graph, ReportFinalizationResult({
          ticket: 1,
          workCycle: 1,
          generation: 1,
          result: FinalizationNeedsEvaluation(5310),
        }), reworkPolicy)
        val owed = decisionObligations(request)
        and {
          owed.length() == 2,
          decisionValid(graph, request),
          not(decisionValid(graph, withObligations(request, []))),
          not(decisionValid(graph, withObligations(request, [owed[0]]))),
          not(decisionValid(graph, withObligations(request, [
            owed[0],
            owed[1],
            owed[1],
          ]))),
          not(decisionValid(graph, withObligations(request, [
            owed[0],
            match owed[1] {
              | ExecuteTask(execution) => ExecuteTask({
                  ...execution,
                  task: {
                    ...execution.task,
                    contextRef: execution.task.contextRef + 1,
                  },
                })
              | _ => owed[1]
            },
          ]))),
          // An event that does not apply where it is decided is no decision.
          not(decisionValid(graph, TicketDecided({
            event: TicketFinalizationNeedsWork({
              ticket: 1,
              workCycle: 1,
              generation: 2,
              evidence: 5311,
            }),
            obligations: [],
          }))),
        }
      }))
      .then(requestEvaluation(1, 5310))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => {
            val progress = decide(graph, ReportTaskTerminal(
              currentEvaluatorReport(1, evaluation, 5311, EvaluatorPass),
            ), reworkPolicy)
            val waiting = currentTaskObligations(evaluation)[1]
            and {
              decisionValid(graph, progress),
              decisionObligations(progress) == [],
              // The other evaluator is still awaited, so it is not started again.
              not(decisionValid(graph, withObligations(progress, [
                ExecuteTask({ ticket: 1, task: waiting }),
              ]))),
            }
          }
        | _ => false
      }))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => {
            val withdrawal = decide(graph, InvalidateEvaluation({
              ticket: 1,
              workCycle: 1,
              round: 2,
              evidence: 5312,
            }), reworkPolicy)
            val owed = decisionObligations(withdrawal)
            and {
              owed.length() == 3,
              decisionValid(graph, withdrawal),
              not(decisionValid(graph, withObligations(withdrawal, [
                owed[0],
                owed[1],
              ]))),
              // Nor one more finalization than the one the ticket entered.
              not(decisionValid(graph, withObligations(withdrawal, [
                owed[0],
                owed[1],
                owed[2],
                match owed[2] {
                  | FinalizeTicket(request) => FinalizeTicket({
                      ...request,
                      finalization: {
                        ...request.finalization,
                        generation: request.finalization.generation + 1,
                      },
                    })
                  | _ => owed[2]
                },
              ]))),
              not(decisionValid(graph, withObligations(withdrawal, [
                owed[0],
                owed[1],
                match owed[2] {
                  | FinalizeTicket(request) => FinalizeTicket({
                      ...request,
                      configuration: request.configuration + 1,
                    })
                  | _ => owed[2]
                },
              ]))),
            }
          }
        | _ => false
      }))
  }

  pure def withOperation(
    candidate: TicketGraph,
    operation: FinalizationOperation,
  ): TicketGraph = {
    tickets: candidate.tickets.set(1, {
      ...candidate.tickets.get(1),
      state: Finalization(operation),
    }),
  }

  // The invariant holds an operation to the evaluation it follows: its origin
  // to its round, an earlier operation as its requester, and a failed basis
  // to the very evaluation that failed.
  run finalizationOperationIsHeldToItsEvaluationTest = {
    failedTwice(5400)
      .then(check(match graph.tickets.get(1).state {
        | Finalization(operation) => {
            val other = Requested({ generation: 1, evidence: 5499 })
            and {
              graphInvariant(graph),
              not(graphInvariant(withOperation(graph, {
                ...operation,
                origin: OpenedByWork,
              }))),
              not(graphInvariant(withOperation(graph, {
                ...operation,
                origin: Requested({ generation: 2, evidence: 5410 }),
              }))),
              not(graphInvariant(withOperation(graph, {
                ...operation,
                origin: other,
              }))),
              // On a passed basis nothing but the origin's own rules can
              // reject these: round 2 was not opened by work, and no request
              // comes from the operation it produced.
              graphInvariant(withOperation(graph, {
                ...operation,
                basis: PassedVerdict,
              })),
              not(graphInvariant(withOperation(graph, {
                ...operation,
                origin: OpenedByWork,
                basis: PassedVerdict,
              }))),
              not(graphInvariant(withOperation(graph, {
                ...operation,
                origin: Requested({ generation: 2, evidence: 5410 }),
                basis: PassedVerdict,
              }))),
              // A request carries evidence, comes from the round before, and
              // the first operation of a cycle is generation 1 or later.
              not(graphInvariant(withOperation(graph, {
                ...operation,
                origin: Requested({ generation: 1, evidence: 0 }),
                basis: PassedVerdict,
              }))),
              not(graphInvariant(withOperation(graph, {
                ...operation,
                round: 3,
                generation: 4,
                basis: PassedVerdict,
              }))),
              graphInvariant(withOperation(graph, {
                ...operation,
                round: 1,
                generation: 1,
                origin: OpenedByWork,
                basis: PassedVerdict,
              })),
              not(graphInvariant(withOperation(graph, {
                ...operation,
                round: 1,
                generation: 0,
                origin: OpenedByWork,
                basis: PassedVerdict,
              }))),
              // An operation is of the ticket's current work cycle.
              not(graphInvariant(withOperation(graph, {
                ...operation,
                workCycle: 2,
                basis: PassedVerdict,
              }))),
              graphInvariant(withOperation(graph, {
                ...operation,
                basis: WithdrawnVerdict,
              })),
              not(graphInvariant(withOperation(graph, {
                ...operation,
                round: 1,
                origin: OpenedByWork,
                basis: WithdrawnVerdict,
              }))),
              not(graphInvariant(withOperation(graph, {
                ...operation,
                round: 1,
                basis: PassedVerdict,
              }))),
              not(completionFollowsAPass(graph, TicketFinalizationSucceeded({
                ticket: 1,
                workCycle: 1,
                generation: 2,
                evidence: 5420,
              }))),
              completionFollowsAPass(
                withOperation(graph, { ...operation, basis: PassedVerdict }),
                TicketFinalizationSucceeded({
                  ticket: 1,
                  workCycle: 1,
                  generation: 2,
                  evidence: 5420,
                }),
              ),
            }
          }
        | _ => false
      }))
  }

  // A ticket waiting with its finalizer owes nothing new when another ticket
  // is decided.
  run anotherTicketIsDecidedWhileOneFinalizesTest = {
    passedOnce(5500)
      .then(submit(CreateTicket(released(3, Set()))))
      .then(check(decisionInvariant))
      .then(submit(CreateTicket(released(2, Set(1)))))
      .then(check(decisionInvariant))
      .then(submit(dispatch(3)))
      .then(check(decisionInvariant))
      .then(reportWorkResult(3, 5510))
      .then(check(decisionInvariant))
      .then(submit(RevokeTicket(3)))
      .then(check(decisionInvariant))
      .then(check(ticketFinalizing(1)))
  }

  // Generations count a work cycle's operations and rounds its evaluations,
  // so they part at a resumed finalization. The round requested from one is
  // still the next round, it names the generation that asked, and the
  // operation after it is the generation after that.
  run requestedRoundAfterAResumeTest = {
    val late = ReportFinalizationResult({
      ticket: 1,
      workCycle: 1,
      generation: 2,
      result: FinalizationSucceeded(5630),
    })
    passedOnce(5600)
      .then(reportFinalization(1, FinalizationResultUnavailable(5610)))
      .then(check(match graph.tickets.get(1).state {
        | Escalated(escalation) => match escalation {
            | FinalizationUnavailableEscalated(failure) =>
                graphInvariant(graph)
                // An escalated finalization is held to the same rules.
                and not(graphInvariant({
                  tickets: graph.tickets.set(1, {
                    ...graph.tickets.get(1),
                    state: Escalated(FinalizationUnavailableEscalated({
                      ...failure,
                      finalization: { ...failure.finalization, input: 0 },
                    })),
                  }),
                }))
            | _ => false
          }
        | _ => false
      }))
      .then(submit(ResumeTicket(1)))
      .then(check(finalizing(1, operation =>
        operation.round == 1 and operation.generation == 2)))
      .then(requestEvaluation(1, 5620))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => and {
            evaluation.round == 2,
            evaluation.origin == Requested({ generation: 2, evidence: 5620 }),
            // A running round is held to the request that opened it.
            not(graphInvariant({
              tickets: graph.tickets.set(1, {
                ...graph.tickets.get(1),
                state: Evaluation({
                  ...evaluation,
                  origin: Requested({ generation: 0, evidence: 5620 }),
                }),
              }),
            })),
            not(graphInvariant({
              tickets: graph.tickets.set(1, {
                ...graph.tickets.get(1),
                state: Evaluation({
                  ...evaluation,
                  origin: Requested({ generation: 2, evidence: 0 }),
                }),
              }),
            })),
            not(graphInvariant({
              tickets: graph.tickets.set(1, {
                ...graph.tickets.get(1),
                state: Evaluation({ ...evaluation, origin: OpenedByWork }),
              }),
            })),
          }
        | _ => false
      }))
      .then(reportEvaluatorResult(1, 5621, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5622, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5623, EvaluatorPass))
      .then(check(finalizing(1, operation => and {
        operation.round == 2,
        operation.generation == 3,
        operation.origin == Requested({ generation: 2, evidence: 5620 }),
        operation.basis == PassedVerdict,
      })))
      // A report for the operation that asked is stale, and completes nothing.
      .then(submit(late))
      .then(check(lastDecision == TicketRefused(FinalizationNotCurrent({
        ticket: 1,
        workCycle: 1,
        generation: 2,
      }))))
      .then(check(ticketFinalizing(1)))
      .then(reportFinalization(1, FinalizationSucceeded(5631)))
      .then(check(ticketDone(1)))
  }

  pure def withEvaluationOrigin(
    candidate: TicketGraph,
    origin: EvaluationOrigin,
  ): TicketGraph = match candidate.tickets.get(1).state {
    | Evaluation(evaluation) => {
        tickets: candidate.tickets.set(1, {
          ...candidate.tickets.get(1),
          state: Evaluation({ ...evaluation, origin: origin }),
        }),
      }
    | _ => candidate
  }

  // A round keeps the request that opened it while it is blocked and when it
  // is resumed. A third round was asked for by the second round's operation,
  // whose generation is 2 or later, and never by an earlier one.
  run requestedRoundKeepsItsOriginTest = {
    passedOnce(5900)
      .then(reportFinalization(1, FinalizationResultUnavailable(5910)))
      .then(submit(ResumeTicket(1)))
      .then(requestEvaluation(1, 5920))
      .then(reportEvaluatorResult(1, 5921, EvaluatorPass))
      .then(reportEvaluatorUnavailable(1, 5922))
      .then(check(match graph.tickets.get(1).state {
        | Escalated(escalation) => match escalation {
            | EvaluationBlockedEscalated(saved) =>
                saved.round == 2
                and saved.origin == Requested({ generation: 2, evidence: 5920 })
            | _ => false
          }
        | _ => false
      }))
      .then(submit(ResumeTicket(1)))
      .then(check(evaluating(1, evaluation =>
        evaluation.round == 2
        and evaluation.origin == Requested({ generation: 2, evidence: 5920 }))))
      .then(reportEvaluatorResult(1, 5923, EvaluatorPass))
      .then(reportEvaluatorResult(1, 5924, EvaluatorPass))
      .then(check(finalizing(1, operation =>
        operation.round == 2 and operation.generation == 3)))
      .then(requestEvaluation(1, 5930))
      .then(check(evaluating(1, evaluation =>
        evaluation.round == 3
        and evaluation.origin == Requested({ generation: 3, evidence: 5930 }))))
      .then(check(and {
        graphInvariant(graph),
        graphInvariant(withEvaluationOrigin(
          graph,
          Requested({ generation: 2, evidence: 5930 }),
        )),
        not(graphInvariant(withEvaluationOrigin(
          graph,
          Requested({ generation: 1, evidence: 5930 }),
        ))),
      }))
  }

  // A failed basis is the evaluation its operation follows in every part: its
  // ticket, work cycle, round, result and source, a valid evaluation, and one
  // that failed.
  run failedBasisIsHeldInEveryPartTest = {
    passedOnce(5700)
      .then(submit(CreateTicket(released(2, Set()))))
      .then(reportFinalization(1, FinalizationResultUnavailable(5710)))
      .then(submit(ResumeTicket(1)))
      .then(requestEvaluation(1, 5720))
      .then(reportEvaluatorResult(1, 5721, EvaluatorFail))
      .then(reportEvaluatorResult(1, 5722, EvaluatorPass))
      .then(check(match graph.tickets.get(1).state {
        | Finalization(operation) => match operation.basis {
            | FailedVerdict(failed) => {
                val ticket = graph.tickets.get(1)
                val other = graph.tickets.get(2)
                val running = requestedEvaluation(
                  ticket,
                  {
                    ...operation,
                    round: 1,
                    generation: 2,
                    origin: OpenedByWork,
                    basis: PassedVerdict,
                  },
                  5720,
                )
                and {
                  operation.round == 2,
                  operation.generation == 3,
                  graphInvariant(graph),
                  not(graphInvariant(withOperation(graph, {
                    ...operation,
                    round: 3,
                  }))),
                  not(graphInvariant(withOperation(graph, {
                    ...operation,
                    input: operation.input + 1,
                  }))),
                  not(graphInvariant(withOperation(graph, {
                    ...operation,
                    source: operation.source + 1,
                  }))),
                  // The ticket and its operation in a later work cycle.
                  not(graphInvariant({
                    tickets: graph.tickets.set(1, {
                      ...ticket,
                      workCyclesStarted: 2,
                      state: Finalization({ ...operation, workCycle: 2 }),
                    }),
                  })),
                  // The operation on another ticket.
                  not(graphInvariant({
                    tickets: graph.tickets.set(2, {
                      ...other,
                      workCyclesStarted: 1,
                      state: Finalization(operation),
                    }),
                  })),
                  // No operation is of a work cycle before the first.
                  not(graphInvariant({
                    tickets: graph.tickets.set(2, {
                      ...other,
                      state: Finalization({
                        workCycle: 0,
                        round: 1,
                        generation: 1,
                        input: operation.input,
                        source: operation.source,
                        origin: OpenedByWork,
                        basis: PassedVerdict,
                      }),
                    }),
                  })),
                  // The same round still running.
                  running.origin == operation.origin,
                  invariant(running),
                  not(graphInvariant(withOperation(graph, {
                    ...operation,
                    basis: FailedVerdict(running),
                  }))),
                  // No valid evaluation.
                  not(graphInvariant(withOperation(graph, {
                    ...operation,
                    basis: FailedVerdict({
                      ...failed,
                      plan: {
                        ...failed.plan,
                        stages: failed.plan.stages.concat(failed.plan.stages),
                      },
                    }),
                  }))),
                }
              }
            | _ => false
          }
        | _ => false
      }))
  }

  // A failed basis is a requested round's. The first evaluation's failure is
  // disposed at once and never waits in Finalization.
  run failedBasisIsARequestedRoundTest = {
    init
      .then(submit(CreateTicket(released(1, Set()))))
      .then(submit(dispatch(1)))
      .then(reportWorkResultWithSource(1, 5800, 5890))
      .then(reportEvaluatorResult(1, 5801, EvaluatorFail))
      .then(check(match graph.tickets.get(1).state {
        | Evaluation(evaluation) => {
            val failed = applyEvaluationReport(
              evaluation,
              currentEvaluatorReport(1, evaluation, 5802, EvaluatorPass),
            )
            val operation = finalizationAfter(failed, FailedVerdict(failed))
            and {
              // Nor is round 1 ever a requested one.
              not(graphInvariant({
                tickets: graph.tickets.set(1, {
                  ...graph.tickets.get(1),
                  state: Evaluation({
                    ...evaluation,
                    origin: Requested({ generation: 1, evidence: 5803 }),
                  }),
                }),
              })),
              invariant(failed),
              failedBasisEntries(FailedVerdict(failed)).length() > 0,
              not(graphInvariant(withOperation(graph, operation))),
              graphInvariant(withOperation(graph, {
                ...operation,
                basis: PassedVerdict,
              })),
            }
          }
        | _ => false
      }))
  }

  run finalizationResultEvidenceMustBePositiveTest = {
    init.then(check(
      not(finalizationResultValid(FinalizationNeedsEvaluation(0)))
      and finalizationResultValid(FinalizationNeedsEvaluation(1))
      and not(finalizationResultValid(FinalizationFailureStands(0)))
      and finalizationResultValid(FinalizationFailureStands(1))
      and not(commandValid(InvalidateEvaluation({
        ticket: 1,
        workCycle: 1,
        round: 0,
        evidence: 1,
      })))
    ))
  }

  def priorOperationIs(ticket: int, workCycle: int, generation: int): bool =
    match priorGraph.tickets.get(ticket).state {
      | Finalization(operation) =>
          operation.workCycle == workCycle
          and operation.generation == generation
      | _ => false
    }

  def priorEvaluationIs(ticket: int, workCycle: int, round: int): bool =
    match priorGraph.tickets.get(ticket).state {
      | Evaluation(evaluation) =>
          evaluation.workCycle == workCycle and evaluation.round == round
      | Escalated(escalation) => match escalation {
          | EvaluationBlockedEscalated(saved) =>
              saved.workCycle == workCycle and saved.round == round
          | _ => false
        }
      | _ => false
    }

  // A decision about a finalization or an evaluation was addressed to the
  // one that was current: its work cycle, and its generation or its round.
  def decisionsAddressTheCurrent = match lastDecision {
    | TicketRefused(_) => true
    | TicketDecided(success) => match success.event {
        | TicketFinalizationSucceeded(fact) =>
            priorOperationIs(fact.ticket, fact.workCycle, fact.generation)
        | TicketFinalizationNeedsWork(fact) =>
            priorOperationIs(fact.ticket, fact.workCycle, fact.generation)
        | TicketFinalizationUnavailable(fact) =>
            priorOperationIs(fact.ticket, fact.workCycle, fact.generation)
        | TicketFinalizationNeedsEvaluation(fact) =>
            priorOperationIs(fact.ticket, fact.workCycle, fact.generation)
        | TicketFinalizationFailureReworked(fact) =>
            priorOperationIs(fact.ticket, fact.workCycle, fact.generation)
        | TicketFinalizationFailureEscalated(fact) =>
            priorOperationIs(fact.ticket, fact.workCycle, fact.generation)
        | TicketEvaluationWithdrawn(fact) =>
            priorEvaluationIs(fact.ticket, fact.workCycle, fact.round)
        | TicketEvaluationInvalidated(fact) =>
            priorEvaluationIs(fact.ticket, fact.workCycle, 1)
        | _ => true
      }
  }

  pure def operationFollows(
    operation: FinalizationOperation,
    evaluation: EvaluationInstance,
  ): bool = and {
    operation.workCycle == evaluation.workCycle,
    operation.round == evaluation.round,
    operation.origin == evaluation.origin,
    operation.generation == match evaluation.origin {
      | OpenedByWork => 1
      | Requested(request) => request.generation + 1
    },
  }

  pure def heldEvaluation(state: TicketState): List[EvaluationInstance] =
    match state {
      | Evaluation(evaluation) => [evaluation]
      | Escalated(escalation) => match escalation {
          | EvaluationBlockedEscalated(evaluation) => [evaluation]
          | _ => []
        }
      | _ => []
    }

  // A round keeps its work cycle, number and origin while it runs, when it is
  // blocked and when it is resumed.
  pure def roundKept(before: TicketState, after: TicketState): bool = {
    val was = heldEvaluation(before)
    val now = heldEvaluation(after)
    was.length() == 0 or now.length() == 0 or and {
      now[0].workCycle == was[0].workCycle,
      now[0].round == was[0].round,
      now[0].origin == was[0].origin,
    }
  }

  // A round is kept as above. A requested evaluation is the round after its
  // requester's and names the requester's generation. The operation an
  // evaluation hands over is of the evaluation's round and the generation
  // after its requester's, and a resumed one is the generation after the one
  // that escalated. Together they keep a work cycle from using a generation
  // twice.
  def roundsAndGenerationsContinue = graph.tickets.keys().forall(ticket =>
    not(priorGraph.tickets.keys().contains(ticket)) or {
      val before = priorGraph.tickets.get(ticket).state
      roundKept(before, graph.tickets.get(ticket).state)
      and match graph.tickets.get(ticket).state {
        | Evaluation(evaluation) => match before {
            | Finalization(operation) => and {
                evaluation.workCycle == operation.workCycle,
                evaluation.round == operation.round + 1,
                match evaluation.origin {
                  | Requested(request) =>
                      request.generation == operation.generation
                  | OpenedByWork => false
                },
              }
            | _ => true
          }
        | Finalization(operation) => match before {
            | Evaluation(evaluation) => operationFollows(operation, evaluation)
            | Escalated(escalation) => match escalation {
                | EvaluationBlockedEscalated(evaluation) =>
                    operationFollows(operation, evaluation)
                | FinalizationUnavailableEscalated(failure) => and {
                    operation.workCycle == failure.finalization.workCycle,
                    operation.round == failure.finalization.round,
                    operation.generation
                      == failure.finalization.generation + 1,
                  }
                | _ => true
              }
            | _ => true
          }
        | _ => true
      }
    })

  def modelInvariant = and {
    graphInvariant(graph),
    decisionInvariant,
    decisionsAddressTheCurrent,
    roundsAndGenerationsContinue,
  }

  def someDone = graph.tickets.keys().exists(ticket =>
    graph.tickets.get(ticket).state == Done)

  // Witnesses for the simulation: states the requested-evaluation paths must
  // be able to reach.
  def someThirdRound = graph.tickets.keys().exists(ticket =>
    match graph.tickets.get(ticket).state {
      | Evaluation(evaluation) => evaluation.round >= 3
      | _ => false
    })

  def someFailedBasis = graph.tickets.keys().exists(ticket =>
    match graph.tickets.get(ticket).state {
      | Finalization(operation) => basisFailed(operation)
      | _ => false
    })

  def someWithdrawnBasis = graph.tickets.keys().exists(ticket =>
    match graph.tickets.get(ticket).state {
      | Finalization(operation) => operation.basis == WithdrawnVerdict
      | _ => false
    })

  def someDoneAfterReevaluation = lastDecision != noDecision
    and match decidedEvent {
      | TicketFinalizationSucceeded(fact) =>
          someDone
          and match priorGraph.tickets.get(fact.ticket).state {
            | Finalization(operation) => operation.round > 1
            | _ => false
          }
      | _ => false
    }

  def someRevokedFromFinalization = lastDecision != noDecision
    and match decidedEvent {
      | TicketRevoked(ticket) =>
          ticket > 0 and graphFinalizing(priorGraph, ticket)
      | _ => false
    }

  def somePassedLaterRound = graph.tickets.keys().exists(ticket =>
    match graph.tickets.get(ticket).state {
      | Finalization(operation) =>
          operation.round > 1 and operation.basis == PassedVerdict
      | _ => false
    })

  def someLaterCycleFinalization = graph.tickets.keys().exists(ticket =>
    match graph.tickets.get(ticket).state {
      | Finalization(operation) => operation.workCycle > 1
      | _ => false
    })

  action createOne = submit(CreateTicket(released(1, Set())))
  action createTwo = submit(CreateTicket(released(2, Set(1))))

  action updateOne = {
    val expected =
      if (graph.tickets.keys().contains(1)) graph.tickets.get(1).revision else 1
    submit(updateTo(1, expected, revised(1, Set())))
  }

  action updateOneOnTwo = {
    val expected =
      if (graph.tickets.keys().contains(1)) graph.tickets.get(1).revision else 1
    submit(updateTo(1, expected, revised(1, Set(2))))
  }

  action updateTwo(dependencies: Set[int]): bool = {
    val expected =
      if (graph.tickets.keys().contains(2)) graph.tickets.get(2).revision else 1
    submit(updateTo(2, expected, revised(2, dependencies)))
  }

  action updateTwoFree = updateTwo(Set())
  action updateTwoOnOne = updateTwo(Set(1))

  action dispatchOne = submit(dispatch(1))
  action dispatchTwo = submit(dispatch(2))
  action revokeOne = submit(RevokeTicket(1))
  action resumeOne = submit(ResumeTicket(1))

  action passWorkOne = reportWorkResult(1, 501)
  action failWorkOne = reportWorkProcessFailed(1, 508)
  action unavailableWorkOne = reportWorkExecutionUnavailable(1, 509)
  action passEvaluatorOne = reportEvaluatorResult(1, 502, EvaluatorPass)
  action failEvaluatorOne = reportEvaluatorResult(1, 503, EvaluatorFail)
  action unavailableEvaluatorOne = reportEvaluatorUnavailable(1, 504)
  action invalidateOne = invalidateEvaluation(1, 510)
  action invalidateFailedEvaluatorOne = reportEvaluatorResultWithFailureDisposition(
    1,
    511,
    EvaluatorFail,
    invalidatePolicy,
  )
  action completeFinalizationOne =
    reportFinalization(1, FinalizationSucceeded(505))
  action reworkFinalizationOne =
    reportFinalization(1, FinalizationNeedsWork(506))
  action unavailableFinalizationOne =
    reportFinalization(1, FinalizationResultUnavailable(507))
  action requestEvaluationOne = requestEvaluation(1, 512)
  action failureStandsOne =
    reportFinalization(1, FinalizationFailureStands(513))
  action failureStandsEscalatedOne = reportFinalizationWithPolicy(
    1,
    FinalizationFailureStands(514),
    escalatePolicy,
  )
  action failureStandsInvalidatedOne = reportFinalizationWithPolicy(
    1,
    FinalizationFailureStands(515),
    invalidatePolicy,
  )

  action step = any {
    createOne,
    createTwo,
    updateOne,
    updateOneOnTwo,
    updateTwoFree,
    updateTwoOnOne,
    dispatchOne,
    dispatchTwo,
    revokeOne,
    resumeOne,
    passWorkOne,
    failWorkOne,
    unavailableWorkOne,
    passEvaluatorOne,
    failEvaluatorOne,
    unavailableEvaluatorOne,
    invalidateOne,
    invalidateFailedEvaluatorOne,
    completeFinalizationOne,
    reworkFinalizationOne,
    unavailableFinalizationOne,
    requestEvaluationOne,
    failureStandsOne,
    failureStandsEscalatedOne,
    failureStandsInvalidatedOne,
  }

  // === The finalizer's simulation ===========================================
  //
  // `step` spends most of a trace creating and dispatching, so it seldom
  // reaches a finalizer. This simulation starts from a ticket whose first
  // evaluation has passed and takes only the steps a finalizer, its
  // evaluators and an operator take from there, among them commands addressed
  // to an operation, a round or a task that may not be the current one.

  pure val finalizingGraph: TicketGraph = {
    val created = applyCommand(
      { tickets: Map() },
      CreateTicket(released(1, Set())),
      reworkPolicy,
    )
    val dispatched = applyCommand(created, dispatch(1), reworkPolicy)
    val ticket = dispatched.tickets.get(1)
    val worked = match ticket.state {
      | Work(work) => applyCommand(
          dispatched,
          ReportTaskTerminal(WorkResultReport({
            ticket: 1,
            result: validatedTaskResult(
              workTaskObligation(ticket, 1, work.source, work.input),
              501,
            ),
            acceptedSourceRef: source(1, 501),
          })),
          reworkPolicy,
        )
      | _ => dispatched
    }
    range(0, 3).foldl(worked, (reached, _) =>
      match reached.tickets.get(1).state {
        | Evaluation(evaluation) => applyCommand(
            reached,
            ReportTaskTerminal(
              currentEvaluatorReport(1, evaluation, 502, EvaluatorPass),
            ),
            reworkPolicy,
          )
        | _ => reached
      })
  }

  action initFinalizing = all {
    graph' = finalizingGraph,
    priorGraph' = finalizingGraph,
    lastDecision' = noDecision,
  }

  // A stray command is addressed near what is current: to it exactly, or
  // off it in one part of the address, so a refusal shows which part was
  // checked. Where ticket 1 has no operation or evaluation to address, it
  // addresses the first one its current work cycle could have. `Earlier` and
  // `Later` move a generation or a round, and `AnotherCycle` names the next
  // work cycle. A stray finalization report carries a result every basis
  // takes or one of the two only one basis takes.
  type Drift = OnTarget | AnotherCycle | Earlier | Later

  pure def drifted(
    cycle: int,
    ordinal: int,
    drift: Drift,
  ): { cycle: int, ordinal: int } = match drift {
    | OnTarget => { cycle: cycle, ordinal: ordinal }
    | AnotherCycle => { cycle: cycle + 1, ordinal: ordinal }
    | Earlier => {
        cycle: cycle,
        ordinal: if (ordinal > 1) ordinal - 1 else ordinal + 2,
      }
    | Later => { cycle: cycle, ordinal: ordinal + 1 }
  }

  action strayFinalizationOne = {
    nondet drift = Set(OnTarget, AnotherCycle, Earlier, Later).oneOf()
    nondet result = Set(
      FinalizationSucceeded(601),
      FinalizationNeedsEvaluation(604),
      FinalizationFailureStands(605),
    ).oneOf()
    val ticket = graph.tickets.get(1)
    val address = match ticket.state {
      | Finalization(operation) =>
          drifted(operation.workCycle, operation.generation, drift)
      | _ => drifted(ticket.workCyclesStarted, 1, drift)
    }
    submit(ReportFinalizationResult({
      ticket: 1,
      workCycle: address.cycle,
      generation: address.ordinal,
      result: result,
    }))
  }

  action strayInvalidateOne = {
    nondet drift = Set(OnTarget, AnotherCycle, Earlier, Later).oneOf()
    val ticket = graph.tickets.get(1)
    val address = match ticket.state {
      | Evaluation(evaluation) =>
          drifted(evaluation.workCycle, evaluation.round, drift)
      | Escalated(escalation) => match escalation {
          | EvaluationBlockedEscalated(saved) =>
              drifted(saved.workCycle, saved.round, drift)
          | _ => drifted(ticket.workCyclesStarted, 1, drift)
        }
      | _ => drifted(ticket.workCyclesStarted, 1, drift)
    }
    submit(InvalidateEvaluation({
      ticket: 1,
      workCycle: address.cycle,
      round: address.ordinal,
      evidence: 606,
    }))
  }

  // A stray evaluator report names an awaited task, or one that differs from
  // it in one part of its identity. It is a produced result, which is held to
  // the whole obligation, or a failure, which is held to the identity alone.
  type TaskDrift =
    SameTask
    | TaskOfAnotherCycle
    | TaskOfAnotherRound
    | TaskOfAnotherStage
    | TaskOfAnotherGeneration
    | TaskOfAnotherEvaluator

  type StrayOutcome = StrayFail | StrayProcessFailed

  pure def driftedTask(
    identity: EvaluationTaskIdentity,
    drift: TaskDrift,
  ): TaskIdentity = EvaluationTask(match drift {
    | SameTask => identity
    | TaskOfAnotherCycle => {
        ...identity,
        workCycle: identity.workCycle + 1,
      }
    | TaskOfAnotherRound => { ...identity, round: identity.round + 1 }
    | TaskOfAnotherStage => { ...identity, stage: identity.stage + 10 }
    | TaskOfAnotherGeneration => {
        ...identity,
        generation: identity.generation + 1,
      }
    | TaskOfAnotherEvaluator => {
        ...identity,
        evaluator: identity.evaluator + 1,
      }
  })

  // The first awaited evaluator's task, or the first task the current work
  // cycle's evaluation would have where none is awaited.
  pure def strayTaskBase(ticket: Ticket): EvaluationTaskIdentity = {
    val fallback = {
      ticket: 1,
      workCycle: ticket.workCyclesStarted,
      round: 1,
      stage: 10,
      generation: 1,
      evaluator: 11,
    }
    match ticket.state {
      | Evaluation(evaluation) =>
          match currentTaskObligations(evaluation)[0].task {
            | EvaluationTask(identity) => identity
            | WorkTask(_) => fallback
          }
      | _ => fallback
    }
  }

  pure def strayEvaluatorReport(
    task: TaskIdentity,
    outcome: StrayOutcome,
  ): TaskTerminalReport = {
    val obligation = { task: task, definition: EVALUATOR, contextRef: 501 }
    match outcome {
      | StrayFail => EvaluationResultReport({
          ticket: 1,
          result: validatedTaskResult(obligation, 608),
          verdict: EvaluatorFail,
        })
      | StrayProcessFailed => TerminalFailureReport({
          ticket: 1,
          failure: { task: task, evidence: 609 },
          kind: ProcessFailure,
        })
    }
  }

  action strayEvaluatorOne = {
    nondet taskDrift = Set(
      SameTask,
      TaskOfAnotherCycle,
      TaskOfAnotherRound,
      TaskOfAnotherStage,
      TaskOfAnotherGeneration,
      TaskOfAnotherEvaluator,
    ).oneOf()
    nondet outcome = Set(StrayFail, StrayProcessFailed).oneOf()
    submit(ReportTaskTerminal(strayEvaluatorReport(
      driftedTask(strayTaskBase(graph.tickets.get(1)), taskDrift),
      outcome,
    )))
  }

  // A finished ticket leaves the walk nothing but refusals, so it takes a
  // few and starts again.
  action restartFinalizing = all {
    isTerminal(graph.tickets.get(1).state),
    graph' = finalizingGraph,
    priorGraph' = finalizingGraph,
    lastDecision' = noDecision,
  }

  action finalizerStep =
    if (isTerminal(graph.tickets.get(1).state)) any {
      restartFinalizing,
      strayFinalizationOne,
      strayEvaluatorOne,
    } else finalizerLiveStep

  // A round passes only by three passes in a row, so a pass is listed more
  // than once: the walk picks among the listed steps evenly, and otherwise
  // seldom sees a requested round pass.
  action finalizerLiveStep = any {
    revokeOne,
    resumeOne,
    passWorkOne,
    passWorkOne,
    failWorkOne,
    passEvaluatorOne,
    passEvaluatorOne,
    passEvaluatorOne,
    passEvaluatorOne,
    failEvaluatorOne,
    unavailableEvaluatorOne,
    invalidateOne,
    invalidateFailedEvaluatorOne,
    completeFinalizationOne,
    reworkFinalizationOne,
    unavailableFinalizationOne,
    requestEvaluationOne,
    failureStandsOne,
    failureStandsEscalatedOne,
    failureStandsInvalidatedOne,
    strayFinalizationOne,
    strayInvalidateOne,
    strayEvaluatorOne,
  }

  // The events `evolve` is tried against in every state the simulation
  // reaches. They are ticket 1's only: each finalization, withdrawal and
  // invalidation event at each address near the current one, its revocation
  // and resumptions, and each event a report from an awaited evaluator could
  // have been decided as. Creation, update, dispatch and work events are not
  // among them.

  pure def finalizationEventsAt(cycle: int, generation: int): Set[TicketEvent] = {
    val fact = {
      ticket: 1,
      workCycle: cycle,
      generation: generation,
      evidence: 700,
    }
    Set(
      TicketFinalizationSucceeded(fact),
      TicketFinalizationNeedsWork(fact),
      TicketFinalizationUnavailable(fact),
      TicketFinalizationNeedsEvaluation(fact),
      TicketFinalizationFailureReworked(fact),
      TicketFinalizationFailureEscalated(fact),
    )
  }

  pure val addressedEvents: Set[TicketEvent] =
    tuples(Set(1, 2, 3), Set(1, 2, 3, 4, 5, 6))
      .map(address => finalizationEventsAt(address._1, address._2))
      .flatten()
      .union(tuples(Set(1, 2, 3), Set(1, 2, 3, 4, 5)).map(address =>
        TicketEvaluationWithdrawn({
          ticket: 1,
          workCycle: address._1,
          round: address._2,
          evidence: 701,
        })))
      .union(Set(1, 2, 3).map(cycle => TicketEvaluationInvalidated({
        ticket: 1,
        workCycle: cycle,
        evidence: 702,
      })))
      .union(Set(
        TicketRevoked(1),
        TicketWorkResumed(1),
        TicketEvaluationResumed(1),
        TicketFinalizationResumed(1),
      ))

  def currentEvaluatorReports: Set[TaskTerminalReport] =
    match graph.tickets.get(1).state {
      | Evaluation(evaluation) => currentTaskObligations(evaluation)
          .foldl(Set(), (found, obligation) => found.union(Set(
            EvaluationResultReport({
              ticket: 1,
              result: validatedTaskResult(obligation, 710),
              verdict: EvaluatorPass,
            }),
            EvaluationResultReport({
              ticket: 1,
              result: validatedTaskResult(obligation, 711),
              verdict: EvaluatorFail,
            }),
            TerminalFailureReport({
              ticket: 1,
              failure: { task: obligation.task, evidence: 712 },
              kind: ProcessFailure,
            }),
            TerminalFailureReport({
              ticket: 1,
              failure: { task: obligation.task, evidence: 713 },
              kind: ExecutionUnavailableFailure,
            }),
          )))
      | _ => Set()
    }

  def reportEvents(report: TaskTerminalReport): Set[TicketEvent] = {
    val entries = match graph.tickets.get(1).state {
      | Evaluation(evaluation) => {
          val updated = applyEvaluationReport(evaluation, report)
          match updated.state {
            | EvaluationFailed(completed) => reworkEntries(updated, completed)
            | _ => []
          }
        }
      | _ => []
    }
    Set(
      TicketEvaluationProgressed({ ticket: 1, report: report }),
      TicketEvaluationPassed({ ticket: 1, report: report }),
      TicketEvaluationBlocked({ ticket: 1, report: report }),
      TicketEvaluationFailureReturned({ ticket: 1, report: report }),
      TicketEvaluationReworkStarted({
        ticket: 1,
        report: report,
        evidence: entries,
      }),
      TicketEvaluationFailureEscalated({
        ticket: 1,
        report: report,
        evidence: entries,
      }),
      TicketEvaluationFailureInvalidated({
        ticket: 1,
        report: report,
        evidence: 1601,
      }),
    )
  }

  def candidateEvents: Set[TicketEvent] = addressedEvents
    .union(currentEvaluatorReports.map(report => reportEvents(report)).flatten())

  pure def finalizationReportBehind(
    fact: FinalizationFact,
    result: FinalizationResult,
  ): TicketCommand = ReportFinalizationResult({
    ticket: fact.ticket,
    workCycle: fact.workCycle,
    generation: fact.generation,
    result: result,
  })

  // The command that decides an event, where one command does.
  pure def commandBehind(event: TicketEvent): TicketCommand = match event {
    | TicketFinalizationSucceeded(fact) =>
        finalizationReportBehind(fact, FinalizationSucceeded(fact.evidence))
    | TicketFinalizationNeedsWork(fact) =>
        finalizationReportBehind(fact, FinalizationNeedsWork(fact.evidence))
    | TicketFinalizationUnavailable(fact) => finalizationReportBehind(
        fact,
        FinalizationResultUnavailable(fact.evidence),
      )
    | TicketFinalizationNeedsEvaluation(fact) => finalizationReportBehind(
        fact,
        FinalizationNeedsEvaluation(fact.evidence),
      )
    | TicketFinalizationFailureReworked(fact) =>
        finalizationReportBehind(fact, FinalizationFailureStands(fact.evidence))
    | TicketFinalizationFailureEscalated(fact) =>
        finalizationReportBehind(fact, FinalizationFailureStands(fact.evidence))
    | TicketEvaluationWithdrawn(fact) => InvalidateEvaluation({
        ticket: fact.ticket,
        workCycle: fact.workCycle,
        round: fact.round,
        evidence: fact.evidence,
      })
    | TicketEvaluationInvalidated(fact) => InvalidateEvaluation({
        ticket: fact.ticket,
        workCycle: fact.workCycle,
        round: 1,
        evidence: fact.evidence,
      })
    | TicketEvaluationProgressed(fact) => ReportTaskTerminal(fact.report)
    | TicketEvaluationPassed(fact) => ReportTaskTerminal(fact.report)
    | TicketEvaluationBlocked(fact) => ReportTaskTerminal(fact.report)
    | TicketEvaluationFailureReturned(fact) => ReportTaskTerminal(fact.report)
    | TicketEvaluationReworkStarted(fact) => ReportTaskTerminal(fact.report)
    | TicketEvaluationFailureEscalated(fact) => ReportTaskTerminal(fact.report)
    | TicketEvaluationFailureInvalidated(fact) =>
        ReportTaskTerminal(fact.report)
    | TicketRevoked(ticket) => RevokeTicket(ticket)
    | _ => ResumeTicket(1)
  }

  def producible(event: TicketEvent): bool = Set(
    decide(graph, commandBehind(event), reworkPolicy),
    decide(graph, commandBehind(event), escalatePolicy),
    decide(graph, commandBehind(event), invalidatePolicy),
  ).exists(decision => match decision {
    | TicketDecided(success) => success.event == event
    | TicketRefused(_) => false
  })

  // `evolve` never leaves the invariant on any candidate event.
  def evolveClosed = candidateEvents.forall(event =>
    graphInvariant(evolve(graph, event)))

  // `evolve` applies a candidate event only where `decide` produces it.
  def evolveOnlyWhatDecideProduces = candidateEvents.forall(event =>
    evolve(graph, event) == graph or producible(event))

  pure def isDecided(decision: TicketDecision): bool = match decision {
    | TicketDecided(_) => true
    | TicketRefused(_) => false
  }

  def accepted(command: TicketCommand): bool =
    isDecided(decide(graph, command, escalatePolicy))

  // Every state short of Done and Revoked has a command the domain accepts:
  // each basis takes exactly the results it allows, an evaluation can always
  // be reported on or invalidated, an escalation resumed, and a ticket
  // revoked wherever nothing can be completing.
  def neverStuck = match graph.tickets.get(1).state {
    | Done => true
    | Revoked => true
    | Finalization(operation) => and {
        accepted(finalizationReportBehind(
          {
            ticket: 1,
            workCycle: operation.workCycle,
            generation: operation.generation,
            evidence: 901,
          },
          FinalizationNeedsEvaluation(901),
        )),
        accepted(finalizationReportBehind(
          {
            ticket: 1,
            workCycle: operation.workCycle,
            generation: operation.generation,
            evidence: 902,
          },
          FinalizationNeedsWork(902),
        )),
        accepted(finalizationReportBehind(
          {
            ticket: 1,
            workCycle: operation.workCycle,
            generation: operation.generation,
            evidence: 903,
          },
          FinalizationResultUnavailable(903),
        )),
        accepted(finalizationReportBehind(
          {
            ticket: 1,
            workCycle: operation.workCycle,
            generation: operation.generation,
            evidence: 905,
          },
          FinalizationSucceeded(905),
        )) == (operation.basis == PassedVerdict),
        accepted(finalizationReportBehind(
          {
            ticket: 1,
            workCycle: operation.workCycle,
            generation: operation.generation,
            evidence: 906,
          },
          FinalizationFailureStands(906),
        )) == basisFailed(operation),
        accepted(RevokeTicket(1)) == (operation.basis != PassedVerdict),
      }
    | Evaluation(evaluation) => and {
        currentEvaluatorReports.size() > 0,
        currentEvaluatorReports.forall(report =>
          accepted(ReportTaskTerminal(report))),
        accepted(InvalidateEvaluation({
          ticket: 1,
          workCycle: evaluation.workCycle,
          round: evaluation.round,
          evidence: 904,
        })),
        accepted(RevokeTicket(1)),
      }
    | Escalated(escalation) => and {
        accepted(ResumeTicket(1)),
        accepted(RevokeTicket(1)),
        match escalation {
          | EvaluationBlockedEscalated(saved) =>
              accepted(InvalidateEvaluation({
                ticket: 1,
                workCycle: saved.workCycle,
                round: saved.round,
                evidence: 907,
              }))
          | _ => true
        },
      }
    | _ => accepted(RevokeTicket(1))
  }

  // A finalization that resumes is the operation that escalated, one
  // generation on.
  def resumeKeepsTheOperation = match lastDecision {
    | TicketRefused(_) => true
    | TicketDecided(success) => match success.event {
        | TicketFinalizationResumed(ticket) =>
            match priorGraph.tickets.get(ticket).state {
              | Escalated(escalation) => match escalation {
                  | FinalizationUnavailableEscalated(failure) =>
                      graph.tickets.get(ticket).state == Finalization({
                        ...failure.finalization,
                        generation: failure.finalization.generation + 1,
                      })
                  | _ => false
                }
              | _ => false
            }
        | _ => true
      }
  }

  def finalizerInvariant = and {
    modelInvariant,
    evolveClosed,
    evolveOnlyWhatDecideProduces,
    resumeKeepsTheOperation,
    neverStuck,
  }
}
