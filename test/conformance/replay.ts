import * as t from "../../src/task.js";
import * as k from "../../src/ticket.js";
import * as e from "../../src/evaluation.js";
import * as b from "../../src/testing.js";
import { DecisionStep, NO_DECISION, Value, Variant } from "../../src/itf.js";
import { ConversionError, decision_from_itf } from "./convert.js";
export {
  ConversionError,
  decision_from_itf,
  graph_from_itf,
} from "./convert.js";
export class Reconstructed {
  constructor(
    readonly command: k.TicketCommand,
    readonly policy: k.EvaluationFailurePolicy,
    readonly origin: "action" | "event",
  ) {}
}
export class EvolveOnly {
  constructor(readonly reason: string) {}
}
/** The finalizer's walk started again from `finalizing_graph`: no command. */
export class Restarted {}
export type Reconstruction = Reconstructed | EvolveOnly | Restarted;
export const RESTART = "restartFinalizing";
/** `finalizingGraph` of `ticket_tests.qnt`: a ticket whose first evaluation passed. */
export function finalizing_graph(): k.TicketGraph {
  const driver = new b.Driver();
  driver.submit(new k.CreateTicket(b.released(1)));
  driver.submit(b.dispatch(1));
  driver.submit(b.work_result_command(driver.graph, 1, 501));
  for (let passed = 0; passed < 3; passed++)
    driver.submit(
      b.evaluator_result_command(driver.graph, 1, 502, new e.EvaluatorPass()),
    );
  return driver.graph;
}
type Picks = Record<string, Value> | null;
function picked(picks: Picks, name: string): Value | undefined {
  const held = picks?.[name];
  return held instanceof Variant && held.tag === "Some"
    ? held.value
    : undefined;
}
function pick(picks: Picks, name: string): Value {
  const value = picked(picks, name);
  if (value === undefined)
    throw new ConversionError(`model step picked no ${name}`);
  return value;
}
function pick_variant(picks: Picks, name: string): Variant {
  const value = pick(picks, name);
  if (!(value instanceof Variant))
    throw new ConversionError(`picked ${name} is not a variant`);
  return value;
}
function picked_result(picks: Picks): k.FinalizationResult {
  const result = pick_variant(picks, "result");
  if (typeof result.value !== "number")
    throw new ConversionError("picked result carries no evidence");
  const evidence = t.ContentRef(result.value);
  switch (result.tag) {
    case "FinalizationSucceeded":
      return new k.FinalizationSucceeded(evidence);
    case "FinalizationNeedsEvaluation":
      return new k.FinalizationNeedsEvaluation(evidence);
    case "FinalizationFailureStands":
      return new k.FinalizationFailureStands(evidence);
    default:
      throw new ConversionError(`unknown picked result ${result.tag}`);
  }
}
/** `anotherCycle` of `ticket_tests.qnt`. */
function another_cycle(cycle: number): number {
  return cycle > 1 ? cycle - 1 : cycle + 1;
}
/** `drifted` of `ticket_tests.qnt`: the address a stray command names. */
function drifted(
  cycle: number,
  ordinal: number,
  picks: Picks,
): { cycle: number; ordinal: number } {
  const drift = pick_variant(picks, "drift").tag;
  switch (drift) {
    case "OnTarget":
      return { cycle, ordinal };
    case "AnotherCycle":
      return { cycle: another_cycle(cycle), ordinal };
    case "Earlier":
      return { cycle, ordinal: ordinal > 1 ? ordinal - 1 : ordinal + 2 };
    case "Later":
      return { cycle, ordinal: ordinal + 1 };
    default:
      throw new ConversionError(`unknown picked drift ${drift}`);
  }
}
function first_ticket(prior: k.TicketGraph): k.Ticket {
  const ticket = prior.tickets.get(t.TicketId(1));
  if (!ticket) throw new ConversionError("a stray step needs ticket 1");
  return ticket;
}
/** `strayCycle` of `ticket_tests.qnt`. */
function stray_cycle(ticket: k.Ticket): number {
  return ticket.work_cycles_started > 0 ? ticket.work_cycles_started : 1;
}
function stray_finalization(prior: k.TicketGraph, picks: Picks) {
  const ticket = first_ticket(prior),
    state = ticket.state;
  return state instanceof k.Finalization
    ? drifted(state.operation.work_cycle, state.operation.generation, picks)
    : drifted(stray_cycle(ticket), 1, picks);
}
function stray_invalidation(prior: k.TicketGraph, picks: Picks) {
  const ticket = first_ticket(prior),
    state = ticket.state,
    held =
      state instanceof k.Evaluation
        ? state.evaluation
        : state instanceof k.Escalated &&
            state.escalation instanceof k.EvaluationBlockedEscalated
          ? state.escalation.evaluation
          : null;
  return held
    ? drifted(held.work_cycle, held.round, picks)
    : drifted(stray_cycle(ticket), 1, picks);
}
/** `driftedTask(strayTaskBase(ticket), taskDrift)` of `ticket_tests.qnt`. */
function stray_task(prior: k.TicketGraph, picks: Picks): t.EvaluationTaskId {
  const ticket = first_ticket(prior),
    current =
      ticket.state instanceof k.Evaluation
        ? e.current_task_obligations(ticket.state.evaluation)[0]?.task
        : undefined,
    base =
      current instanceof t.EvaluationTaskId
        ? current
        : new t.EvaluationTaskId(
            t.TicketId(1),
            t.CycleNumber(stray_cycle(ticket)),
            t.Round(1),
            t.StageKey(10),
            t.Generation(1),
            t.EvaluatorKey(11),
          ),
    drift = pick_variant(picks, "taskDrift").tag,
    task = (change: {
      cycle?: number;
      round?: number;
      stage?: number;
      generation?: number;
      evaluator?: number;
    }) =>
      new t.EvaluationTaskId(
        base.ticket,
        t.CycleNumber(change.cycle ?? base.work_cycle),
        t.Round(change.round ?? base.round),
        t.StageKey(change.stage ?? base.stage),
        t.Generation(change.generation ?? base.generation),
        t.EvaluatorKey(change.evaluator ?? base.evaluator),
      );
  switch (drift) {
    case "SameTask":
      return base;
    case "TaskOfAnotherCycle":
      return task({ cycle: another_cycle(base.work_cycle) });
    case "TaskOfAnotherRound":
      return task({ round: base.round > 1 ? base.round - 1 : 2 });
    case "TaskOfAnotherStage":
      return task({ stage: base.stage === 10 ? 20 : 10 });
    case "TaskOfAnotherGeneration":
      return task({ generation: base.generation + 1 });
    case "TaskOfAnotherEvaluator":
      return task({ evaluator: base.evaluator === 11 ? 12 : 11 });
    default:
      throw new ConversionError(`unknown picked task drift ${drift}`);
  }
}
function stray_evaluator_report(
  prior: k.TicketGraph,
  picks: Picks,
): k.TaskTerminalReport {
  const task = stray_task(prior, picks),
    produced = (manifest: number, verdict: e.EvaluationVerdict) =>
      new k.EvaluationResultReport(
        t.TicketId(1),
        new t.ValidatedTaskResult(
          new t.TaskObligation(task, b.EVALUATOR, t.ContextRef(501)),
          t.ContentRef(manifest),
        ),
        verdict,
      ),
    failed = (evidence: number, kind: k.FailureKind) =>
      new k.TerminalFailureReport(
        t.TicketId(1),
        new t.TaskFailure(task, t.ContentRef(evidence)),
        kind,
      ),
    outcome = pick_variant(picks, "outcome").tag;
  switch (outcome) {
    case "StrayFail":
      return produced(608, new e.EvaluatorFail());
    case "StrayProcessFailed":
      return failed(609, new k.ProcessFailure());
    default:
      throw new ConversionError(`unknown picked outcome ${outcome}`);
  }
}
const PICKING = new Set([
  "strayFinalizationOne",
  "strayInvalidateOne",
  "strayEvaluatorOne",
]);
function simulation(
  action: string,
  prior: k.TicketGraph,
  picks: Picks,
): k.TicketCommand {
  switch (action) {
    case "strayFinalizationOne": {
      const address = stray_finalization(prior, picks);
      return new k.ReportFinalizationResult(
        new k.FinalizationResultReport(
          t.TicketId(1),
          t.CycleNumber(address.cycle),
          t.Generation(address.ordinal),
          picked_result(picks),
        ),
      );
    }
    case "strayInvalidateOne": {
      const address = stray_invalidation(prior, picks);
      return new k.InvalidateEvaluation(
        t.TicketId(1),
        t.CycleNumber(address.cycle),
        t.Round(address.ordinal),
        t.ContentRef(606),
      );
    }
    case "strayEvaluatorOne":
      return new k.ReportTaskTerminal(stray_evaluator_report(prior, picks));
    case "createOne":
      return new k.CreateTicket(b.released(1));
    case "createTwo":
      return new k.CreateTicket(b.released(2, new Set([t.TicketId(1)])));
    case "updateOne":
      return new k.UpdateTicket(
        t.TicketId(1),
        prior.tickets.get(t.TicketId(1))?.revision ?? 1,
        b.released(1, new Set(), true),
      );
    case "updateOneOnTwo":
      return new k.UpdateTicket(
        t.TicketId(1),
        prior.tickets.get(t.TicketId(1))?.revision ?? 1,
        b.released(1, new Set([t.TicketId(2)]), true),
      );
    case "updateTwoFree":
    case "updateTwoOnOne":
      return new k.UpdateTicket(
        t.TicketId(2),
        prior.tickets.get(t.TicketId(2))?.revision ?? 1,
        b.released(
          2,
          new Set(action === "updateTwoOnOne" ? [t.TicketId(1)] : []),
          true,
        ),
      );
    case "dispatchOne":
      return b.dispatch(1);
    case "dispatchTwo":
      return b.dispatch(2);
    case "revokeOne":
      return new k.RevokeTicket(t.TicketId(1));
    case "resumeOne":
      return new k.ResumeTicket(t.TicketId(1));
    case "passWorkOne":
      return b.work_result_command(prior, 1, 501);
    case "failWorkOne":
      return b.failure_command(prior, 1, 508, true, false);
    case "unavailableWorkOne":
      return b.failure_command(prior, 1, 509, true, true);
    case "passEvaluatorOne":
      return b.evaluator_result_command(prior, 1, 502, new e.EvaluatorPass());
    case "failEvaluatorOne":
      return b.evaluator_result_command(prior, 1, 503, new e.EvaluatorFail());
    case "unavailableEvaluatorOne":
      return b.failure_command(prior, 1, 504, false, true);
    case "invalidateOne": {
      const s1 = prior.tickets.get(t.TicketId(1))?.state;
      const held =
        s1 instanceof k.Evaluation
          ? s1.evaluation
          : s1 instanceof k.Escalated &&
              s1.escalation instanceof k.EvaluationBlockedEscalated
            ? s1.escalation.evaluation
            : null;
      return held
        ? new k.InvalidateEvaluation(
            t.TicketId(1),
            held.work_cycle,
            held.round,
            t.ContentRef(510),
          )
        : (() => {
            throw new ConversionError("invalidateOne needs an evaluation");
          })();
    }
    case "invalidateFailedEvaluatorOne":
      return b.evaluator_result_command(prior, 1, 511, new e.EvaluatorFail());
    case "completeFinalizationOne":
      return b.finalization_command(
        prior,
        1,
        new k.FinalizationSucceeded(t.ContentRef(505)),
      );
    case "reworkFinalizationOne":
      return b.finalization_command(
        prior,
        1,
        new k.FinalizationNeedsWork(t.ContentRef(506)),
      );
    case "unavailableFinalizationOne":
      return b.finalization_command(
        prior,
        1,
        new k.FinalizationResultUnavailable(t.ContentRef(507)),
      );
    case "requestEvaluationOne":
      return b.finalization_command(
        prior,
        1,
        new k.FinalizationNeedsEvaluation(t.ContentRef(512)),
      );
    case "failureStandsOne":
    case "failureStandsEscalatedOne":
    case "failureStandsInvalidatedOne":
      return b.finalization_command(
        prior,
        1,
        new k.FinalizationFailureStands(
          t.ContentRef(
            action === "failureStandsOne"
              ? 513
              : action === "failureStandsEscalatedOne"
                ? 514
                : 515,
          ),
        ),
      );
    default:
      throw new ConversionError(`unknown step alternative ${action}`);
  }
}
function finalization_report(
  e: {
    ticket: t.TicketId;
    work_cycle: t.CycleNumber;
    generation: t.Generation;
  },
  result: k.FinalizationResult,
): k.TicketCommand {
  return new k.ReportFinalizationResult(
    new k.FinalizationResultReport(
      e.ticket,
      e.work_cycle,
      e.generation,
      result,
    ),
  );
}
function event_command(e: k.TicketEvent): Reconstructed {
  let command: k.TicketCommand;
  let policy = k.rework_policy;
  switch (e.kind) {
    case "TicketCreated":
      command = new k.CreateTicket(e.definition);
      break;
    case "TicketUpdated":
      command = new k.UpdateTicket(e.ticket, e.revision - 1, e.definition);
      break;
    case "TicketDispatched":
      command = new k.DispatchTicket(e.ticket, e.source);
      break;
    case "TicketRevoked":
      command = new k.RevokeTicket(e.ticket);
      break;
    case "TicketWorkResumed":
    case "TicketEvaluationResumed":
    case "TicketFinalizationResumed":
      command = new k.ResumeTicket(e.ticket);
      break;
    case "TicketWorkResultAccepted":
      command = new k.ReportTaskTerminal(
        new k.WorkResultReport(e.ticket, e.result, e.accepted_source_ref),
      );
      break;
    case "TicketWorkProcessFailed":
      command = b.terminal_command(
        e.ticket,
        new t.TaskProcessFailed(new t.TaskFailure(e.task, e.evidence)),
      );
      break;
    case "TicketWorkExecutionUnavailable":
      command = b.terminal_command(
        e.ticket,
        new t.TaskExecutionUnavailable(new t.TaskFailure(e.task, e.evidence)),
      );
      break;
    case "TicketEvaluationFailureEscalated":
      policy = () => new k.EscalateEvaluationFailure();
      command = new k.ReportTaskTerminal(e.report);
      break;
    case "TicketEvaluationFailureInvalidated": {
      const evidence = e.evidence;
      policy = () => new k.InvalidateEvaluationFailure(evidence);
      command = new k.ReportTaskTerminal(e.report);
      break;
    }
    case "TicketEvaluationInvalidated":
      command = new k.InvalidateEvaluation(
        e.ticket,
        e.work_cycle,
        t.Round(1),
        e.evidence,
      );
      break;
    case "TicketEvaluationWithdrawn":
      command = new k.InvalidateEvaluation(
        e.ticket,
        e.work_cycle,
        e.round,
        e.evidence,
      );
      break;
    case "TicketEvaluationFailureReturned":
      command = new k.ReportTaskTerminal(e.report);
      break;
    case "TicketFinalizationNeedsEvaluation":
      command = finalization_report(
        e,
        new k.FinalizationNeedsEvaluation(e.evidence),
      );
      break;
    case "TicketFinalizationFailureReworked":
      command = finalization_report(
        e,
        new k.FinalizationFailureStands(e.evidence),
      );
      break;
    case "TicketFinalizationFailureEscalated":
      policy = () => new k.EscalateEvaluationFailure();
      command = finalization_report(
        e,
        new k.FinalizationFailureStands(e.evidence),
      );
      break;
    case "TicketEvaluationProgressed":
    case "TicketEvaluationPassed":
    case "TicketEvaluationBlocked":
    case "TicketEvaluationReworkStarted":
      command = new k.ReportTaskTerminal(e.report);
      break;
    case "TicketFinalizationSucceeded":
    case "TicketFinalizationNeedsWork":
    case "TicketFinalizationUnavailable":
      command = new k.ReportFinalizationResult(
        new k.FinalizationResultReport(
          e.ticket,
          e.work_cycle,
          e.generation,
          e instanceof k.TicketFinalizationSucceeded
            ? new k.FinalizationSucceeded(e.evidence)
            : e instanceof k.TicketFinalizationNeedsWork
              ? new k.FinalizationNeedsWork(e.evidence)
              : new k.FinalizationResultUnavailable(e.evidence),
        ),
      );
      break;
  }
  return new Reconstructed(command, policy, "event");
}
export function command_from_step(
  step: DecisionStep,
  prior: k.TicketGraph,
): Reconstruction {
  if (step.action === RESTART) return new Restarted();
  if (step.action !== null) {
    if (
      !PICKING.has(step.action) &&
      Object.keys(step.nondet_picks ?? {}).some(
        (name) => picked(step.nondet_picks, name) !== undefined,
      )
    )
      throw new ConversionError(
        `model step ${step.action} makes no nondeterministic pick`,
      );
    return new Reconstructed(
      simulation(step.action, prior, step.nondet_picks),
      step.action === "invalidateFailedEvaluatorOne" ||
        step.action === "failureStandsInvalidatedOne"
        ? () => new k.InvalidateEvaluationFailure(t.ContentRef(1601))
        : step.action === "failureStandsEscalatedOne"
          ? () => new k.EscalateEvaluationFailure()
          : k.rework_policy,
      "action",
    );
  }
  if (t.equal(step.decision, NO_DECISION))
    return new EvolveOnly(
      "the init sentinel: the scenario asserted inside check(...)",
    );
  const d = decision_from_itf(step.decision);
  return d instanceof k.TicketRefused
    ? new EvolveOnly(`a refusal names no command: ${d.reason.kind}`)
    : event_command(d.event);
}
const INVALIDATING: k.EvaluationFailurePolicy = () =>
  new k.InvalidateEvaluationFailure(t.ContentRef(1601));
