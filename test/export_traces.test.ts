import { test, expect, afterEach } from "vitest";
import {
  mkdtempSync,
  readFileSync,
  writeFileSync,
  rmSync,
  readdirSync,
  existsSync,
} from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import * as traces from "../model/ticket-domain/export_traces.js";
const roots: string[] = [];
afterEach(() => {
  for (const dir of roots.splice(0))
    rmSync(dir, { recursive: true, force: true });
});
function directory(): string {
  const dir = mkdtempSync(join(tmpdir(), "chug-traces-test-"));
  roots.push(dir);
  return dir;
}
function fake_quint(_quint: string, args: readonly string[]): void {
  const pattern = args[args.indexOf("--out-itf") + 1]!;
  if (args[0] === "test") {
    for (const name of traces.scenario_names()) {
      const raw = JSON.parse(
        readFileSync(join(traces.TRACES, `scenario-${name}.itf.json`), "utf8"),
      );
      writeFileSync(
        pattern.replace("{test}", name).replace("{seq}", "0"),
        JSON.stringify(raw),
      );
    }
  } else {
    const seed = args[args.indexOf("--seed") + 1]!;
    writeFileSync(
      pattern.replace("{seq}", "0"),
      readFileSync(join(traces.TRACES, `simulation-seed-${seed}.itf.json`)),
    );
  }
}
test("trace export is deterministic with complete model-declared coverage", () => {
  const output = directory();
  writeFileSync(join(output, "stale.itf.json"), "stale");
  writeFileSync(join(output, "README.md"), "keep");
  const first = traces.export_traces("quint", {
    traces: output,
    run: fake_quint,
  });
  expect(first.removed).toEqual(["stale.itf.json"]);
  expect(first.traces).toHaveLength(26);
  expect(existsSync(join(output, "README.md"))).toBe(true);
  expect(first.coverage).toEqual(
    JSON.parse(readFileSync(traces.INDEX, "utf8")).coverage,
  );
  const bytes = new Map(
    readdirSync(output).map((n) => [n, readFileSync(join(output, n))]),
  );
  const second = traces.export_traces("quint", {
    traces: output,
    run: fake_quint,
  });
  expect(second.removed).toEqual([]);
  for (const [name, data] of bytes)
    expect(readFileSync(join(output, name))).toEqual(data);
  const expected = JSON.parse(readFileSync(traces.INDEX, "utf8"));
  expect(JSON.parse(readFileSync(join(output, "index.json"), "utf8"))).toEqual({
    ...expected,
    generator: traces.GENERATOR,
  });
});
test("trace export refuses missing traces bad status missing executables and declarations", () => {
  expect(() =>
    traces.export_traces("quint", { traces: directory(), run: () => {} }),
  ).toThrow(/produced no trace/);
  expect(() => traces.normalize({ "#meta": { status: "error" } }, {})).toThrow(
    /expected 'ok'/,
  );
  expect(() => traces.find_quint({ PATH: directory() })).toThrow(/not found/);
  expect(() => traces.variant_names(traces.MODEL, "Missing")).toThrow(
    /not found/,
  );
  const file = join(directory(), "empty.qnt");
  writeFileSync(file, "module empty {}");
  expect(() => traces.scenario_names(file)).toThrow(/no `run`/);
});
test("normalization removes unstable metadata and duplicate MBT variables only", () => {
  const raw = {
    "#meta": {
      status: "ok",
      format: "ITF",
      "format-description": "format",
      source: "source",
      timestamp: "now",
      description: "generated",
    },
    vars: ["a", "a", "b"],
    states: [{ "#meta": { index: 0 }, a: 1, b: { "#set": [] } }],
  };
  const normalized = traces.normalize(raw, {
    kind: "scenario",
    scenario: "example",
  });
  expect(normalized.vars).toEqual(["a", "b"]);
  expect(normalized.states).toEqual(raw.states);
  expect(normalized["#meta"]).toEqual({
    format: "ITF",
    "format-description": "format",
    source: "source",
    status: "ok",
    generator: traces.GENERATOR,
    kind: "scenario",
    scenario: "example",
  });
});
