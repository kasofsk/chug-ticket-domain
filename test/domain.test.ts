import { expect, test } from "vitest";
import * as t from "../src/task.js";
import * as e from "../src/evaluation.js";
import * as k from "../src/ticket.js";
import * as b from "../src/testing.js";
const tid = new t.WorkTaskId(t.TicketId(1), t.CycleNumber(1));
const obligation = new t.TaskObligation(tid, b.WORK, b.source(1), []);
const result = (
  outputs: readonly t.OutputRef[] = [],
  findings: readonly t.ResultFinding[] = [],
) =>
  new t.ValidatedTaskResult(obligation, t.ContentRef(1), outputs, 1, findings);
test.each([0, -1, -100])("identities reject absent parts %s", (n) => {
  expect(() => new t.WorkTaskId(t.TicketId(n), t.CycleNumber(1))).toThrow();
  expect(() => new t.WorkTaskId(t.TicketId(1), t.CycleNumber(n))).toThrow();
  for (let i = 0; i < 5; i++) {
    const p = [1, 1, 1, 1, 1];
    p[i] = n;
    expect(
      () =>
        new t.EvaluationTaskId(
          t.TicketId(p[0]!),
          t.CycleNumber(p[1]!),
          t.StageKey(p[2]!),
          t.Generation(p[3]!),
          t.EvaluatorKey(p[4]!),
        ),
    ).toThrow();
  }
});
test("task references and obligations enforce repository contract", () => {
  for (let i = 0; i < 4; i++) {
    const p = [1, 1, 1, 1];
    p[i] = 0;
    expect(
      () =>
        new t.TaskDefinition(
          t.ContentRef(p[0]!),
          t.ContentRef(p[1]!),
          new t.ExecutionRequirements(
            t.ContentRef(p[2]!),
            new t.ReadRepository(),
          ),
          t.ContentRef(p[3]!),
        ),
    ).toThrow();
  }
  expect(
    () =>
      new t.TaskObligation(
        tid,
        b.WORK,
        new t.WorkspaceSource(t.ContentRef(2), t.Digest(1)),
        [],
      ),
  ).toThrow();
  expect(() => new t.TaskObligation(tid, b.WORK, b.source(0), [])).toThrow();
  expect(() => new t.TaskFailure(tid, t.ContentRef(0))).toThrow();
  expect(t.reads_repository(b.EVALUATOR, t.ContentRef(1))).toBe(true);
  expect(t.publishes_repository_result(b.WORK, t.ContentRef(1))).toBe(true);
  expect(t.reads_repository(b.WORK, t.ContentRef(1))).toBe(false);
});
test("result findings enforce presence uniqueness and bound", () => {
  expect(() => new t.ResultFinding(0, t.ContentRef(1))).toThrow();
  expect(() => new t.ResultFinding(1, t.ContentRef(0))).toThrow();
  expect(() =>
    result(
      [],
      Array.from(
        { length: 33 },
        (_, i) => new t.ResultFinding(i + 1, t.ContentRef(1)),
      ),
    ),
  ).toThrow();
  expect(() =>
    result(
      [],
      [
        new t.ResultFinding(1, t.ContentRef(1)),
        new t.ResultFinding(1, t.ContentRef(2)),
      ],
    ),
  ).toThrow();
  expect(
    result(
      [],
      Array.from(
        { length: 32 },
        (_, i) => new t.ResultFinding(i + 1, t.ContentRef(1)),
      ),
    ).findings,
  ).toHaveLength(32);
  expect(
    () => new t.ValidatedTaskResult(obligation, t.ContentRef(0), [], 1, []),
  ).toThrow();
});
test("only one valid output on the required repository is exact", () => {
  expect(t.exact_git_output(result())).toBeNull();
  const output = new t.GitOutput(b.source(5));
  expect(t.exact_git_output(result([output]))).toEqual(b.source(5));
  expect(t.exact_git_output(result([output, output]))).toBeNull();
  expect(t.exact_git_output(result([new t.GitOutput(b.source(0))]))).toBeNull();
  expect(
    t.exact_git_output(
      result([
        new t.GitOutput(new t.WorkspaceSource(t.ContentRef(2), t.Digest(5))),
      ]),
    ),
  ).toBeNull();
});
test("plan keys and stage contents are validated", () => {
  expect(e.validate_plan(b.PLAN, t.ContentRef(1))).toBe(true);
  expect(e.validate_plan(b.PLAN, t.ContentRef(2))).toBe(false);
  for (const plan of [
    new e.EvaluationPlan([]),
    new e.EvaluationPlan([
      new e.StageDefinition(t.StageKey(0), b.PLAN.stages[0]!.evaluators),
    ]),
    new e.EvaluationPlan([b.PLAN.stages[0]!, b.PLAN.stages[0]!]),
    new e.EvaluationPlan([new e.StageDefinition(t.StageKey(1), [])]),
    new e.EvaluationPlan([
      new e.StageDefinition(t.StageKey(1), [
        b.PLAN.stages[0]!.evaluators[0]!,
        b.PLAN.stages[0]!.evaluators[0]!,
      ]),
    ]),
  ])
    expect(e.plan_valid(plan)).toBe(false);
  expect(() =>
    e.begin(
      t.CycleNumber(1),
      new e.EvaluationInput(t.TicketId(1), t.ContentRef(1), b.source(1)),
      new e.EvaluationPlan([]),
    ),
  ).toThrow();
});
test("findings survive failed evaluation into next work context", () => {
  const d = new b.Driver();
  d.submit(new k.CreateTicket(b.released(1)));
  d.submit(b.dispatch(1));
  d.submit(b.work_result_command(d.graph, 1, 501));
  const findings = [new t.ResultFinding(7, t.ContentRef(77))];
  d.submit(b.evaluator_result_command(d.graph, 1, 502, -1, findings));
  d.submit(b.evaluator_result_command(d.graph, 1, 503, 1));
  const s = d.graph.tickets.get(t.TicketId(1))!.state;
  expect(s).toBeInstanceOf(k.Work);
  if (!(s instanceof k.Work)) throw new Error();
  expect(s.execution.input.cause).toEqual(
    new k.EvaluationRework([
      new e.EvaluationReworkEntry(
        t.EvaluatorKey(11),
        new e.SummaryReason(-1),
        t.ContentRef(502),
        [new e.EvaluationFinding(7, t.ContentRef(77))],
      ),
    ]),
  );
  expect(
    k.work_context(k.retry_work_input(s.execution.input, t.ContentRef(900))),
  ).toEqual([101, 102, 103, 502, 900]);
});
test("resume retries only blocked evaluators with a new generation", () => {
  const d = new b.Driver();
  d.submit(new k.CreateTicket(b.released(1)));
  d.submit(b.dispatch(1));
  d.submit(b.work_result_command(d.graph, 1, 501));
  d.submit(b.evaluator_result_command(d.graph, 1, 502, 1));
  const stale = b.evaluator_result_command(d.graph, 1, 503, 1);
  d.submit(b.failure_command(d.graph, 1, 900, false, true));
  d.submit(new k.ResumeTicket(t.TicketId(1)));
  const o = b.evaluator_obligation(d.graph, 1);
  expect(o.task).toEqual(
    new t.EvaluationTaskId(
      t.TicketId(1),
      t.CycleNumber(1),
      t.StageKey(10),
      t.Generation(2),
      t.EvaluatorKey(12),
    ),
  );
  expect(d.submit(stale)).toBeInstanceOf(k.TicketRefused);
  expect(k.graph_invariant(d.graph)).toBe(true);
});
test("checked evolution rejects mismatched events and duplicate obligations", () => {
  const d = new b.Driver();
  expect(() =>
    k.evolve_checked(d.graph, new k.TicketRevoked(t.TicketId(1))),
  ).toThrow();
  d.submit(new k.CreateTicket(b.released(1)));
  expect(() =>
    k.evolve_checked(
      d.graph,
      new k.TicketWorkResultAccepted(t.TicketId(1), result()),
    ),
  ).toThrow();
  const decision = k.decide(d.graph, b.dispatch(1), k.rework_policy);
  if (!(decision instanceof k.TicketDecided)) throw new Error();
  expect(
    k.decision_valid(
      d.graph,
      new k.TicketDecided(decision.event, [
        ...decision.obligations,
        ...decision.obligations,
      ]),
    ),
  ).toBe(false);
});
test("graph invariant rejects missing dependencies cycles identity and revision", () => {
  const make = (id: number, deps: number[], revision = 1) =>
    new k.Ticket(
      b.released(id, new Set(deps.map(t.TicketId))),
      revision,
      0,
      new k.Pending(),
    );
  expect(
    k.graph_invariant(
      new k.TicketGraph(new Map([[t.TicketId(1), make(1, [2])]])),
    ),
  ).toBe(false);
  expect(
    k.graph_invariant(
      new k.TicketGraph(
        new Map([
          [t.TicketId(1), make(1, [2])],
          [t.TicketId(2), make(2, [1])],
        ]),
      ),
    ),
  ).toBe(false);
  expect(
    k.graph_invariant(
      new k.TicketGraph(new Map([[t.TicketId(2), make(1, [])]])),
    ),
  ).toBe(false);
  expect(
    k.graph_invariant(
      new k.TicketGraph(new Map([[t.TicketId(1), make(1, [], 0)]])),
    ),
  ).toBe(false);
});
test("seeded walks preserve invariants and exercise every event", () => {
  let seed = 0x127892ab;
  const random = () => {
    seed ^= seed << 13;
    seed ^= seed >>> 17;
    seed ^= seed << 5;
    return seed >>> 0;
  };
  const seen = new Set<string>();
  for (let run = 0; run < 100; run++) {
    const d = new b.Driver();
    d.submit(new k.CreateTicket(b.released(1)));
    seen.add("TicketCreated");
    for (let step = 0; step < 200; step++) {
      const ticket = d.graph.tickets.get(t.TicketId(1))!,
        s = ticket.state;
      let command: k.TicketCommand;
      const n = random() % 8;
      if (s instanceof k.Pending)
        command =
          n < 2
            ? new k.UpdateTicket(
                t.TicketId(1),
                ticket.revision,
                b.released(1, new Set(), true),
              )
            : b.dispatch(1);
      else if (s instanceof k.Work)
        command =
          n < 5
            ? b.work_result_command(d.graph, 1, 501)
            : b.failure_command(d.graph, 1, 900, true, n === 6);
      else if (s instanceof k.Evaluation)
        command =
          n < 6
            ? b.evaluator_result_command(d.graph, 1, 502, n < 4 ? 1 : -1)
            : b.failure_command(d.graph, 1, 900, false, n === 6);
      else if (s instanceof k.Finalization)
        command = b.finalization_command(
          d.graph,
          1,
          n < 4
            ? new k.FinalizationSucceeded(t.ContentRef(505))
            : n < 6
              ? new k.FinalizationNeedsWork(t.ContentRef(506))
              : new k.FinalizationResultUnavailable(t.ContentRef(507)),
        );
      else if (s instanceof k.Escalated)
        command = new k.ResumeTicket(t.TicketId(1));
      else break;
      if (random() % 71 === 0) command = new k.RevokeTicket(t.TicketId(1));
      const decision = d.submit(
        command,
        random() % 3 === 0
          ? () => new k.EscalateEvaluationFailure()
          : k.rework_policy,
      );
      expect(k.decision_valid(d.prior_graph, decision)).toBe(true);
      expect(k.graph_invariant(d.graph)).toBe(true);
      if (decision instanceof k.TicketDecided) seen.add(decision.event.kind);
    }
  }
  expect([...seen].sort()).toEqual(
    [
      "TicketCreated",
      "TicketUpdated",
      "TicketDispatched",
      "TicketRevoked",
      "TicketWorkResumed",
      "TicketEvaluationResumed",
      "TicketFinalizationResumed",
      "TicketWorkResultAccepted",
      "TicketWorkProcessFailed",
      "TicketWorkExecutionUnavailable",
      "TicketEvaluationProgressed",
      "TicketEvaluationPassed",
      "TicketEvaluationReworkStarted",
      "TicketEvaluationFailureEscalated",
      "TicketEvaluationBlocked",
      "TicketFinalizationSucceeded",
      "TicketFinalizationNeedsWork",
      "TicketFinalizationUnavailable",
    ].sort(),
  );
});
test("domain copies input arrays and maps", () => {
  const context = [t.ContentRef(1)];
  const o = new t.TaskObligation(tid, b.WORK, b.source(1), context);
  context.push(t.ContentRef(2));
  expect(o.context).toEqual([1]);
  expect(Object.isFrozen(o.context)).toBe(true);
  const tickets = new Map<t.TicketId, k.Ticket>();
  const graph = new k.TicketGraph(tickets);
  tickets.set(
    t.TicketId(1),
    new k.Ticket(b.released(1), 1, 0, new k.Pending()),
  );
  expect(graph.tickets.size).toBe(0);
});

test("publishing work without a Git output reaches the refusal rule", () => {
  const driver = new b.Driver();
  driver.submit(new k.CreateTicket(b.released(1)));
  driver.submit(b.dispatch(1));
  const work = b.work_obligation(driver.graph, 1);
  const produced = new t.ValidatedTaskResult(
    work,
    t.ContentRef(101),
    [],
    1,
    [],
  );
  const before = driver.graph;
  expect(
    driver.submit(
      b.terminal_command(t.TicketId(1), new t.TaskResultProduced(produced)),
    ),
  ).toEqual(
    new k.TicketRefused(new k.WorkResultMissingExactGitOutput(t.TicketId(1))),
  );
  expect(driver.graph).toEqual(before);
  expect(() =>
    k.evolve_checked(
      before,
      new k.TicketWorkResultAccepted(t.TicketId(1), produced),
    ),
  ).toThrow();
});
