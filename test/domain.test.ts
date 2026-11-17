import { expect, test } from "vitest";
import * as t from "../src/task.js";
import * as e from "../src/evaluation.js";
import * as k from "../src/ticket.js";
import * as b from "../src/testing.js";

function started(): b.Driver {
  const driver = new b.Driver();
  driver.submit(new k.CreateTicket(b.released(1)));
  driver.submit(b.dispatch(1));
  return driver;
}

function producedWork(
  graph: k.TicketGraph,
  resultRef: number,
  sourceRef: number,
): k.ReportTaskTerminal {
  return new k.ReportTaskTerminal(
    new k.WorkResultReport(
      t.TicketId(1),
      new t.ValidatedTaskResult(
        b.work_obligation(graph, 1),
        t.ContentRef(resultRef),
      ),
      t.ContentRef(sourceRef),
    ),
  );
}

test("task definitions require immutable refs", () => {
  expect(
    () =>
      new t.TaskDefinition(
        t.ContentRef(0),
        t.ContentRef(1),
        t.ContentRef(1),
        t.ContentRef(1),
      ),
  ).toThrow();
  expect(
    () =>
      new t.TaskDefinition(
        t.ContentRef(1),
        t.ContentRef(1),
        t.ContentRef(0),
        t.ContentRef(1),
      ),
  ).toThrow();
  const obligation = new t.TaskObligation(
    new t.WorkTaskId(t.TicketId(1), t.CycleNumber(1)),
    b.WORK,
    t.ContextRef(1),
  );
  expect(
    () => new t.ValidatedTaskResult(obligation, t.ContentRef(0)),
  ).toThrow();
  expect(
    () => new t.TaskObligation(obligation.task, b.WORK, t.ContextRef(0)),
  ).toThrow();
  expect(
    new t.ValidatedTaskResult(obligation, t.ContentRef(9)).obligation,
  ).toBe(obligation);
});

test("a produced work report pins its accepted source for evaluation and finalization", () => {
  const driver = started();
  expect(driver.submit(producedWork(driver.graph, 501, 991))).toBeInstanceOf(
    k.TicketDecided,
  );
  let state = driver.graph.tickets.get(t.TicketId(1))!.state;
  expect(state).toBeInstanceOf(k.Evaluation);
  if (!(state instanceof k.Evaluation)) return;
  expect(state.evaluation.input.work_result).toBe(501);
  expect(state.evaluation.input.accepted_source_ref).toBe(991);
  expect(e.current_task_obligations(state.evaluation)[0]!.context_ref).toBe(
    501,
  );
  for (const ref of [601, 602, 603]) {
    state = driver.graph.tickets.get(t.TicketId(1))!.state;
    if (!(state instanceof k.Evaluation))
      throw new Error("evaluation ended early");
    driver.submit(
      new k.ReportTaskTerminal(
        new k.EvaluationResultReport(
          t.TicketId(1),
          new t.ValidatedTaskResult(
            e.current_task_obligations(state.evaluation)[0]!,
            t.ContentRef(ref),
          ),
          new e.EvaluatorPass(),
        ),
      ),
    );
  }
  state = driver.graph.tickets.get(t.TicketId(1))!.state;
  expect(state).toBeInstanceOf(k.Finalization);
  if (state instanceof k.Finalization) {
    expect(state.operation.input).toBe(501);
    expect(state.operation.source).toBe(991);
  }
});

test("a produced result must carry the exact current obligation", () => {
  const driver = started();
  const original = b.work_obligation(driver.graph, 1);
  const wrong = new t.TaskObligation(
    original.task,
    new t.TaskDefinition(
      t.ContentRef(99),
      b.WORK.inputs,
      b.WORK.execution_requirements,
      b.WORK.result_contract,
    ),
    original.context_ref,
  );
  const decision = driver.submit(
    new k.ReportTaskTerminal(
      new k.WorkResultReport(
        t.TicketId(1),
        new t.ValidatedTaskResult(wrong, t.ContentRef(501)),
        t.ContentRef(991),
      ),
    ),
  );
  expect(decision).toBeInstanceOf(k.TicketRefused);
  expect(driver.graph.tickets.get(t.TicketId(1))!.state).toBeInstanceOf(k.Work);
});

test("an explicit failed evaluator verdict carries its exact result ref to rework", () => {
  const driver = started();
  driver.submit(producedWork(driver.graph, 501, 991));
  let state = driver.graph.tickets.get(t.TicketId(1))!.state;
  if (!(state instanceof k.Evaluation)) throw new Error("evaluation missing");
  driver.submit(
    new k.ReportTaskTerminal(
      new k.EvaluationResultReport(
        t.TicketId(1),
        new t.ValidatedTaskResult(
          e.current_task_obligations(state.evaluation)[0]!,
          t.ContentRef(701),
        ),
        new e.EvaluatorFail(),
      ),
    ),
  );
  state = driver.graph.tickets.get(t.TicketId(1))!.state;
  if (!(state instanceof k.Evaluation))
    throw new Error("evaluation ended early");
  driver.submit(
    new k.ReportTaskTerminal(
      new k.EvaluationResultReport(
        t.TicketId(1),
        new t.ValidatedTaskResult(
          e.current_task_obligations(state.evaluation)[0]!,
          t.ContentRef(702),
        ),
        new e.EvaluatorPass(),
      ),
    ),
  );
  state = driver.graph.tickets.get(t.TicketId(1))!.state;
  expect(state).toBeInstanceOf(k.Work);
  if (state instanceof k.Work) {
    expect(state.execution.input.cause).toBeInstanceOf(k.EvaluationRework);
    if (state.execution.input.cause instanceof k.EvaluationRework)
      expect(state.execution.input.cause.entries).toEqual([
        new e.EvaluationReworkEntry(t.EvaluatorKey(11), t.ContentRef(701)),
      ]);
    expect(state.execution.source).toBe(991);
    expect(b.work_obligation(driver.graph, 1).context_ref).toBe(2);
  }
});

