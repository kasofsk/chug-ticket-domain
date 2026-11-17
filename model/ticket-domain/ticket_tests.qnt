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
      | Work(work) => work.input.cause == StackInvalidated(evidence)
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

  run failedVerdictThatStandsMayBeInvalidatedByThePolicyTest = {
    failedTwice(3800)
      .then(reportFinalizationWithPolicy(
        1,
        FinalizationFailureStands(3820),
        invalidatePolicy,
      ))
      .then(check(decisionInvariant))
      .then(check(ticketWorkCycle(1, 2)))
      .then(check(workInvalidatedWith(1, 1601)))
      .then(check(workUsesSource(1, 3890)))
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
      .then(check(evolve(graph, TicketFinalizationFailureInvalidated({
        ticket: 1,
        workCycle: 1,
        generation: 1,
        evidence: 3920,
        invalidation: 3921,
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
        and operation.basis == WithdrawnVerdict(4220))))
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
        and operation.basis == WithdrawnVerdict(4420))))
  }

  // Finalization cannot be revoked, so a ticket waiting there leaves by its
  // finalizer reporting that it cannot proceed.
  run waitingFinalizationLeavesThroughUnavailableTest = {
    failedTwice(4500)
      .then(submit(RevokeTicket(1)))
      .then(check(lastDecision == TicketRefused(TicketNotRevocable(1))))
      .then(reportFinalization(1, FinalizationResultUnavailable(4520)))
      .then(check(decisionInvariant))
      .then(check(isEscalated(graph.tickets.get(1).state)))
      .then(submit(ResumeTicket(1)))
      .then(check(finalizing(1, operation =>
        operation.round == 2 and operation.generation == 3
        and basisFailed(operation))))
      .then(reportFinalization(1, FinalizationResultUnavailable(4521)))
      .then(submit(RevokeTicket(1)))
      .then(check(graph.tickets.get(1).state == Revoked))
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

  def modelInvariant = graphInvariant(graph) and decisionInvariant

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
      | Finalization(operation) => match operation.basis {
          | WithdrawnVerdict(_) => true
          | _ => false
        }
      | _ => false
    })

  def someDoneAfterReevaluation = lastDecision != noDecision
    and match decidedEvent {
      | TicketFinalizationSucceeded(fact) => fact.generation > 1 and someDone
      | _ => false
    }

  def someEscalated = graph.tickets.keys().exists(ticket =>
    match graph.tickets.get(ticket).state {
      | Escalated(_) => true
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
}
