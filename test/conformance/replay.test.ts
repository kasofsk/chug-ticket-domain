import { expect, test } from "vitest";
import { basename } from "node:path";
import * as k from "../../src/ticket.js";
import { equal } from "../../src/task.js";
import * as itf from "../../src/itf.js";
import * as replay from "./replay.js";
const traces = itf.load_traces();
const summaries: {
  file: string;
  kind: string;
  checks: number;
  evolve: string[];
}[] = [];
for (const trace of traces)
  test(basename(trace.path), () => {
    let checks = 0;
    const evolve: string[] = [];
    for (const step of itf.steps(trace)) {
      const state = trace.states[step.index]!,
        where = `${basename(trace.path)}[${step.index}]`,
        prior = replay.graph_from_itf(state[itf.PRIOR_GRAPH_VAR]!),
        graph = replay.graph_from_itf(state[itf.GRAPH_VAR]!),
        decision = replay.decision_from_itf(state[itf.DECISION_VAR]!);
      expect(k.graph_invariant(prior), `${where}: prior invariant`).toBe(true);
      expect(k.graph_invariant(graph), `${where}: graph invariant`).toBe(true);
      expect(
        k.decision_valid(prior, decision),
        `${where}: decision valid`,
      ).toBe(true);
      expect(
        equal(k.apply_decision(prior, decision), graph),
        `${where}: evolution`,
      ).toBe(true);
      if (decision instanceof k.TicketDecided)
        expect(
          equal(k.evolve_checked(prior, decision.event), graph),
          `${where}: checked evolution`,
        ).toBe(true);
      const rebuilt = replay.command_from_step(step, prior);
      if (rebuilt instanceof replay.Reconstructed) {
        k.validate_command(rebuilt.command);
        expect(
          k.decide(prior, rebuilt.command, rebuilt.policy),
          `${where}: decide`,
        ).toEqual(decision);
        checks++;
      } else evolve.push(`[${step.index}] ${rebuilt.reason}`);
    }
    summaries.push({
      file: basename(trace.path),
      kind: trace.kind,
      checks,
      evolve,
    });
  });
test("corpus has complete decision coverage", () => {
  expect(traces).toHaveLength(29);
  expect(summaries.filter((s) => s.kind === "simulation")).toHaveLength(4);
  expect(
    summaries
      .filter((s) => s.kind === "simulation")
      .reduce((n, s) => n + s.checks, 0),
  ).toBe(100);
  expect(
    summaries
      .filter((s) => s.kind === "scenario")
      .reduce((n, s) => n + s.checks, 0),
  ).toBe(203);
  expect(summaries.flatMap((s) => s.evolve)).toHaveLength(22);
  expect(
    summaries.filter((s) => s.kind === "simulation").flatMap((s) => s.evolve),
  ).toEqual([]);
});