test("failure reports contain evidence without a result interpretation", () => {
  const driver = started();
  const task = b.work_obligation(driver.graph, 1).task;
  driver.submit(
    new k.ReportTaskTerminal(
      new k.TerminalFailureReport(
        t.TicketId(1),
        new t.TaskFailure(task, t.ContentRef(900)),
        new k.ProcessFailure(),
      ),
    ),
  );
  expect(driver.graph.tickets.get(t.TicketId(1))!.state).toBeInstanceOf(
    k.Escalated,
  );
});

test("an update refuses a dependency it adds unless that dependency is live and acyclic", () => {
  const ids = (...n: number[]) => new Set(n.map(t.TicketId));
  const update = (ticket: number, revision: number, deps: Set<t.TicketId>) =>
    new k.UpdateTicket(
      t.TicketId(ticket),
      revision,
      b.released(ticket, deps, true),
    );
  const driver = new b.Driver();
  driver.submit(new k.CreateTicket(b.released(1)));
  driver.submit(new k.CreateTicket(b.released(2, ids(1))));
  driver.submit(new k.CreateTicket(b.released(3)));
  expect(driver.submit(update(2, 1, ids(2)))).toEqual(
    new k.TicketRefused(new k.SelfDependency(t.TicketId(2))),
  );
  expect(driver.submit(update(2, 1, ids(1, 9)))).toEqual(
    new k.TicketRefused(new k.DependenciesNotFound(t.TicketId(2), ids(9))),
  );
  expect(driver.submit(update(1, 1, ids(3, 2)))).toEqual(
    new k.TicketRefused(new k.DependencyCycle(t.TicketId(1), ids(2))),
  );
  driver.submit(new k.RevokeTicket(t.TicketId(1)));
  expect(driver.submit(new k.CreateTicket(b.released(4, ids(1))))).toEqual(
    new k.TicketRefused(new k.DependenciesRevoked(t.TicketId(4), ids(1))),
  );
  expect(driver.submit(update(3, 1, ids(1)))).toEqual(
    new k.TicketRefused(new k.DependenciesRevoked(t.TicketId(3), ids(1))),
  );
  expect(driver.submit(update(2, 1, ids(1)))).toBeInstanceOf(k.TicketDecided);
  expect(driver.submit(update(2, 2, ids(3)))).toBeInstanceOf(k.TicketDecided);
  expect(
    driver.graph.tickets.get(t.TicketId(2))!.definition.dependencies,
  ).toEqual(ids(3));
  expect(k.graph_invariant(driver.graph)).toBe(true);
});

const T1 = t.TicketId(1);
const invalidate = (cycle: number, evidence: number, round = 1) =>
  new k.InvalidateEvaluation(
    T1,
    t.CycleNumber(cycle),
    t.Round(round),
    t.ContentRef(evidence),
  );
const state_of = (d: b.Driver) => d.graph.tickets.get(T1)!.state;
const refused = (cycle: number, round = 1) =>
  new k.TicketRefused(
    new k.EvaluationNotCurrent(T1, t.CycleNumber(cycle), t.Round(round)),
  );

function evaluating(): b.Driver {
  const driver = started();
  driver.submit(producedWork(driver.graph, 501, 991));
  return driver;
}

test("a decision that drops a live task without cancelling it is invalid", () => {
  const driver = evaluating();
  const decision = k.decide(driver.graph, invalidate(1, 511), k.rework_policy);
  if (!(decision instanceof k.TicketDecided)) throw new Error("not decided");
  expect(decision.obligations.some((o) => o instanceof k.CancelTask)).toBe(
    true,
  );
  expect(k.decision_valid(driver.graph, decision)).toBe(true);
  const stripped = new k.TicketDecided(
    decision.event,
    decision.obligations.filter((o) => !(o instanceof k.CancelTask)),
  );
  expect(k.decision_valid(driver.graph, stripped)).toBe(false);
});

test("invalidating an evaluation restarts work from the accepted source", () => {
  const driver = evaluating();
  driver.submit(invalidate(1, 511));
  const state = state_of(driver);
  if (!(state instanceof k.Work)) throw new Error("not in work");
  expect(state.execution.source).toBe(t.ContentRef(991));
  expect(state.execution.input.cause).toEqual(
    new k.EvaluationInvalidated(t.ContentRef(511)),
  );
  expect(driver.submit(invalidate(1, 512))).toEqual(refused(1));
  expect(k.graph_invariant(driver.graph)).toBe(true);
});

