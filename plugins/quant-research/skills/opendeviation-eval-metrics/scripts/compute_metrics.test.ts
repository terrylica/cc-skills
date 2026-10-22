// End-to-end test of the compute_metrics.py CLI (#44).
//
// The bug: `evaluate_fold` returned `is_collapsed` as a numpy bool, so calling the library worked
// while the CLI's `json.dumps` raised TypeError. Only running the real CLI and parsing what it
// prints catches that class of bug, so this test does exactly that, in a subprocess, through uv.
//
// It lives here as a Bun test because the repo gate (`moon run repo:check` -> `repo:test`) runs
// every tracked *.test.ts; no gate task runs Python test files. JSON.parse is the strict parser on
// purpose: it rejects the bare NaN / Infinity tokens Python's json module emits by default.
import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SKILL_DIR = join(import.meta.dir, "..");
const UV_PYTHON = ["uv", "run", "--no-project", "--with-requirements", "requirements.txt", "python", "-I"];
const TIMEOUT_MS = 180_000; // a cold uv cache resolves numpy, pandas and scipy on the first run

let work = "";

function run(args: string[]): string {
  const proc = Bun.spawnSync([...UV_PYTHON, ...args], { cwd: SKILL_DIR, stdout: "pipe", stderr: "pipe" });
  if (proc.exitCode !== 0) {
    const tail = proc.stderr.toString().split("\n").slice(-15).join("\n");
    throw new Error(`exit ${proc.exitCode}: ${args.join(" ")}\n${tail}`);
  }
  return proc.stdout.toString();
}

function cli(...args: string[]): string {
  return run(["scripts/compute_metrics.py", ...args]);
}

function fold(name: string): string[] {
  return ["--predictions", join(work, `${name}_p.npy`), "--actuals", join(work, `${name}_a.npy`), "--timestamps", join(work, `${name}_t.npy`)];
}

beforeAll(() => {
  work = mkdtempSync(join(tmpdir(), "compute-metrics-cli-"));
  // Two folds. "normal": random predictions. "edge": constant predictions on strictly positive
  // returns, so the model is collapsed (is_collapsed True), no day loses (sortino_ratio = inf,
  // profit_factor = inf before its cap) and omega has no losses (NaN).
  run([
    "-c",
    `import sys, numpy as np
d = sys.argv[1]; n = 200; r = np.random.default_rng(0)
ts = np.datetime64("2026-01-01T00") + np.arange(n) * np.timedelta64(3, "h")
np.save(d + "/normal_p.npy", r.normal(size=n)); np.save(d + "/normal_a.npy", r.normal(size=n) * 0.01)
np.save(d + "/edge_p.npy", np.full(n, 0.5)); np.save(d + "/edge_a.npy", np.abs(r.normal(size=n)) * 0.01 + 1e-4)
for k in ("normal", "edge"): np.save(d + "/" + k + "_t.npy", ts)`,
    work,
  ]);
}, TIMEOUT_MS);

afterAll(() => {
  if (work) rmSync(work, { recursive: true, force: true });
});

describe("compute_metrics.py CLI writes strict JSON", () => {
  test("single fold to stdout", () => {
    const m = JSON.parse(cli(...fold("normal")));
    expect(typeof m.is_collapsed).toBe("boolean");
    expect(m.is_collapsed).toBe(false);
    expect(Number.isInteger(m.n_bars)).toBe(true);
    expect(m.n_bars).toBe(200);
    expect(typeof m.weekly_sharpe).toBe("number");
    expect(typeof m.psr).toBe("number");
  }, TIMEOUT_MS);

  test("collapsed fold with infinite and NaN metrics, via --output", () => {
    const out = join(work, "edge.json");
    expect(cli(...fold("edge"), "--output", out)).toBe("");
    const m = JSON.parse(readFileSync(out, "utf8"));
    expect(m.is_collapsed).toBe(true);
    expect(m.sortino_ratio).toBeNull(); // inf: JSON has no Infinity
    expect(m.omega_ratio).toBeNull(); // NaN
    expect(m.profit_factor).toBe(1e6); // inf, capped where the dict is built
  }, TIMEOUT_MS);

  test("--aggregate over the folds' own output", () => {
    const lines = ["normal", "edge"].map((k) => JSON.stringify(JSON.parse(cli(...fold(k)))));
    const jsonl = join(work, "folds.jsonl");
    writeFileSync(jsonl, `${lines.join("\n")}\n`);
    const agg = JSON.parse(cli("--results", jsonl, "--aggregate"));
    expect(agg.n_folds).toBe(2);
    expect(agg.collapse_count).toBe(1);
    expect(agg.collapse_rate).toBe(0.5);
  }, TIMEOUT_MS);
});
