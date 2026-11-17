import { expect, test } from "vitest";
import { basename } from "node:path";
import * as k from "../../src/ticket.js";
import { equal } from "../../src/task.js";
import * as itf from "../../src/itf.js";
import * as replay from "./replay.js";
const traces = itf.load_traces();
const finalizing = replay.finalizing_graph();
const features = new Set<string>();
const summaries: {
  file: string;
  kind: string;
  checks: number;
  restarts: number;
  evolve: string[];
}[] = [];
for (const trace of traces)
  test(basename(trace.path), () => {
    let checks = 0,
      restarts = 0;
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
      if (trace.meta.step !== undefined && step.index === 1)
        expect(equal(prior, finalizing), `${where}: starts finalizing`).toBe(
          true,
        );
      for (const feature of replay.step_features(step, prior, decision))
        features.add(feature);
      const rebuilt = replay.command_from_step(step, prior);
      if (rebuilt instanceof replay.Restarted) {
        expect(equal(prior, finalizing), `${where}: restart`).toBe(true);
        expect(equal(graph, finalizing), `${where}: restart`).toBe(true);
        restarts++;
      } else if (rebuilt instanceof replay.Reconstructed) {
        k.validate_command(rebuilt.command);
        expect(
          k.decide(prior, rebuilt.command, rebuilt.policy),
          `${where}: decide`,
        ).toEqual(decision);
        if (
          decision instanceof k.TicketDecided &&
          decision.event instanceof k.TicketFinalizationFailureEscalated
        )
          for (const policy of replay.ESCALATING)
            expect(
              k.decide(prior, rebuilt.command, policy),
              `${where}: any disposition but rework escalates`,
            ).toEqual(decision);
        checks++;
      } else evolve.push(`[${step.index}] ${rebuilt.reason}`);
    }
    summaries.push({
      file: basename(trace.path),
      kind: trace.kind,
      checks,
      restarts,
      evolve,
    });
  });
test("corpus has complete decision coverage", () => {
  expect(traces).toHaveLength(81);
  expect(summaries.filter((s) => s.kind === "simulation")).toHaveLength(12);
  expect(
    summaries
      .filter((s) => s.kind === "simulation")
      .reduce((n, s) => n + s.checks, 0),
  ).toBe(288);
  expect(
    summaries
      .filter((s) => s.kind === "scenario")
      .reduce((n, s) => n + s.checks, 0),
  ).toBe(756);
  expect(summaries.flatMap((s) => s.evolve)).toHaveLength(101);
  expect(summaries.reduce((n, s) => n + s.restarts, 0)).toBe(12);
  expect(
    summaries.filter((s) => s.kind === "simulation").flatMap((s) => s.evolve),
  ).toEqual([]);
  expect(
    replay.REQUIRED_FEATURES.filter((feature) => !features.has(feature)),
  ).toEqual([]);
});