test("evolve ignores an invalidation for another cycle or state", () => {
  const driver = evaluating();
  const at = (cycle: number) =>
    new k.TicketEvaluationInvalidated(
      T1,
      t.CycleNumber(cycle),
      t.ContentRef(511),
    );
  expect(k.evolve(driver.graph, at(2))).toBe(driver.graph);
  driver.submit(invalidate(1, 511));
  expect(k.evolve(driver.graph, at(1))).toBe(driver.graph);
  driver.submit(producedWork(driver.graph, 502, 992));
  expect(k.evolve(driver.graph, at(1))).toBe(driver.graph);
  expect(k.evolve(driver.graph, at(2))).not.toBe(driver.graph);
});

test("a blocked evaluation escalation can be invalidated, a failure one cannot", () => {
  const blocked = evaluating();
  blocked.submit(
    b.evaluator_result_command(blocked.graph, 1, 511, new e.EvaluatorPass()),
  );
  blocked.submit(b.failure_command(blocked.graph, 1, 512, false, true));
  expect(state_of(blocked)).toBeInstanceOf(k.Escalated);
  expect(blocked.submit(invalidate(2, 521))).toEqual(refused(2));
  const decision = blocked.submit(invalidate(1, 521));
  if (!(decision instanceof k.TicketDecided)) throw new Error("not decided");
  expect(decision.obligations.some((o) => o instanceof k.CancelTask)).toBe(
    false,
  );
  const state = state_of(blocked);
  if (!(state instanceof k.Work)) throw new Error("not in work");
  expect(state.execution.source).toBe(t.ContentRef(991));
  expect(state.execution.input.cause).toEqual(
    new k.EvaluationInvalidated(t.ContentRef(521)),
  );
  const failed = evaluating();
  failed.submit(
    b.evaluator_result_command(failed.graph, 1, 611, new e.EvaluatorFail()),
  );
  failed.submit(
    b.evaluator_result_command(failed.graph, 1, 612, new e.EvaluatorPass()),
    () => new k.EscalateEvaluationFailure(),
  );
  expect(state_of(failed)).toBeInstanceOf(k.Escalated);
  expect(failed.submit(invalidate(1, 621))).toEqual(refused(1));
});

test("a policy must supply positive invalidation evidence", () => {
  const driver = evaluating();
  driver.submit(
    b.evaluator_result_command(driver.graph, 1, 511, new e.EvaluatorFail()),
  );
  const report = b.evaluator_result_command(
    driver.graph,
    1,
    512,
    new e.EvaluatorPass(),
  );
  const zero = k.decide(
    driver.graph,
    report,
    () => new k.InvalidateEvaluationFailure(t.ContentRef(0)),
  );
  expect(k.decision_valid(driver.graph, zero)).toBe(false);
  const good = k.decide(
    driver.graph,
    report,
    () => new k.InvalidateEvaluationFailure(t.ContentRef(1601)),
  );
  expect(k.decision_valid(driver.graph, good)).toBe(true);
  expect(good).toBeInstanceOf(k.TicketDecided);
  if (good instanceof k.TicketDecided)
    expect(good.event).toBeInstanceOf(k.TicketEvaluationFailureInvalidated);
});

test("work that fails after an invalidation resumes with the same cause", () => {
  const driver = evaluating();
  driver.submit(invalidate(1, 511));
  driver.submit(b.failure_command(driver.graph, 1, 521, true, false));
  expect(state_of(driver)).toBeInstanceOf(k.Escalated);
  driver.submit(new k.ResumeTicket(T1));
  const state = state_of(driver);
  if (!(state instanceof k.Work)) throw new Error("not in work");
  expect(state.execution.input.cause).toEqual(
    new k.EvaluationInvalidated(t.ContentRef(511)),
  );
  expect(state.execution.input.retry_evidence).toEqual([t.ContentRef(521)]);
  expect(k.graph_invariant(driver.graph)).toBe(true);
});

const pass = (d: b.Driver, ref: number) =>
  d.submit(b.evaluator_result_command(d.graph, 1, ref, new e.EvaluatorPass()));
const fail = (d: b.Driver, ref: number) =>
  d.submit(b.evaluator_result_command(d.graph, 1, ref, new e.EvaluatorFail()));
const finalization = (d: b.Driver) => {
  const s = state_of(d);
  if (!(s instanceof k.Finalization)) throw new Error("not in finalization");
  return s.operation;
};
const report = (generation: number, result: k.FinalizationResult) =>
  new k.ReportFinalizationResult(
    new k.FinalizationResultReport(
      T1,
      t.CycleNumber(1),
      t.Generation(generation),
      result,
    ),
  );
const not_allowed = (generation: number) =>
  new k.TicketRefused(
    new k.FinalizationResultNotAllowed(
      T1,
      t.CycleNumber(1),
      t.Generation(generation),
    ),
  );

function passed_once(): b.Driver {
  const driver = evaluating();
  pass(driver, 601);
  pass(driver, 602);
  pass(driver, 603);
  return driver;
}

function failed_twice(): b.Driver {
  const driver = passed_once();
  driver.submit(
    report(1, new k.FinalizationNeedsEvaluation(t.ContentRef(610))),
  );
  fail(driver, 611);
  pass(driver, 612);
  return driver;
}

