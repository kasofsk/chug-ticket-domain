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

test("task definitions require immutable refs and capability names", () => {
  expect(
    () =>
      new t.TaskDefinition(
        t.ContentRef(0),
        t.ContentRef(1),
        new t.ExecutionRequirements(),
        t.ContentRef(1),
      ),
  ).toThrow();
  expect(() => new t.ExecutionRequirements([""])).toThrow();
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
