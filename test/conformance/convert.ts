import { Variant, Value } from "../../src/itf.js";
export class ConversionError extends Error {}
function record(v: Value, fields: readonly string[]): Record<string, Value> {
  if (
    typeof v !== "object" ||
    v === null ||
    Array.isArray(v) ||
    v instanceof Map ||
    v instanceof Set ||
    v instanceof Variant
  )
    throw new ConversionError("expected a record");
  const r = v as Record<string, Value>;
  if (Object.keys(r).sort().join(",") !== [...fields].sort().join(","))
    throw new ConversionError(
      `holds [${Object.keys(r).sort()}], not [${[...fields].sort()}]`,
    );
  return r;
}
function integer(v: Value): number {
  if (typeof v !== "number" || !Number.isSafeInteger(v))
    throw new ConversionError("expected an integer");
  return v;
}
function list(v: Value): readonly Value[] {
  if (!Array.isArray(v)) throw new ConversionError("expected a list");
  return v;
}
function set(v: Value): readonly Value[] {
  if (!(v instanceof Set)) throw new ConversionError("expected a set");
  return [...v];
}
function mapping(v: Value): readonly (readonly [Value, Value])[] {
  if (!(v instanceof Map)) throw new ConversionError("expected a map");
  return [...v];
}
import {
  WorkTaskId,
  EvaluationTaskId,
  TaskId,
  TaskDefinition,
  TaskObligation,
  ValidatedTaskResult,
  TaskFailure,
  TaskResultProduced,
  TaskProcessFailed,
  TaskExecutionUnavailable,
  TaskTerminal,
  TicketId,
  CycleNumber,
  StageKey,
  Generation,
  EvaluatorKey,
  ContentRef,
  ContextRef,
} from "../../src/task.js";
import {
  EvaluatorDefinition,
  StageDefinition,
  EvaluationPlan,
  EvaluationInput,
  EvaluatorPass,
  EvaluatorFail,
  EvaluationVerdict,
  EvaluatorPassed,
  EvaluatorFailed,
  EvaluatorResult,
  Awaiting,
  Produced,
  EvaluatorProcessFailed,
  EvaluatorExecutionUnavailable,
  EvaluatorStatus,
  EvaluationReworkEntry,
  StageRun,
  EvaluationProgress,
  Running,
  EvaluationPassed,
  EvaluationFailed,
  EvaluationBlocked,
  EvaluationState,
  EvaluationInstance,
} from "../../src/evaluation.js";
import {
  InitialWork,
  EvaluationRework,
  FinalizationRework,
  WorkCause,
  WorkInput,
  WorkExecution,
  FinalizationOperation,
  WorkEscalation,
  EvaluationFailureEscalation,
  FinalizationEscalation,
  WorkFailureEscalated,
  WorkExecutionUnavailableEscalated,
  EvaluationFailureEscalated,
  EvaluationBlockedEscalated,
  FinalizationUnavailableEscalated,
  Escalation,
  ReleasedTicket,
  Pending,
  Work,
  Evaluation,
  Finalization,
  Escalated,
  Done,
  Revoked,
  TicketState,
  Ticket,
  TicketGraph,
  WorkResultReport,
  EvaluationResultReport,
  TerminalFailureReport,
  TaskTerminalReport,
  ProcessFailure,
  ExecutionUnavailableFailure,
  TicketAlreadyExists,
  DependenciesNotFound,
  SelfDependency,
  TicketNotFound,
  TicketNotPending,
  TicketIdentityMismatch,
  TicketRevisionStale,
  TicketDependenciesChanged,
  DependenciesIncomplete,
  TicketNotRevocable,
  TicketNotResumable,
  TaskNotCurrent,
  FinalizationNotCurrent,
  TicketRefusal,
  TicketCreated,
  TicketUpdated,
  TicketDispatched,
  TicketRevoked,
  TicketWorkResumed,
  TicketEvaluationResumed,
  TicketFinalizationResumed,
  TicketWorkResultAccepted,
  TicketWorkProcessFailed,
  TicketWorkExecutionUnavailable,
  TicketEvaluationProgressed,
  TicketEvaluationPassed,
  TicketEvaluationReworkStarted,
  TicketEvaluationFailureEscalated,
  TicketEvaluationBlocked,
  TicketFinalizationSucceeded,
  TicketFinalizationNeedsWork,
  TicketFinalizationUnavailable,
  TicketEvent,
  ExecuteTask,
  FinalizeTicket,
  CancelTask,
  Obligation,
  TicketRefused,
  TicketDecided,
  TicketDecision,
} from "../../src/ticket.js";
function parse_TicketId(v: Value): TicketId {
  return TicketId(integer(v));
}
function parse_CycleNumber(v: Value): CycleNumber {
  return CycleNumber(integer(v));
}
function parse_StageKey(v: Value): StageKey {
  return StageKey(integer(v));
}
function parse_Generation(v: Value): Generation {
  return Generation(integer(v));
}
function parse_EvaluatorKey(v: Value): EvaluatorKey {
  return EvaluatorKey(integer(v));
}
function parse_ContentRef(v: Value): ContentRef {
  return ContentRef(integer(v));
}
function parse_ContextRef(v: Value): ContextRef {
  return ContextRef(integer(v));
}
function parse_WorkTaskId(v: Value): WorkTaskId {
  if (!(v instanceof Variant) || v.tag !== "WorkTask")
    throw new ConversionError("expected WorkTaskId variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "cycle"]);
  return new WorkTaskId(
    parse_TicketId(r["ticket"]!),
    parse_CycleNumber(r["cycle"]!),
  );
}
function parse_EvaluationTaskId(v: Value): EvaluationTaskId {
  if (!(v instanceof Variant) || v.tag !== "EvaluationTask")
    throw new ConversionError("expected EvaluationTaskId variant");
  const payload = v.value;
  const r = record(payload, [
    "ticket",
    "workCycle",
    "stage",
    "generation",
    "evaluator",
  ]);
  return new EvaluationTaskId(
    parse_TicketId(r["ticket"]!),
    parse_CycleNumber(r["workCycle"]!),
    parse_StageKey(r["stage"]!),
    parse_Generation(r["generation"]!),
    parse_EvaluatorKey(r["evaluator"]!),
  );
}
function parse_TaskDefinition(v: Value): TaskDefinition {
  const r = record(v, [
    "workload",
    "inputs",
    "executionRequirements",
    "resultContract",
  ]);
  return new TaskDefinition(
    parse_ContentRef(r["workload"]!),
    parse_ContentRef(r["inputs"]!),
    parse_ContentRef(r["executionRequirements"]!),
    parse_ContentRef(r["resultContract"]!),
  );
}
function parse_TaskObligation(v: Value): TaskObligation {
  const r = record(v, ["task", "definition", "contextRef"]);
  return new TaskObligation(
    parse_TaskId(r["task"]!),
    parse_TaskDefinition(r["definition"]!),
    parse_ContextRef(r["contextRef"]!),
  );
}
function parse_ValidatedTaskResult(v: Value): ValidatedTaskResult {
  const r = record(v, ["obligation", "resultRef"]);
  return new ValidatedTaskResult(
    parse_TaskObligation(r["obligation"]!),
    parse_ContentRef(r["resultRef"]!),
  );
}
function parse_TaskFailure(v: Value): TaskFailure {
  const r = record(v, ["task", "evidence"]);
  return new TaskFailure(
    parse_TaskId(r["task"]!),
    parse_ContentRef(r["evidence"]!),
  );
}
function parse_TaskResultProduced(v: Value): TaskResultProduced {
  if (!(v instanceof Variant) || v.tag !== "TaskResultProduced")
    throw new ConversionError("expected TaskResultProduced variant");
  const payload = v.value;
  return new TaskResultProduced(parse_ValidatedTaskResult(payload));
}
function parse_TaskProcessFailed(v: Value): TaskProcessFailed {
  if (!(v instanceof Variant) || v.tag !== "TaskProcessFailed")
    throw new ConversionError("expected TaskProcessFailed variant");
  const payload = v.value;
  return new TaskProcessFailed(parse_TaskFailure(payload));
}
function parse_TaskExecutionUnavailable(v: Value): TaskExecutionUnavailable {
  if (!(v instanceof Variant) || v.tag !== "TaskExecutionUnavailable")
    throw new ConversionError("expected TaskExecutionUnavailable variant");
  const payload = v.value;
  return new TaskExecutionUnavailable(parse_TaskFailure(payload));
}
function parse_EvaluatorDefinition(v: Value): EvaluatorDefinition {
  const r = record(v, ["key", "task"]);
  return new EvaluatorDefinition(
    parse_EvaluatorKey(r["key"]!),
    parse_TaskDefinition(r["task"]!),
  );
}
function parse_StageDefinition(v: Value): StageDefinition {
  const r = record(v, ["key", "evaluators"]);
  return new StageDefinition(
    parse_StageKey(r["key"]!),
    list(r["evaluators"]!).map((item) => parse_EvaluatorDefinition(item)),
  );
}
function parse_EvaluationPlan(v: Value): EvaluationPlan {
  const r = record(v, ["stages"]);
  return new EvaluationPlan(
    list(r["stages"]!).map((item) => parse_StageDefinition(item)),
  );
}
function parse_EvaluationInput(v: Value): EvaluationInput {
  const r = record(v, ["ticket", "workResult", "acceptedSourceRef"]);
  return new EvaluationInput(
    parse_TicketId(r["ticket"]!),
    parse_ContentRef(r["workResult"]!),
    parse_ContentRef(r["acceptedSourceRef"]!),
  );
}
function parse_EvaluatorPassed(v: Value): EvaluatorPassed {
  if (!(v instanceof Variant) || v.tag !== "EvaluatorPassed")
    throw new ConversionError("expected EvaluatorPassed variant");
  const payload = v.value;
  return new EvaluatorPassed(parse_ContentRef(payload));
}
function parse_EvaluatorFailed(v: Value): EvaluatorFailed {
  if (!(v instanceof Variant) || v.tag !== "EvaluatorFailed")
    throw new ConversionError("expected EvaluatorFailed variant");
  const payload = v.value;
  return new EvaluatorFailed(parse_ContentRef(payload));
}
function parse_Awaiting(v: Value): Awaiting {
  if (!(v instanceof Variant) || v.tag !== "Awaiting")
    throw new ConversionError("expected Awaiting variant");
  const payload = v.value;
  if (!Array.isArray(payload) || payload.length)
    throw new ConversionError("expected nullary payload");
  return new Awaiting();
}
function parse_Produced(v: Value): Produced {
  if (!(v instanceof Variant) || v.tag !== "Produced")
    throw new ConversionError("expected Produced variant");
  const payload = v.value;
  return new Produced(parse_EvaluatorResult(payload));
}
function parse_EvaluatorProcessFailed(v: Value): EvaluatorProcessFailed {
  if (!(v instanceof Variant) || v.tag !== "EvaluatorProcessFailed")
    throw new ConversionError("expected EvaluatorProcessFailed variant");
  const payload = v.value;
  return new EvaluatorProcessFailed(parse_ContentRef(payload));
}
function parse_EvaluatorExecutionUnavailable(
  v: Value,
): EvaluatorExecutionUnavailable {
  if (!(v instanceof Variant) || v.tag !== "EvaluatorExecutionUnavailable")
    throw new ConversionError("expected EvaluatorExecutionUnavailable variant");
  const payload = v.value;
  return new EvaluatorExecutionUnavailable(parse_ContentRef(payload));
}
function parse_EvaluationReworkEntry(v: Value): EvaluationReworkEntry {
  const r = record(v, ["evaluator", "resultRef"]);
  return new EvaluationReworkEntry(
    parse_EvaluatorKey(r["evaluator"]!),
    parse_ContentRef(r["resultRef"]!),
  );
}
function parse_StageRun(v: Value): StageRun {
  const r = record(v, ["stageIndex", "generation", "evaluators"]);
  return new StageRun(
    integer(r["stageIndex"]!),
    parse_Generation(r["generation"]!),
    new Map(
      mapping(r["evaluators"]!).map(
        ([key, item]) =>
          [parse_EvaluatorKey(key), parse_EvaluatorStatus(item)] as const,
      ),
    ),
  );
}
function parse_EvaluationProgress(v: Value): EvaluationProgress {
  const r = record(v, ["completedStages", "stage"]);
  return new EvaluationProgress(
    list(r["completedStages"]!).map((item) => parse_StageRun(item)),
    parse_StageRun(r["stage"]!),
  );
}
function parse_Running(v: Value): Running {
  if (!(v instanceof Variant) || v.tag !== "Running")
    throw new ConversionError("expected Running variant");
  const payload = v.value;
  return new Running(parse_EvaluationProgress(payload));
}
function parse_EvaluationPassed(v: Value): EvaluationPassed {
  if (!(v instanceof Variant) || v.tag !== "EvaluationPassed")
    throw new ConversionError("expected EvaluationPassed variant");
  const payload = v.value;
  return new EvaluationPassed(
    list(payload).map((item) => parse_StageRun(item)),
  );
}
function parse_EvaluationFailed(v: Value): EvaluationFailed {
  if (!(v instanceof Variant) || v.tag !== "EvaluationFailed")
    throw new ConversionError("expected EvaluationFailed variant");
  const payload = v.value;
  return new EvaluationFailed(
    list(payload).map((item) => parse_StageRun(item)),
  );
}
function parse_EvaluationBlocked(v: Value): EvaluationBlocked {
  if (!(v instanceof Variant) || v.tag !== "EvaluationBlocked")
    throw new ConversionError("expected EvaluationBlocked variant");
  const payload = v.value;
  return new EvaluationBlocked(parse_EvaluationProgress(payload));
}
function parse_EvaluationInstance(v: Value): EvaluationInstance {
  const r = record(v, ["workCycle", "input", "plan", "state"]);
  return new EvaluationInstance(
    parse_CycleNumber(r["workCycle"]!),
    parse_EvaluationInput(r["input"]!),
    parse_EvaluationPlan(r["plan"]!),
    parse_EvaluationState(r["state"]!),
  );
}
function parse_InitialWork(v: Value): InitialWork {
  if (!(v instanceof Variant) || v.tag !== "InitialWork")
    throw new ConversionError("expected InitialWork variant");
  const payload = v.value;
  if (!Array.isArray(payload) || payload.length)
    throw new ConversionError("expected nullary payload");
  return new InitialWork();
}
function parse_EvaluationRework(v: Value): EvaluationRework {
  if (!(v instanceof Variant) || v.tag !== "EvaluationRework")
    throw new ConversionError("expected EvaluationRework variant");
  const payload = v.value;
  return new EvaluationRework(
    list(payload).map((item) => parse_EvaluationReworkEntry(item)),
  );
}
function parse_FinalizationRework(v: Value): FinalizationRework {
  if (!(v instanceof Variant) || v.tag !== "FinalizationRework")
    throw new ConversionError("expected FinalizationRework variant");
  const payload = v.value;
  return new FinalizationRework(parse_ContentRef(payload));
}
function parse_WorkInput(v: Value): WorkInput {
  const r = record(v, ["released", "cause", "retryEvidence"]);
  return new WorkInput(
    parse_ContentRef(r["released"]!),
    parse_WorkCause(r["cause"]!),
    list(r["retryEvidence"]!).map((item) => parse_ContentRef(item)),
  );
}
function parse_WorkExecution(v: Value): WorkExecution {
  const r = record(v, ["input", "source"]);
  return new WorkExecution(
    parse_WorkInput(r["input"]!),
    parse_ContentRef(r["source"]!),
  );
}
function parse_FinalizationOperation(v: Value): FinalizationOperation {
  const r = record(v, ["workCycle", "generation", "input", "source"]);
  return new FinalizationOperation(
    parse_CycleNumber(r["workCycle"]!),
    parse_Generation(r["generation"]!),
    parse_ContentRef(r["input"]!),
    parse_ContentRef(r["source"]!),
  );
}
function parse_WorkEscalation(v: Value): WorkEscalation {
  const r = record(v, ["resumeInput", "source", "evidence"]);
  return new WorkEscalation(
    parse_WorkInput(r["resumeInput"]!),
    parse_ContentRef(r["source"]!),
    parse_ContentRef(r["evidence"]!),
  );
}
function parse_EvaluationFailureEscalation(
  v: Value,
): EvaluationFailureEscalation {
  const r = record(v, ["evidence", "source"]);
  return new EvaluationFailureEscalation(
    list(r["evidence"]!).map((item) => parse_EvaluationReworkEntry(item)),
    parse_ContentRef(r["source"]!),
  );
}
function parse_FinalizationEscalation(v: Value): FinalizationEscalation {
  const r = record(v, ["finalization", "evidence"]);
  return new FinalizationEscalation(
    parse_FinalizationOperation(r["finalization"]!),
    parse_ContentRef(r["evidence"]!),
  );
}
function parse_WorkFailureEscalated(v: Value): WorkFailureEscalated {
  if (!(v instanceof Variant) || v.tag !== "WorkFailureEscalated")
    throw new ConversionError("expected WorkFailureEscalated variant");
  const payload = v.value;
  return new WorkFailureEscalated(parse_WorkEscalation(payload));
}
function parse_WorkExecutionUnavailableEscalated(
  v: Value,
): WorkExecutionUnavailableEscalated {
  if (!(v instanceof Variant) || v.tag !== "WorkExecutionUnavailableEscalated")
    throw new ConversionError(
      "expected WorkExecutionUnavailableEscalated variant",
    );
  const payload = v.value;
  return new WorkExecutionUnavailableEscalated(parse_WorkEscalation(payload));
}
function parse_EvaluationFailureEscalated(
  v: Value,
): EvaluationFailureEscalated {
  if (!(v instanceof Variant) || v.tag !== "EvaluationFailureEscalated")
    throw new ConversionError("expected EvaluationFailureEscalated variant");
  const payload = v.value;
  return new EvaluationFailureEscalated(
    parse_EvaluationFailureEscalation(payload),
  );
}
function parse_EvaluationBlockedEscalated(
  v: Value,
): EvaluationBlockedEscalated {
  if (!(v instanceof Variant) || v.tag !== "EvaluationBlockedEscalated")
    throw new ConversionError("expected EvaluationBlockedEscalated variant");
  const payload = v.value;
  return new EvaluationBlockedEscalated(parse_EvaluationInstance(payload));
}
function parse_FinalizationUnavailableEscalated(
  v: Value,
): FinalizationUnavailableEscalated {
  if (!(v instanceof Variant) || v.tag !== "FinalizationUnavailableEscalated")
    throw new ConversionError(
      "expected FinalizationUnavailableEscalated variant",
    );
  const payload = v.value;
  return new FinalizationUnavailableEscalated(
    parse_FinalizationEscalation(payload),
  );
}
function parse_ReleasedTicket(v: Value): ReleasedTicket {
  const r = record(v, [
    "id",
    "content",
    "dependencies",
    "workConfiguration",
    "evaluationPlan",
    "finalizationConfiguration",
  ]);
  return new ReleasedTicket(
    parse_TicketId(r["id"]!),
    parse_ContentRef(r["content"]!),
    new Set(set(r["dependencies"]!).map((item) => parse_TicketId(item))),
    parse_TaskDefinition(r["workConfiguration"]!),
    parse_EvaluationPlan(r["evaluationPlan"]!),
    parse_ContentRef(r["finalizationConfiguration"]!),
  );
}
function parse_Pending(v: Value): Pending {
  if (!(v instanceof Variant) || v.tag !== "Pending")
    throw new ConversionError("expected Pending variant");
  const payload = v.value;
  if (!Array.isArray(payload) || payload.length)
    throw new ConversionError("expected nullary payload");
  return new Pending();
}
function parse_Work(v: Value): Work {
  if (!(v instanceof Variant) || v.tag !== "Work")
    throw new ConversionError("expected Work variant");
  const payload = v.value;
  return new Work(parse_WorkExecution(payload));
}
function parse_Evaluation(v: Value): Evaluation {
  if (!(v instanceof Variant) || v.tag !== "Evaluation")
    throw new ConversionError("expected Evaluation variant");
  const payload = v.value;
  return new Evaluation(parse_EvaluationInstance(payload));
}
function parse_Finalization(v: Value): Finalization {
  if (!(v instanceof Variant) || v.tag !== "Finalization")
    throw new ConversionError("expected Finalization variant");
  const payload = v.value;
  return new Finalization(parse_FinalizationOperation(payload));
}
function parse_Escalated(v: Value): Escalated {
  if (!(v instanceof Variant) || v.tag !== "Escalated")
    throw new ConversionError("expected Escalated variant");
  const payload = v.value;
  return new Escalated(parse_Escalation(payload));
}
function parse_Done(v: Value): Done {
  if (!(v instanceof Variant) || v.tag !== "Done")
    throw new ConversionError("expected Done variant");
  const payload = v.value;
  if (!Array.isArray(payload) || payload.length)
    throw new ConversionError("expected nullary payload");
  return new Done();
}
function parse_Revoked(v: Value): Revoked {
  if (!(v instanceof Variant) || v.tag !== "Revoked")
    throw new ConversionError("expected Revoked variant");
  const payload = v.value;
  if (!Array.isArray(payload) || payload.length)
    throw new ConversionError("expected nullary payload");
  return new Revoked();
}
function parse_Ticket(v: Value): Ticket {
  const r = record(v, ["definition", "revision", "workCyclesStarted", "state"]);
  return new Ticket(
    parse_ReleasedTicket(r["definition"]!),
    integer(r["revision"]!),
    integer(r["workCyclesStarted"]!),
    parse_TicketState(r["state"]!),
  );
}
function parse_TicketGraph(v: Value): TicketGraph {
  const r = record(v, ["tickets"]);
  return new TicketGraph(
    new Map(
      mapping(r["tickets"]!).map(
        ([key, item]) => [parse_TicketId(key), parse_Ticket(item)] as const,
      ),
    ),
  );
}
function parse_TicketAlreadyExists(v: Value): TicketAlreadyExists {
  if (!(v instanceof Variant) || v.tag !== "TicketAlreadyExists")
    throw new ConversionError("expected TicketAlreadyExists variant");
  const payload = v.value;
  return new TicketAlreadyExists(parse_TicketId(payload));
}
function parse_DependenciesNotFound(v: Value): DependenciesNotFound {
  if (!(v instanceof Variant) || v.tag !== "DependenciesNotFound")
    throw new ConversionError("expected DependenciesNotFound variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "dependencies"]);
  return new DependenciesNotFound(
    parse_TicketId(r["ticket"]!),
    new Set(set(r["dependencies"]!).map((item) => parse_TicketId(item))),
  );
}
function parse_SelfDependency(v: Value): SelfDependency {
  if (!(v instanceof Variant) || v.tag !== "SelfDependency")
    throw new ConversionError("expected SelfDependency variant");
  const payload = v.value;
  return new SelfDependency(parse_TicketId(payload));
}
function parse_TicketNotFound(v: Value): TicketNotFound {
  if (!(v instanceof Variant) || v.tag !== "TicketNotFound")
    throw new ConversionError("expected TicketNotFound variant");
  const payload = v.value;
  return new TicketNotFound(parse_TicketId(payload));
}
function parse_TicketNotPending(v: Value): TicketNotPending {
  if (!(v instanceof Variant) || v.tag !== "TicketNotPending")
    throw new ConversionError("expected TicketNotPending variant");
  const payload = v.value;
  return new TicketNotPending(parse_TicketId(payload));
}
function parse_TicketIdentityMismatch(v: Value): TicketIdentityMismatch {
  if (!(v instanceof Variant) || v.tag !== "TicketIdentityMismatch")
    throw new ConversionError("expected TicketIdentityMismatch variant");
  const payload = v.value;
  return new TicketIdentityMismatch(parse_TicketId(payload));
}
function parse_TicketRevisionStale(v: Value): TicketRevisionStale {
  if (!(v instanceof Variant) || v.tag !== "TicketRevisionStale")
    throw new ConversionError("expected TicketRevisionStale variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "expected", "current"]);
  return new TicketRevisionStale(
    parse_TicketId(r["ticket"]!),
    integer(r["expected"]!),
    integer(r["current"]!),
  );
}
function parse_TicketDependenciesChanged(v: Value): TicketDependenciesChanged {
  if (!(v instanceof Variant) || v.tag !== "TicketDependenciesChanged")
    throw new ConversionError("expected TicketDependenciesChanged variant");
  const payload = v.value;
  return new TicketDependenciesChanged(parse_TicketId(payload));
}
function parse_DependenciesIncomplete(v: Value): DependenciesIncomplete {
  if (!(v instanceof Variant) || v.tag !== "DependenciesIncomplete")
    throw new ConversionError("expected DependenciesIncomplete variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "dependencies"]);
  return new DependenciesIncomplete(
    parse_TicketId(r["ticket"]!),
    new Set(set(r["dependencies"]!).map((item) => parse_TicketId(item))),
  );
}
function parse_TicketNotRevocable(v: Value): TicketNotRevocable {
  if (!(v instanceof Variant) || v.tag !== "TicketNotRevocable")
    throw new ConversionError("expected TicketNotRevocable variant");
  const payload = v.value;
  return new TicketNotRevocable(parse_TicketId(payload));
}
function parse_TicketNotResumable(v: Value): TicketNotResumable {
  if (!(v instanceof Variant) || v.tag !== "TicketNotResumable")
    throw new ConversionError("expected TicketNotResumable variant");
  const payload = v.value;
  return new TicketNotResumable(parse_TicketId(payload));
}
function parse_TaskNotCurrent(v: Value): TaskNotCurrent {
  if (!(v instanceof Variant) || v.tag !== "TaskNotCurrent")
    throw new ConversionError("expected TaskNotCurrent variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "task"]);
  return new TaskNotCurrent(
    parse_TicketId(r["ticket"]!),
    parse_TaskId(r["task"]!),
  );
}
function parse_FinalizationNotCurrent(v: Value): FinalizationNotCurrent {
  if (!(v instanceof Variant) || v.tag !== "FinalizationNotCurrent")
    throw new ConversionError("expected FinalizationNotCurrent variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "workCycle", "generation"]);
  return new FinalizationNotCurrent(
    parse_TicketId(r["ticket"]!),
    parse_CycleNumber(r["workCycle"]!),
    parse_Generation(r["generation"]!),
  );
}
function parse_TicketCreated(v: Value): TicketCreated {
  if (!(v instanceof Variant) || v.tag !== "TicketCreated")
    throw new ConversionError("expected TicketCreated variant");
  const payload = v.value;
  return new TicketCreated(parse_ReleasedTicket(payload));
}
function parse_TicketUpdated(v: Value): TicketUpdated {
  if (!(v instanceof Variant) || v.tag !== "TicketUpdated")
    throw new ConversionError("expected TicketUpdated variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "revision", "definition"]);
  return new TicketUpdated(
    parse_TicketId(r["ticket"]!),
    integer(r["revision"]!),
    parse_ReleasedTicket(r["definition"]!),
  );
}
function parse_TicketDispatched(v: Value): TicketDispatched {
  if (!(v instanceof Variant) || v.tag !== "TicketDispatched")
    throw new ConversionError("expected TicketDispatched variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "source"]);
  return new TicketDispatched(
    parse_TicketId(r["ticket"]!),
    parse_ContentRef(r["source"]!),
  );
}
function parse_TicketRevoked(v: Value): TicketRevoked {
  if (!(v instanceof Variant) || v.tag !== "TicketRevoked")
    throw new ConversionError("expected TicketRevoked variant");
  const payload = v.value;
  return new TicketRevoked(parse_TicketId(payload));
}
function parse_TicketWorkResumed(v: Value): TicketWorkResumed {
  if (!(v instanceof Variant) || v.tag !== "TicketWorkResumed")
    throw new ConversionError("expected TicketWorkResumed variant");
  const payload = v.value;
  return new TicketWorkResumed(parse_TicketId(payload));
}
function parse_TicketEvaluationResumed(v: Value): TicketEvaluationResumed {
  if (!(v instanceof Variant) || v.tag !== "TicketEvaluationResumed")
    throw new ConversionError("expected TicketEvaluationResumed variant");
  const payload = v.value;
  return new TicketEvaluationResumed(parse_TicketId(payload));
}
function parse_TicketFinalizationResumed(v: Value): TicketFinalizationResumed {
  if (!(v instanceof Variant) || v.tag !== "TicketFinalizationResumed")
    throw new ConversionError("expected TicketFinalizationResumed variant");
  const payload = v.value;
  return new TicketFinalizationResumed(parse_TicketId(payload));
}
function parse_TicketWorkResultAccepted(v: Value): TicketWorkResultAccepted {
  if (!(v instanceof Variant) || v.tag !== "TicketWorkResultAccepted")
    throw new ConversionError("expected TicketWorkResultAccepted variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "result", "acceptedSourceRef"]);
  return new TicketWorkResultAccepted(
    parse_TicketId(r["ticket"]!),
    parse_ValidatedTaskResult(r["result"]!),
    parse_ContentRef(r["acceptedSourceRef"]!),
  );
}
function parse_TicketWorkProcessFailed(v: Value): TicketWorkProcessFailed {
  if (!(v instanceof Variant) || v.tag !== "TicketWorkProcessFailed")
    throw new ConversionError("expected TicketWorkProcessFailed variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "task", "evidence"]);
  return new TicketWorkProcessFailed(
    parse_TicketId(r["ticket"]!),
    parse_TaskId(r["task"]!),
    parse_ContentRef(r["evidence"]!),
  );
}
function parse_TicketWorkExecutionUnavailable(
  v: Value,
): TicketWorkExecutionUnavailable {
  if (!(v instanceof Variant) || v.tag !== "TicketWorkExecutionUnavailable")
    throw new ConversionError(
      "expected TicketWorkExecutionUnavailable variant",
    );
  const payload = v.value;
  const r = record(payload, ["ticket", "task", "evidence"]);
  return new TicketWorkExecutionUnavailable(
    parse_TicketId(r["ticket"]!),
    parse_TaskId(r["task"]!),
    parse_ContentRef(r["evidence"]!),
  );
}
function parse_TicketEvaluationProgressed(
  v: Value,
): TicketEvaluationProgressed {
  if (!(v instanceof Variant) || v.tag !== "TicketEvaluationProgressed")
    throw new ConversionError("expected TicketEvaluationProgressed variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "report"]);
  return new TicketEvaluationProgressed(
    parse_TicketId(r["ticket"]!),
    parse_TaskTerminalReport(r["report"]!),
  );
}
function parse_TicketEvaluationPassed(v: Value): TicketEvaluationPassed {
  if (!(v instanceof Variant) || v.tag !== "TicketEvaluationPassed")
    throw new ConversionError("expected TicketEvaluationPassed variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "report"]);
  return new TicketEvaluationPassed(
    parse_TicketId(r["ticket"]!),
    parse_TaskTerminalReport(r["report"]!),
  );
}
function parse_TicketEvaluationReworkStarted(
  v: Value,
): TicketEvaluationReworkStarted {
  if (!(v instanceof Variant) || v.tag !== "TicketEvaluationReworkStarted")
    throw new ConversionError("expected TicketEvaluationReworkStarted variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "report", "evidence"]);
  return new TicketEvaluationReworkStarted(
    parse_TicketId(r["ticket"]!),
    parse_TaskTerminalReport(r["report"]!),
    list(r["evidence"]!).map((item) => parse_EvaluationReworkEntry(item)),
  );
}
function parse_TicketEvaluationFailureEscalated(
  v: Value,
): TicketEvaluationFailureEscalated {
  if (!(v instanceof Variant) || v.tag !== "TicketEvaluationFailureEscalated")
    throw new ConversionError(
      "expected TicketEvaluationFailureEscalated variant",
    );
  const payload = v.value;
  const r = record(payload, ["ticket", "report", "evidence"]);
  return new TicketEvaluationFailureEscalated(
    parse_TicketId(r["ticket"]!),
    parse_TaskTerminalReport(r["report"]!),
    list(r["evidence"]!).map((item) => parse_EvaluationReworkEntry(item)),
  );
}
function parse_TicketEvaluationBlocked(v: Value): TicketEvaluationBlocked {
  if (!(v instanceof Variant) || v.tag !== "TicketEvaluationBlocked")
    throw new ConversionError("expected TicketEvaluationBlocked variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "report"]);
  return new TicketEvaluationBlocked(
    parse_TicketId(r["ticket"]!),
    parse_TaskTerminalReport(r["report"]!),
  );
}
function parse_TicketFinalizationSucceeded(
  v: Value,
): TicketFinalizationSucceeded {
  if (!(v instanceof Variant) || v.tag !== "TicketFinalizationSucceeded")
    throw new ConversionError("expected TicketFinalizationSucceeded variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "workCycle", "generation", "evidence"]);
  return new TicketFinalizationSucceeded(
    parse_TicketId(r["ticket"]!),
    parse_CycleNumber(r["workCycle"]!),
    parse_Generation(r["generation"]!),
    parse_ContentRef(r["evidence"]!),
  );
}
function parse_TicketFinalizationNeedsWork(
  v: Value,
): TicketFinalizationNeedsWork {
  if (!(v instanceof Variant) || v.tag !== "TicketFinalizationNeedsWork")
    throw new ConversionError("expected TicketFinalizationNeedsWork variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "workCycle", "generation", "evidence"]);
  return new TicketFinalizationNeedsWork(
    parse_TicketId(r["ticket"]!),
    parse_CycleNumber(r["workCycle"]!),
    parse_Generation(r["generation"]!),
    parse_ContentRef(r["evidence"]!),
  );
}
function parse_TicketFinalizationUnavailable(
  v: Value,
): TicketFinalizationUnavailable {
  if (!(v instanceof Variant) || v.tag !== "TicketFinalizationUnavailable")
    throw new ConversionError("expected TicketFinalizationUnavailable variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "workCycle", "generation", "evidence"]);
  return new TicketFinalizationUnavailable(
    parse_TicketId(r["ticket"]!),
    parse_CycleNumber(r["workCycle"]!),
    parse_Generation(r["generation"]!),
    parse_ContentRef(r["evidence"]!),
  );
}
function parse_ExecuteTask(v: Value): ExecuteTask {
  if (!(v instanceof Variant) || v.tag !== "ExecuteTask")
    throw new ConversionError("expected ExecuteTask variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "task"]);
  return new ExecuteTask(
    parse_TicketId(r["ticket"]!),
    parse_TaskObligation(r["task"]!),
  );
}
function parse_FinalizeTicket(v: Value): FinalizeTicket {
  if (!(v instanceof Variant) || v.tag !== "FinalizeTicket")
    throw new ConversionError("expected FinalizeTicket variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "finalization", "configuration"]);
  return new FinalizeTicket(
    parse_TicketId(r["ticket"]!),
    parse_FinalizationOperation(r["finalization"]!),
    parse_ContentRef(r["configuration"]!),
  );
}
function parse_CancelTask(v: Value): CancelTask {
  if (!(v instanceof Variant) || v.tag !== "CancelTask")
    throw new ConversionError("expected CancelTask variant");
  const payload = v.value;
  const r = record(payload, ["ticket", "task"]);
  return new CancelTask(parse_TicketId(r["ticket"]!), parse_TaskId(r["task"]!));
}
function parse_TicketRefused(v: Value): TicketRefused {
  if (!(v instanceof Variant) || v.tag !== "TicketRefused")
    throw new ConversionError("expected TicketRefused variant");
  const payload = v.value;
  return new TicketRefused(parse_TicketRefusal(payload));
}
function parse_TicketDecided(v: Value): TicketDecided {
  if (!(v instanceof Variant) || v.tag !== "TicketDecided")
    throw new ConversionError("expected TicketDecided variant");
  const payload = v.value;
  const r = record(payload, ["event", "obligations"]);
  return new TicketDecided(
    parse_TicketEvent(r["event"]!),
    list(r["obligations"]!).map((item) => parse_Obligation(item)),
  );
}
function parse_TaskId(v: Value): TaskId {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "WorkTask":
      return parse_WorkTaskId(v);
    case "EvaluationTask":
      return parse_EvaluationTaskId(v);
    default:
      throw new ConversionError(`unknown TaskId tag '${v.tag}'`);
  }
}
function parse_TaskTerminal(v: Value): TaskTerminal {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "TaskResultProduced":
      return parse_TaskResultProduced(v);
    case "TaskProcessFailed":
      return parse_TaskProcessFailed(v);
    case "TaskExecutionUnavailable":
      return parse_TaskExecutionUnavailable(v);
    default:
      throw new ConversionError(`unknown TaskTerminal tag '${v.tag}'`);
  }
}
function parse_EvaluationVerdict(v: Value): EvaluationVerdict {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "EvaluatorPass":
      return new EvaluatorPass();
    case "EvaluatorFail":
      return new EvaluatorFail();
    default:
      throw new ConversionError(`unknown EvaluationVerdict tag '${v.tag}'`);
  }
}
function parse_TaskTerminalReport(v: Value): TaskTerminalReport {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  if (v.tag === "WorkResultReport") {
    const r = record(v.value, ["ticket", "result", "acceptedSourceRef"]);
    return new WorkResultReport(
      parse_TicketId(r["ticket"]!),
      parse_ValidatedTaskResult(r["result"]!),
      parse_ContentRef(r["acceptedSourceRef"]!),
    );
  }
  if (v.tag === "EvaluationResultReport") {
    const r = record(v.value, ["ticket", "result", "verdict"]);
    return new EvaluationResultReport(
      parse_TicketId(r["ticket"]!),
      parse_ValidatedTaskResult(r["result"]!),
      parse_EvaluationVerdict(r["verdict"]!),
    );
  }
  if (v.tag === "TerminalFailureReport") {
    const r = record(v.value, ["ticket", "failure", "kind"]);
    const kind = r["kind"];
    if (!(kind instanceof Variant))
      throw new ConversionError("expected failure kind");
    return new TerminalFailureReport(
      parse_TicketId(r["ticket"]!),
      parse_TaskFailure(r["failure"]!),
      kind.tag === "ProcessFailure"
        ? new ProcessFailure()
        : kind.tag === "ExecutionUnavailableFailure"
          ? new ExecutionUnavailableFailure()
          : (() => {
              throw new ConversionError("unknown failure kind");
            })(),
    );
  }
  throw new ConversionError(`unknown TaskTerminalReport tag '${v.tag}'`);
}
function parse_EvaluatorResult(v: Value): EvaluatorResult {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "EvaluatorPassed":
      return parse_EvaluatorPassed(v);
    case "EvaluatorFailed":
      return parse_EvaluatorFailed(v);
    default:
      throw new ConversionError(`unknown EvaluatorResult tag '${v.tag}'`);
  }
}
function parse_EvaluatorStatus(v: Value): EvaluatorStatus {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "Awaiting":
      return parse_Awaiting(v);
    case "Produced":
      return parse_Produced(v);
    case "EvaluatorProcessFailed":
      return parse_EvaluatorProcessFailed(v);
    case "EvaluatorExecutionUnavailable":
      return parse_EvaluatorExecutionUnavailable(v);
    default:
      throw new ConversionError(`unknown EvaluatorStatus tag '${v.tag}'`);
  }
}
function parse_EvaluationState(v: Value): EvaluationState {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "Running":
      return parse_Running(v);
    case "EvaluationPassed":
      return parse_EvaluationPassed(v);
    case "EvaluationFailed":
      return parse_EvaluationFailed(v);
    case "EvaluationBlocked":
      return parse_EvaluationBlocked(v);
    default:
      throw new ConversionError(`unknown EvaluationState tag '${v.tag}'`);
  }
}
function parse_WorkCause(v: Value): WorkCause {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "InitialWork":
      return parse_InitialWork(v);
    case "EvaluationRework":
      return parse_EvaluationRework(v);
    case "FinalizationRework":
      return parse_FinalizationRework(v);
    default:
      throw new ConversionError(`unknown WorkCause tag '${v.tag}'`);
  }
}
function parse_Escalation(v: Value): Escalation {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "WorkFailureEscalated":
      return parse_WorkFailureEscalated(v);
    case "WorkExecutionUnavailableEscalated":
      return parse_WorkExecutionUnavailableEscalated(v);
    case "EvaluationFailureEscalated":
      return parse_EvaluationFailureEscalated(v);
    case "EvaluationBlockedEscalated":
      return parse_EvaluationBlockedEscalated(v);
    case "FinalizationUnavailableEscalated":
      return parse_FinalizationUnavailableEscalated(v);
    default:
      throw new ConversionError(`unknown Escalation tag '${v.tag}'`);
  }
}
function parse_TicketState(v: Value): TicketState {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "Pending":
      return parse_Pending(v);
    case "Work":
      return parse_Work(v);
    case "Evaluation":
      return parse_Evaluation(v);
    case "Finalization":
      return parse_Finalization(v);
    case "Escalated":
      return parse_Escalated(v);
    case "Done":
      return parse_Done(v);
    case "Revoked":
      return parse_Revoked(v);
    default:
      throw new ConversionError(`unknown TicketState tag '${v.tag}'`);
  }
}
function parse_TicketRefusal(v: Value): TicketRefusal {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "TicketAlreadyExists":
      return parse_TicketAlreadyExists(v);
    case "DependenciesNotFound":
      return parse_DependenciesNotFound(v);
    case "SelfDependency":
      return parse_SelfDependency(v);
    case "TicketNotFound":
      return parse_TicketNotFound(v);
    case "TicketNotPending":
      return parse_TicketNotPending(v);
    case "TicketIdentityMismatch":
      return parse_TicketIdentityMismatch(v);
    case "TicketRevisionStale":
      return parse_TicketRevisionStale(v);
    case "TicketDependenciesChanged":
      return parse_TicketDependenciesChanged(v);
    case "DependenciesIncomplete":
      return parse_DependenciesIncomplete(v);
    case "TicketNotRevocable":
      return parse_TicketNotRevocable(v);
    case "TicketNotResumable":
      return parse_TicketNotResumable(v);
    case "TaskNotCurrent":
      return parse_TaskNotCurrent(v);
    case "FinalizationNotCurrent":
      return parse_FinalizationNotCurrent(v);
    default:
      throw new ConversionError(`unknown TicketRefusal tag '${v.tag}'`);
  }
}
function parse_TicketEvent(v: Value): TicketEvent {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "TicketCreated":
      return parse_TicketCreated(v);
    case "TicketUpdated":
      return parse_TicketUpdated(v);
    case "TicketDispatched":
      return parse_TicketDispatched(v);
    case "TicketRevoked":
      return parse_TicketRevoked(v);
    case "TicketWorkResumed":
      return parse_TicketWorkResumed(v);
    case "TicketEvaluationResumed":
      return parse_TicketEvaluationResumed(v);
    case "TicketFinalizationResumed":
      return parse_TicketFinalizationResumed(v);
    case "TicketWorkResultAccepted":
      return parse_TicketWorkResultAccepted(v);
    case "TicketWorkProcessFailed":
      return parse_TicketWorkProcessFailed(v);
    case "TicketWorkExecutionUnavailable":
      return parse_TicketWorkExecutionUnavailable(v);
    case "TicketEvaluationProgressed":
      return parse_TicketEvaluationProgressed(v);
    case "TicketEvaluationPassed":
      return parse_TicketEvaluationPassed(v);
    case "TicketEvaluationReworkStarted":
      return parse_TicketEvaluationReworkStarted(v);
    case "TicketEvaluationFailureEscalated":
      return parse_TicketEvaluationFailureEscalated(v);
    case "TicketEvaluationBlocked":
      return parse_TicketEvaluationBlocked(v);
    case "TicketFinalizationSucceeded":
      return parse_TicketFinalizationSucceeded(v);
    case "TicketFinalizationNeedsWork":
      return parse_TicketFinalizationNeedsWork(v);
    case "TicketFinalizationUnavailable":
      return parse_TicketFinalizationUnavailable(v);
    default:
      throw new ConversionError(`unknown TicketEvent tag '${v.tag}'`);
  }
}
function parse_Obligation(v: Value): Obligation {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "ExecuteTask":
      return parse_ExecuteTask(v);
    case "FinalizeTicket":
      return parse_FinalizeTicket(v);
    case "CancelTask":
      return parse_CancelTask(v);
    default:
      throw new ConversionError(`unknown Obligation tag '${v.tag}'`);
  }
}
function parse_TicketDecision(v: Value): TicketDecision {
  if (!(v instanceof Variant)) throw new ConversionError("expected a variant");
  switch (v.tag) {
    case "TicketRefused":
      return parse_TicketRefused(v);
    case "TicketDecided":
      return parse_TicketDecided(v);
    default:
      throw new ConversionError(`unknown TicketDecision tag '${v.tag}'`);
  }
}
export function graph_from_itf(v: Value, _where = "graph"): TicketGraph {
  return parse_TicketGraph(v);
}
export function decision_from_itf(
  v: Value,
  _where = "lastDecision",
): TicketDecision {
  return parse_TicketDecision(v);
}