test("a requested evaluation runs the same result again in the same cycle", () => {
  const driver = passed_once();
  expect(finalization(driver).basis).toBeInstanceOf(k.PassedVerdict);
  const decision = driver.submit(
    report(1, new k.FinalizationNeedsEvaluation(t.ContentRef(610))),
  );
  if (!(decision instanceof k.TicketDecided)) throw new Error("not decided");
  expect(k.decision_valid(driver.prior_graph, decision)).toBe(true);
  const state = state_of(driver);
  if (!(state instanceof k.Evaluation)) throw new Error("not evaluating");
  expect(state.evaluation.round).toBe(2);
  expect(state.evaluation.origin).toEqual(
    new e.Requested(t.Generation(1), t.ContentRef(610)),
  );
  expect(state.evaluation.input.work_result).toBe(t.ContentRef(501));
  expect(driver.graph.tickets.get(T1)!.work_cycles_started).toBe(1);
  const stale = report(1, new k.FinalizationSucceeded(t.ContentRef(620)));
  expect(driver.submit(stale)).toEqual(
    new k.TicketRefused(
      new k.FinalizationNotCurrent(T1, t.CycleNumber(1), t.Generation(1)),
    ),
  );
  pass(driver, 611);
  pass(driver, 612);
  pass(driver, 613);
  expect(finalization(driver).generation).toBe(2);
  expect(driver.submit(stale)).toBeInstanceOf(k.TicketRefused);
  driver.submit(report(2, new k.FinalizationSucceeded(t.ContentRef(620))));
  expect(state_of(driver)).toBeInstanceOf(k.Done);
});

test("a requested evaluation's failure returns to finalization unjudged", () => {
  const driver = passed_once();
  driver.submit(
    report(1, new k.FinalizationNeedsEvaluation(t.ContentRef(610))),
  );
  fail(driver, 611);
  const decision = driver.submit(
    b.evaluator_result_command(driver.graph, 1, 612, new e.EvaluatorPass()),
    () => new k.EscalateEvaluationFailure(),
  );
  if (!(decision instanceof k.TicketDecided)) throw new Error("not decided");
  expect(decision.event).toBeInstanceOf(k.TicketEvaluationFailureReturned);
  expect(k.decision_valid(driver.prior_graph, decision)).toBe(true);
  const operation = finalization(driver);
  expect(operation.basis).toBeInstanceOf(k.FailedVerdict);
  expect([operation.round, operation.generation]).toEqual([2, 2]);
  expect(
    driver.submit(report(2, new k.FinalizationSucceeded(t.ContentRef(620)))),
  ).toEqual(not_allowed(2));
  const forged = new k.TicketDecided(
    new k.TicketFinalizationSucceeded(
      T1,
      t.CycleNumber(1),
      t.Generation(2),
      t.ContentRef(620),
    ),
    [],
  );
  expect(k.decision_valid(driver.graph, forged)).toBe(false);
  expect(k.evolve(driver.graph, forged.event)).toBe(driver.graph);
});

test("a failed verdict that stands is disposed by the failure policy", () => {
  const stands = report(2, new k.FinalizationFailureStands(t.ContentRef(620)));
  const entries = [
    new e.EvaluationReworkEntry(t.EvaluatorKey(11), t.ContentRef(611)),
  ];
  const reworked = failed_twice();
  reworked.submit(stands);
  const work = state_of(reworked);
  if (!(work instanceof k.Work)) throw new Error("not in work");
  expect(work.execution.input.cause).toEqual(new k.EvaluationRework(entries));
  expect(work.execution.source).toBe(t.ContentRef(991));
  const escalated = failed_twice();
  escalated.submit(stands, () => new k.EscalateEvaluationFailure());
  expect(state_of(escalated)).toEqual(
    new k.Escalated(
      new k.EvaluationFailureEscalated(
        new k.EvaluationFailureEscalation(entries, t.ContentRef(991)),
      ),
    ),
  );
  // A failure that stands is the ticket's own: the policy that would
  // invalidate it, and one the domain does not recognise, both escalate.
  for (const policy of [
    () => new k.InvalidateEvaluationFailure(t.ContentRef(630)),
    () => ({ kind: "Unrecognised" }) as unknown as k.FailureDisposition,
  ]) {
    const other = failed_twice();
    const decision = other.submit(stands, policy);
    if (!(decision instanceof k.TicketDecided)) throw new Error("not decided");
    expect(decision.event).toEqual(
      new k.TicketFinalizationFailureEscalated(
        T1,
        t.CycleNumber(1),
        t.Generation(2),
        t.ContentRef(620),
      ),
    );
    expect(k.decision_valid(other.prior_graph, decision)).toBe(true);
    expect(state_of(other)).toEqual(state_of(escalated));
    expect(other.graph.tickets.get(T1)!.work_cycles_started).toBe(1);
  }
  for (const d of [reworked, escalated])
    expect(k.graph_invariant(d.graph)).toBe(true);
  const passed = passed_once();
  expect(
    passed.submit(
      report(1, new k.FinalizationFailureStands(t.ContentRef(620))),
    ),
  ).toEqual(not_allowed(1));
});

test("a failed verdict may be evaluated again without a work cycle", () => {
  const driver = failed_twice();
  driver.submit(
    report(2, new k.FinalizationNeedsEvaluation(t.ContentRef(620))),
  );
  const state = state_of(driver);
  if (!(state instanceof k.Evaluation)) throw new Error("not evaluating");
  expect(state.evaluation.round).toBe(3);
  expect(driver.graph.tickets.get(T1)!.work_cycles_started).toBe(1);
  expect(k.graph_invariant(driver.graph)).toBe(true);
});