const UNRECOGNISED: k.EvaluationFailurePolicy = () =>
  ({ kind: "Unrecognised" }) as unknown as k.FailureDisposition;
/**
 * The policies a decided `FinalizationFailureStands` must not tell apart: any
 * disposition but rework escalates.
 */
export const ESCALATING: readonly k.EvaluationFailurePolicy[] = [
  () => new k.EscalateEvaluationFailure(),
  INVALIDATING,
  UNRECOGNISED,
];
/**
 * What a simulation step shows that the corpus must hold at least once, so
 * that every part of a command replay rebuilds from picks is one some
 * decision in the corpus depends on.
 */
export const REQUIRED_FEATURES = [
  "a stray produced evaluator report is accepted",
  "a stray evaluator failure is accepted",
  "a stray evaluator report is refused during an evaluation",
  "a stray Succeeded is addressed to the current operation",
  "a stray NeedsEvaluation is addressed to the current operation",
  "a stray FailureStands is addressed to the current operation",
  "a stray finalization report is refused as not current during a finalization",
  "a stray finalization report for another work cycle is refused at the current generation",
  "a stray finalization report is refused as not allowed",
  "a stray invalidation is accepted",
  "a stray invalidation is refused during an evaluation",
  "the escalating policy meets a failure that stands",
  "the invalidating policy meets a failure that stands",
  "the walk starts again",
] as const;
type Feature = (typeof REQUIRED_FEATURES)[number];
const ON_TARGET: Record<string, Feature> = {
  FinalizationSucceeded:
    "a stray Succeeded is addressed to the current operation",
  FinalizationNeedsEvaluation:
    "a stray NeedsEvaluation is addressed to the current operation",
  FinalizationFailureStands:
    "a stray FailureStands is addressed to the current operation",
};
export function step_features(
  step: DecisionStep,
  prior: k.TicketGraph,
  decision: k.TicketDecision,
): Feature[] {
  const found: Feature[] = [],
    picks = step.nondet_picks,
    state = prior.tickets.get(t.TicketId(1))?.state,
    decided = decision instanceof k.TicketDecided,
    refusal = decision instanceof k.TicketRefused ? decision.reason.kind : null,
    evaluating =
      state instanceof k.Evaluation ||
      (state instanceof k.Escalated &&
        state.escalation instanceof k.EvaluationBlockedEscalated),
    stands =
      decision instanceof k.TicketDecided &&
      decision.event instanceof k.TicketFinalizationFailureEscalated;
  switch (step.action) {
    case "strayEvaluatorOne":
      if (decided)
        found.push(
          pick_variant(picks, "outcome").tag === "StrayFail"
            ? "a stray produced evaluator report is accepted"
            : "a stray evaluator failure is accepted",
        );
      else if (state instanceof k.Evaluation)
        found.push("a stray evaluator report is refused during an evaluation");
      break;
    case "strayFinalizationOne":
      if (!(state instanceof k.Finalization)) break;
      if (pick_variant(picks, "drift").tag === "OnTarget") {
        const feature = ON_TARGET[pick_variant(picks, "result").tag];
        if (feature) found.push(feature);
      }
      if (refusal === "FinalizationNotCurrent") {
        found.push(
          "a stray finalization report is refused as not current during a finalization",
        );
        if (pick_variant(picks, "drift").tag === "AnotherCycle")
          found.push(
            "a stray finalization report for another work cycle is refused at the current generation",
          );
      }
      if (refusal === "FinalizationResultNotAllowed")
        found.push("a stray finalization report is refused as not allowed");
      break;
    case "strayInvalidateOne":
      if (decided) found.push("a stray invalidation is accepted");
      else if (evaluating)
        found.push("a stray invalidation is refused during an evaluation");
      break;
    case "failureStandsEscalatedOne":
      if (stands)
        found.push("the escalating policy meets a failure that stands");
      break;
    case "failureStandsInvalidatedOne":
      if (stands)
        found.push("the invalidating policy meets a failure that stands");
      break;
    case RESTART:
      found.push("the walk starts again");
      break;
  }
  return found;
}
