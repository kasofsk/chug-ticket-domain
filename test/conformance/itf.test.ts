import { expect, test } from "vitest";
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { join, basename } from "node:path";
import { tmpdir } from "node:os";
import * as itf from "../../src/itf.js";
import { graph_from_itf, decision_from_itf } from "./convert.js";
const traces = itf.load_traces();
test("indexed traces all decode with declared shape and metadata", () => {
  const index = JSON.parse(
    readFileSync(join(itf.TRACES_DIR, "index.json"), "utf8"),
  ) as {
    traces: {
      file: string;
      states: number;
      kind: string;
      scenario?: string;
      seed?: string;
    }[];
  };
  expect(traces.map((t) => basename(t.path))).toEqual(
    index.traces.map((t) => t.file).sort(),
  );
  for (const t of traces) {
    const entry = index.traces.find((e) => e.file === basename(t.path))!;
    expect(t.states).toHaveLength(entry.states);
    expect(t.kind).toBe(entry.kind);
    expect(t.name).toBe(entry.scenario ?? entry.seed);
    for (const s of t.states) expect(Object.keys(s)).toEqual(t.vars);
  }
});
test.each([
  { "#bigint": 501 },
  { "#bigint": "0x1f" },
  { "#bigint": "01" },
  { "#bigint": "501", extra: 1 },
  { "#unserializable": "1" },
  { tag: "Only" },
  { tag: 7, value: { "#tup": [] } },
  { "#map": [[{ "#bigint": "1" }]] },
  { "#set": { not: "an array" } },
  1.5,
  null,
])("unexpected encoding is refused %j", (v) =>
  expect(() => itf.decode(v)).toThrow(itf.ItfError),
);
test("decodes scalar tuple list set map and variant forms", () => {
  expect(itf.decode({ "#bigint": "-7" })).toBe(-7);
  expect(itf.decode({ "#tup": [5, "six"] })).toEqual([5, "six"]);
  expect(itf.decode({ "#set": [4, 3] })).toEqual(new Set([4, 3]));
  expect(
    itf.decode({ "#map": [[1, { tag: "Pending", value: { "#tup": [] } }]] }),
  ).toEqual(new Map([[1, new itf.Variant("Pending", [])]]));
  expect(() =>
    itf.decode({
      "#map": [
        [{ a: 1, b: 2 }, "x"],
        [{ b: 2, a: 1 }, "y"],
      ],
    }),
  ).toThrow(/duplicate/);
});
test("rejects state shape and index mismatches", () => {
  const dir = mkdtempSync(join(tmpdir(), "chug-itf-"));
  try {
    for (const s of [
      { "#meta": { index: 0 }, a: "x" },
      { "#meta": { index: 1 }, a: "x", b: "y" },
      { a: "x", b: "y" },
      { "#meta": { index: 0 }, a: "x", b: "y", extra: 0 },
    ]) {
      const file = join(dir, "bad.json");
      writeFileSync(
        file,
        JSON.stringify({
          "#meta": { kind: "scenario", scenario: "bad" },
          vars: ["a", "b"],
          states: [s],
        }),
      );
      expect(() => itf.load_trace(file)).toThrow(itf.ItfError);
    }
  } finally {
    rmSync(dir, { recursive: true });
  }
});
test("conversion refuses unknown variants and record fields", () => {
  expect(() => decision_from_itf(new itf.Variant("Bogus", []))).toThrow(
    /unknown TicketDecision tag/,
  );
  expect(() => graph_from_itf({ tickets: new Map(), extra: 1 })).toThrow(
    /holds/,
  );
  expect(() => graph_from_itf({})).toThrow(/holds/);
  expect(() => graph_from_itf(new itf.Variant("TicketGraph", []))).toThrow(
    /record/,
  );
});
test("distinct decisions preserve happy path indexing", () => {
  const t = traces.find((t) => t.name === "happyPathTest")!;
  expect([...itf.decisions(t)].map((s) => s.index)).toEqual([
    1, 2, 3, 5, 6, 7, 8, 9, 10,
  ]);
});

test("execution requirement refs survive trace conversion distinctly", () => {
  const trace = traces.find(
    (entry) => entry.name === "executionRequirementsPreservedTest",
  )!;
  const final = graph_from_itf(trace.states.at(-1)![itf.GRAPH_VAR]!);
  const ticket = [...final.tickets.values()][0]!;
  expect(ticket.definition.work_configuration.execution_requirements).toBe(31);
  for (const stage of ticket.definition.evaluation_plan.stages)
    for (const evaluator of stage.evaluators)
      expect(evaluator.task.execution_requirements).toBe(32);
});