test("invalidating a requested evaluation withdraws it to finalization", () => {
  const driver = passed_once();
  driver.submit(
    report(1, new k.FinalizationNeedsEvaluation(t.ContentRef(610))),
  );
  pass(driver, 611);
  expect(driver.submit(invalidate(1, 620))).toEqual(refused(1));
  const decision = driver.submit(invalidate(1, 620, 2));
  if (!(decision instanceof k.TicketDecided)) throw new Error("not decided");
  expect(decision.event).toEqual(
    new k.TicketEvaluationWithdrawn(
      T1,
      t.CycleNumber(1),
      t.Round(2),
      t.ContentRef(620),
    ),
  );
  expect(
    decision.obligations.filter((o) => o instanceof k.CancelTask),
  ).toHaveLength(1);
  expect(k.decision_valid(driver.prior_graph, decision)).toBe(true);
  expect(finalization(driver).basis).toEqual(new k.WithdrawnVerdict());
  expect(
    driver.submit(report(2, new k.FinalizationSucceeded(t.ContentRef(630)))),
  ).toEqual(not_allowed(2));
  expect(
    driver.submit(
      report(2, new k.FinalizationFailureStands(t.ContentRef(630))),
    ),
  ).toEqual(not_allowed(2));
  expect(
    k.evolve(
      driver.graph,
      new k.TicketEvaluationInvalidated(
        T1,
        t.CycleNumber(1),
        t.ContentRef(640),
      ),
    ),
  ).toBe(driver.graph);
});

const not_current = (generation: number) =>
  new k.TicketRefused(
    new k.FinalizationNotCurrent(
      T1,
      t.CycleNumber(1),
      t.Generation(generation),
    ),
  );
const fact = (generation: number, evidence = 700) =>
  [
    T1,
    t.CycleNumber(1),
    t.Generation(generation),
    t.ContentRef(evidence),
  ] as const;
const request = (d: b.Driver, generation: number, evidence: number) =>
  d.submit(
    report(
      generation,
      new k.FinalizationNeedsEvaluation(t.ContentRef(evidence)),
    ),
  );
const with_operation = (
  d: b.Driver,
  change: (o: k.FinalizationOperation) => k.FinalizationOperation,
) => {
  const ticket = d.graph.tickets.get(T1)!;
  return new k.TicketGraph(
    new Map([
      [
        T1,
        new k.Ticket(
          ticket.definition,
          ticket.revision,
          ticket.work_cycles_started,
          new k.Finalization(change(finalization(d))),
        ),
      ],
    ]),
  );
};

test("a finalization operation names the request its verdict answers", () => {
  const driver = passed_once();
  expect(finalization(driver).origin).toEqual(new e.OpenedByWork());
  request(driver, 1, 610);
  pass(driver, 611);
  pass(driver, 612);
  const passed = pass(driver, 613);
  const requested = new e.Requested(t.Generation(1), t.ContentRef(610));
  expect(finalization(driver).origin).toEqual(requested);
  expect(finalization(driver).basis).toBeInstanceOf(k.PassedVerdict);
  if (!(passed instanceof k.TicketDecided)) throw new Error("not decided");
  expect(passed.obligations).toEqual([
    new k.FinalizeTicket(T1, finalization(driver), t.ContentRef(1)),
  ]);
  expect(finalization(failed_twice()).origin).toEqual(requested);
  driver.submit(
    report(2, new k.FinalizationResultUnavailable(t.ContentRef(620))),
  );
  driver.submit(new k.ResumeTicket(T1));
  expect(finalization(driver).origin).toEqual(requested);
  expect(finalization(driver).generation).toBe(3);
  expect(k.graph_invariant(driver.graph)).toBe(true);
  // Round 1 was opened by work and a later round by an earlier operation.
  const forged = (origin: e.EvaluationOrigin) =>
    with_operation(
      driver,
      (o) =>
        new k.FinalizationOperation(
          o.work_cycle,
          o.round,
          o.generation,
          o.input,
          o.source,
          origin,
          o.basis,
        ),
    );
  expect(k.graph_invariant(forged(requested))).toBe(true);
  expect(k.graph_invariant(forged(new e.OpenedByWork()))).toBe(false);
  expect(
    k.graph_invariant(
      forged(new e.Requested(t.Generation(3), t.ContentRef(610))),
    ),
  ).toBe(false);
});

test("a failed basis is the evaluation its operation follows", () => {
  const driver = failed_twice();
  const basis = finalization(driver).basis;
  if (!(basis instanceof k.FailedVerdict)) throw new Error("not failed");
  const failed = basis.evaluation;
  const forged = (evaluation: e.EvaluationInstance) =>
    with_operation(
      driver,
      (o) =>
        new k.FinalizationOperation(
          o.work_cycle,
          o.round,
          o.generation,
          o.input,
          o.source,
          o.origin,
          new k.FailedVerdict(evaluation),
        ),
    );
  const again = (round: number, origin: e.EvaluationOrigin) =>
    new e.EvaluationInstance(
      failed.work_cycle,
      t.Round(round),
      origin,
      failed.input,
      failed.plan,
      failed.state,
    );
  expect(k.graph_invariant(forged(failed))).toBe(true);
  expect(k.graph_invariant(forged(again(3, failed.origin)))).toBe(false);
  expect(
    k.graph_invariant(
      forged(again(2, new e.Requested(t.Generation(1), t.ContentRef(611)))),
    ),
  ).toBe(false);
  const running = e.begin(
    failed.work_cycle,
    failed.round,
    failed.origin,
    failed.input,
    failed.plan,
  );
  expect(k.graph_invariant(forged(running))).toBe(false);
});

test("a report for another operation is refused before its result is judged", () => {
  const failed = failed_twice();
  for (const result of [
    new k.FinalizationSucceeded(t.ContentRef(620)),
    new k.FinalizationFailureStands(t.ContentRef(620)),
    new k.FinalizationNeedsEvaluation(t.ContentRef(620)),
  ]) {
    expect(failed.submit(report(1, result))).toEqual(not_current(1));
    expect(failed.submit(report(3, result))).toEqual(not_current(3));
  }
  const passed = passed_once();
  expect(
    passed.submit(
      report(2, new k.FinalizationFailureStands(t.ContentRef(620))),
    ),
  ).toEqual(not_current(2));
});

test("finalization events apply only on the basis they were decided on", () => {
  const passed = passed_once();
  for (const event of [
    new k.TicketFinalizationFailureReworked(...fact(1)),
    new k.TicketFinalizationFailureEscalated(...fact(1)),
  ])
    expect(k.evolve(passed.graph, event)).toBe(passed.graph);
  const withdrawn = passed_once();
  request(withdrawn, 1, 610);
  withdrawn.submit(invalidate(1, 620, 2));
  expect(finalization(withdrawn).basis).toBeInstanceOf(k.WithdrawnVerdict);
  for (const event of [
    new k.TicketFinalizationSucceeded(...fact(2)),
    new k.TicketFinalizationFailureReworked(...fact(2)),
    new k.TicketFinalizationFailureEscalated(...fact(2)),
  ]) {
    expect(k.evolve(withdrawn.graph, event)).toBe(withdrawn.graph);
    expect(
      k.decision_valid(withdrawn.graph, new k.TicketDecided(event, [])),
    ).toBe(false);
  }
  expect(() =>
    k.evolve_checked(
      withdrawn.graph,
      new k.TicketFinalizationSucceeded(...fact(2)),
    ),
  ).toThrow();
});

test("evaluation events do not cross between a work-opened and a requested evaluation", () => {
  const entries = (evaluator: number, ref: number) => [
    new e.EvaluationReworkEntry(t.EvaluatorKey(evaluator), t.ContentRef(ref)),
  ];
  const failing = (d: b.Driver, ref: number) => {
    const command = b.evaluator_result_command(
      d.graph,
      1,
      ref,
      new e.EvaluatorFail(),
    );
    if (!(command instanceof k.ReportTaskTerminal))
      throw new Error("no report");
    return command.report;
  };
  const opened = evaluating();
  pass(opened, 601);
  expect(
    k.evolve(
      opened.graph,
      new k.TicketEvaluationFailureReturned(T1, failing(opened, 602)),
    ),
  ).toBe(opened.graph);
  expect(
    k.evolve(
      opened.graph,
      new k.TicketEvaluationWithdrawn(
        T1,
        t.CycleNumber(1),
        t.Round(1),
        t.ContentRef(620),
      ),
    ),
  ).toBe(opened.graph);
  const requested = passed_once();
  request(requested, 1, 610);
  pass(requested, 611);
  const last = failing(requested, 612);
  for (const event of [
    new k.TicketEvaluationReworkStarted(T1, last, entries(12, 612)),
    new k.TicketEvaluationFailureEscalated(T1, last, entries(12, 612)),
    new k.TicketEvaluationFailureInvalidated(T1, last, t.ContentRef(630)),
    new k.TicketEvaluationInvalidated(T1, t.CycleNumber(1), t.ContentRef(630)),
    new k.TicketEvaluationWithdrawn(
      T1,
      t.CycleNumber(1),
      t.Round(3),
      t.ContentRef(630),
    ),
    new k.TicketEvaluationWithdrawn(
      T1,
      t.CycleNumber(2),
      t.Round(2),
      t.ContentRef(630),
    ),
  ])
    expect(k.evolve(requested.graph, event)).toBe(requested.graph);
  expect(
    k.evolve(requested.graph, new k.TicketEvaluationFailureReturned(T1, last)),
  ).not.toBe(requested.graph);
  expect(
    k.evolve(
      requested.graph,
      new k.TicketEvaluationWithdrawn(
        T1,
        t.CycleNumber(1),
        t.Round(2),
        t.ContentRef(630),
      ),
    ),
  ).not.toBe(requested.graph);
});

test("an evaluator report is current only for its own round", () => {
  const driver = passed_once();
  request(driver, 1, 610);
  const current = b.evaluator_obligation(driver.graph, 1).task;
  if (!(current instanceof t.EvaluationTaskId)) throw new Error("no evaluator");
  for (const round of [1, 3]) {
    const other = new t.EvaluationTaskId(
      current.ticket,
      current.work_cycle,
      t.Round(round),
      current.stage,
      current.generation,
      current.evaluator,
    );
    const refusal = new k.TicketRefused(new k.TaskNotCurrent(T1, other));
    expect(
      driver.submit(
        b.terminal_command(
          T1,
          new t.TaskProcessFailed(new t.TaskFailure(other, t.ContentRef(620))),
        ),
      ),
    ).toEqual(refusal);
    expect(
      driver.submit(
        new k.ReportTaskTerminal(
          new k.EvaluationResultReport(
            T1,
            new t.ValidatedTaskResult(
              new t.TaskObligation(other, b.EVALUATOR, t.ContextRef(501)),
              t.ContentRef(621),
            ),
            new e.EvaluatorFail(),
          ),
        ),
      ),
    ).toEqual(refusal);
  }
});

test("a finalization may be revoked on any basis but a pass", () => {
  const passed = passed_once();
  expect(passed.submit(new k.RevokeTicket(T1))).toEqual(
    new k.TicketRefused(new k.TicketNotRevocable(T1)),
  );
  expect(k.evolve(passed.graph, new k.TicketRevoked(T1))).toBe(passed.graph);
  const withdrawn = passed_once();
  request(withdrawn, 1, 610);
  withdrawn.submit(invalidate(1, 620, 2));
  for (const driver of [failed_twice(), withdrawn]) {
    const decision = driver.submit(new k.RevokeTicket(T1));
    expect(decision).toEqual(new k.TicketDecided(new k.TicketRevoked(T1), []));
    expect(k.decision_valid(driver.prior_graph, decision)).toBe(true);
    expect(state_of(driver)).toBeInstanceOf(k.Revoked);
    expect(
      driver.submit(
        report(2, new k.FinalizationNeedsEvaluation(t.ContentRef(630))),
      ),
    ).toEqual(not_current(2));
  }
});

test("a decision obliges every task it starts and every finalization it opens", () => {
  const without = (d: k.TicketDecision, kind: string) => {
    if (!(d instanceof k.TicketDecided)) throw new Error("not decided");
    return new k.TicketDecided(
      d.event,
      d.obligations.filter((o) => o.kind !== kind),
    );
  };
  const driver = passed_once();
  const requested = request(driver, 1, 610);
  expect(k.decision_valid(driver.prior_graph, requested)).toBe(true);
  expect(
    k.decision_valid(driver.prior_graph, without(requested, "ExecuteTask")),
  ).toBe(false);
  const withdrawn = driver.submit(invalidate(1, 620, 2));
  expect(k.decision_valid(driver.prior_graph, withdrawn)).toBe(true);
  expect(
    k.decision_valid(driver.prior_graph, without(withdrawn, "FinalizeTicket")),
  ).toBe(false);
  request(driver, 2, 630);
  fail(driver, 631);
  const returned = pass(driver, 632);
  expect(k.decision_valid(driver.prior_graph, returned)).toBe(true);
  expect(
    k.decision_valid(driver.prior_graph, without(returned, "FinalizeTicket")),
  ).toBe(false);
  // An event that does not apply to the state it was decided in is no
  // decision at all: this one is addressed to an operation that is not the
  // current one, and nothing else about it is wrong.
  expect(finalization(driver).generation).toBe(3);
  expect(
    k.decision_valid(
      driver.graph,
      new k.TicketDecided(new k.TicketFinalizationUnavailable(...fact(2)), []),
    ),
  ).toBe(false);
  expect(
    k.decision_valid(
      driver.graph,
      new k.TicketDecided(new k.TicketFinalizationUnavailable(...fact(3)), []),
    ),
  ).toBe(true);
});

test("an obligation is the whole obligation of what the decision started", () => {
  const driver = passed_once();
  const requested = request(driver, 1, 610);
  if (!(requested instanceof k.TicketDecided)) throw new Error("not decided");
  const [first, second] = requested.obligations;
  if (!(first instanceof k.ExecuteTask) || !(second instanceof k.ExecuteTask))
    throw new Error("no tasks");
  const elsewhere = new k.ExecuteTask(
    second.ticket,
    new t.TaskObligation(
      second.task.task,
      second.task.definition,
      t.ContextRef(second.task.context_ref + 1),
    ),
  );
  expect(
    k.decision_valid(
      driver.prior_graph,
      new k.TicketDecided(requested.event, [first, elsewhere]),
    ),
  ).toBe(false);
  // A task that was already awaited is not started again.
  const progressed = pass(driver, 611);
  if (!(progressed instanceof k.TicketDecided)) throw new Error("not decided");
  expect(progressed.obligations).toEqual([]);
  expect(k.decision_valid(driver.prior_graph, progressed)).toBe(true);
  expect(
    k.decision_valid(
      driver.prior_graph,
      new k.TicketDecided(progressed.event, [second]),
    ),
  ).toBe(false);
  // A finalization is obliged under the ticket's own configuration.
  pass(driver, 612);
  const passed = pass(driver, 613);
  if (!(passed instanceof k.TicketDecided)) throw new Error("not decided");
  const [finalize] = passed.obligations;
  if (!(finalize instanceof k.FinalizeTicket)) throw new Error("no finalize");
  expect(k.decision_valid(driver.prior_graph, passed)).toBe(true);
  expect(
    k.decision_valid(
      driver.prior_graph,
      new k.TicketDecided(passed.event, [
        new k.FinalizeTicket(
          finalize.ticket,
          finalize.finalization,
          t.ContentRef(finalize.configuration + 1),
        ),
      ]),
    ),
  ).toBe(false);
});

test("a finalization report is current only for its own work cycle", () => {
  const driver = passed_once();
  driver.submit(report(1, new k.FinalizationNeedsWork(t.ContentRef(620))));
  driver.submit(b.work_result_command(driver.graph, 1, 621));
  pass(driver, 622);
  pass(driver, 623);
  pass(driver, 624);
  const operation = finalization(driver);
  expect([operation.work_cycle, operation.generation]).toEqual([2, 1]);
  expect(
    driver.submit(report(1, new k.FinalizationSucceeded(t.ContentRef(630)))),
  ).toEqual(not_current(1));
  expect(
    k.evolve(driver.graph, new k.TicketFinalizationSucceeded(...fact(1))),
  ).toBe(driver.graph);
  const done = driver.submit(
    new k.ReportFinalizationResult(
      new k.FinalizationResultReport(
        T1,
        t.CycleNumber(2),
        t.Generation(1),
        new k.FinalizationSucceeded(t.ContentRef(630)),
      ),
    ),
  );
  expect(k.decision_valid(driver.prior_graph, done)).toBe(true);
  expect(state_of(driver)).toBeInstanceOf(k.Done);
});

test("an operation's origin and basis are held to its round", () => {
  const first = passed_once();
  const reshaped = (
    d: b.Driver,
    origin: e.EvaluationOrigin,
    basis: k.FinalizationBasis,
  ) =>
    with_operation(
      d,
      (o) =>
        new k.FinalizationOperation(
          o.work_cycle,
          o.round,
          o.generation,
          o.input,
          o.source,
          origin,
          basis,
        ),
    );
  // Only a requested round, which is never round 1, can be withdrawn.
  expect(
    k.graph_invariant(
      reshaped(first, new e.OpenedByWork(), new k.WithdrawnVerdict()),
    ),
  ).toBe(false);
  // A resumed round 1 is still round 1, so no request opened it.
  first.submit(
    report(1, new k.FinalizationResultUnavailable(t.ContentRef(620))),
  );
  first.submit(new k.ResumeTicket(T1));
  expect([finalization(first).round, finalization(first).generation]).toEqual([
    1, 2,
  ]);
  expect(k.graph_invariant(first.graph)).toBe(true);
  expect(
    k.graph_invariant(
      reshaped(
        first,
        new e.Requested(t.Generation(1), t.ContentRef(610)),
        new k.PassedVerdict(),
      ),
    ),
  ).toBe(false);
});

const equal_operations = (d: b.Driver) => {
  const one = d.graph.tickets.get(T1)!.state,
    three = d.graph.tickets.get(t.TicketId(3))!.state;
  return (
    one instanceof k.Finalization &&
    three instanceof k.Finalization &&
    t.equal(one.operation, three.operation)
  );
};

test("a decision about one ticket owes nothing for another that is finalizing", () => {
  const driver = passed_once();
  for (const command of [new k.CreateTicket(b.released(3)), b.dispatch(3)]) {
    const decision = driver.submit(command);
    expect(decision).toBeInstanceOf(k.TicketDecided);
    expect(k.decision_valid(driver.prior_graph, decision)).toBe(true);
  }
  // The other ticket reaches the very same operation, and its finalization
  // is owed to it, not to the one already waiting.
  driver.submit(
    new k.ReportTaskTerminal(
      new k.WorkResultReport(
        t.TicketId(3),
        new t.ValidatedTaskResult(
          b.work_obligation(driver.graph, 3),
          finalization(driver).input,
        ),
        finalization(driver).source,
      ),
    ),
  );
  const third = (ref: number) =>
    driver.submit(
      b.evaluator_result_command(driver.graph, 3, ref, new e.EvaluatorPass()),
    );
  third(601);
  third(602);
  const passed = third(603);
  if (!(passed instanceof k.TicketDecided)) throw new Error("not decided");
  const [finalize] = passed.obligations;
  if (!(finalize instanceof k.FinalizeTicket)) throw new Error("no finalize");
  expect(equal_operations(driver)).toBe(true);
  expect(k.decision_valid(driver.prior_graph, passed)).toBe(true);
  expect(
    k.decision_valid(
      driver.prior_graph,
      new k.TicketDecided(passed.event, [
        new k.FinalizeTicket(T1, finalize.finalization, finalize.configuration),
      ]),
    ),
  ).toBe(false);
});

test("a disposition the domain does not recognise escalates a failed evaluation", () => {
  const driver = evaluating();
  fail(driver, 601);
  const decision = driver.submit(
    b.evaluator_result_command(driver.graph, 1, 602, new e.EvaluatorPass()),
    () => ({ kind: "Unrecognised" }) as unknown as k.FailureDisposition,
  );
  if (!(decision instanceof k.TicketDecided)) throw new Error("not decided");
  expect(decision.event).toBeInstanceOf(k.TicketEvaluationFailureEscalated);
  expect(k.decision_valid(driver.prior_graph, decision)).toBe(true);
  expect(state_of(driver)).toBeInstanceOf(k.Escalated);
});

test("a finalization completes after any number of requested evaluations", () => {
  const driver = passed_once();
  for (let generation = 1; generation <= 5; generation++) {
    request(driver, generation, 700 + generation);
    pass(driver, 711);
    pass(driver, 712);
    pass(driver, 713);
  }
  expect([finalization(driver).round, finalization(driver).generation]).toEqual(
    [6, 6],
  );
  expect(driver.graph.tickets.get(T1)!.work_cycles_started).toBe(1);
  const done = driver.submit(
    report(6, new k.FinalizationSucceeded(t.ContentRef(720))),
  );
  expect(k.decision_valid(driver.prior_graph, done)).toBe(true);
  expect(state_of(driver)).toBeInstanceOf(k.Done);
});
