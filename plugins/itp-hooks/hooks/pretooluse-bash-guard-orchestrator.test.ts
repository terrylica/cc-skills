/**
 * Differential test for the PreToolUse:Bash guard orchestrator (#111).
 *
 * The orchestrator must decide exactly what the separate hooks decided before it. For each command
 * in the corpus, every guard in BASH_GUARD_REGISTRY is run STANDALONE (its own bun process, as
 * Claude Code ran it) and the outputs are folded with Claude Code's precedence, deny > ask > allow.
 * The orchestrator's single response must match: the same decision, the deciding guard's reason
 * verbatim, and the same additionalContext.
 *
 * HOME and cwd are throwaway directories, so guards that read per-user state see the same (empty)
 * state in both modes and nothing on the machine is touched.
 */
import { afterAll, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { BASH_GUARD_REGISTRY, runBashGuards, toHookResponse } from "./pretooluse-bash-guard-orchestrator.ts";
import { runGuardMainInProcess, type PreToolUseInput } from "./pretooluse-helpers.ts";

const HOOKS_DIR = new URL(".", import.meta.url).pathname;
const ORCHESTRATOR = join(HOOKS_DIR, "pretooluse-bash-guard-orchestrator.ts");
const sandbox = mkdtempSync(join(tmpdir(), "bash-orchestrator-test-"));
const fakeHome = mkdtempSync(join(tmpdir(), "bash-orchestrator-home-"));
afterAll(() => {
  rmSync(sandbox, { recursive: true, force: true });
  rmSync(fakeHome, { recursive: true, force: true });
});

// One command per guard family, plus pass-throughs and wrapped forms. Each deny/ask/context case
// was checked to fire standalone; the pass-throughs check that nothing fires.
const CORPUS: string[] = [
  "ls -la",
  "echo hello",
  "pkill -f node",
  "bash -c 'pkill -f node'",
  "pip install requests",
  "git checkout -b feature/x",
  "claude -p 'summarise this'",
  "awk '{print $1}' data/ticks.parquet",
  "npm install typescript@5",
  "tccutil reset All com.example.app",
  "pkill node -f",
  "open -a 'Google Chrome' --args --remote-debugging-port=9222",
  "pueue add -- sleep 1",
  "git push origin main",
];

function inputFor(command: string): PreToolUseInput {
  return {
    tool_name: "Bash",
    tool_input: { command },
    cwd: sandbox,
    session_id: "bash-orchestrator-test",
    tool_use_id: "toolu_test",
    hook_event_name: "PreToolUse",
  } as PreToolUseInput;
}

const ENV = { ...process.env, HOME: fakeHome };

interface Folded {
  decision: string;
  reason?: string;
  additionalContext?: string;
}

/** What Claude Code saw from the separate hooks, folded with its precedence. */
function standalone(command: string): Folded {
  const stdin = Buffer.from(JSON.stringify(inputFor(command)));
  let deny: string | undefined;
  let ask: string | undefined;
  const contexts: string[] = [];
  for (const entry of BASH_GUARD_REGISTRY) {
    const file = [".ts", ".mjs"].map((ext) => join(HOOKS_DIR, entry.name + ext)).find((p) => Bun.file(p).size > 0);
    if (!file) throw new Error(`no file for ${entry.name}`);
    const proc = Bun.spawnSync(["bun", file], { stdin, stdout: "pipe", stderr: "pipe", env: ENV, cwd: sandbox });
    for (const line of proc.stdout.toString().split("\n")) {
      if (!line.trim().startsWith("{")) continue;
      const hso = JSON.parse(line).hookSpecificOutput ?? {};
      if (hso.permissionDecision === "deny") deny ??= hso.permissionDecisionReason;
      if (hso.permissionDecision === "ask") ask ??= hso.permissionDecisionReason;
      if (hso.additionalContext) contexts.push(hso.additionalContext);
    }
  }
  if (deny !== undefined) return { decision: "deny", reason: deny };
  const additionalContext = contexts.length > 0 ? contexts.join("\n\n") : undefined;
  if (ask !== undefined) return { decision: "ask", reason: ask, additionalContext };
  return { decision: "allow", additionalContext };
}

function orchestrated(command: string): Folded {
  const proc = Bun.spawnSync(["bun", ORCHESTRATOR], {
    stdin: Buffer.from(JSON.stringify(inputFor(command))),
    stdout: "pipe",
    stderr: "pipe",
    env: ENV,
    cwd: sandbox,
  });
  const lines = proc.stdout.toString().split("\n").filter((l) => l.trim());
  expect(lines).toHaveLength(1);
  const hso = JSON.parse(lines[0]).hookSpecificOutput;
  return { decision: hso.permissionDecision, reason: hso.permissionDecisionReason, additionalContext: hso.additionalContext };
}

describe("orchestrator decides exactly what the separate hooks decided", () => {
  for (const command of CORPUS) {
    test(command, () => {
      expect(orchestrated(command)).toEqual(standalone(command));
    }, 120_000);
  }

  test("the corpus exercises deny and context, not only allow", () => {
    const decisions = CORPUS.map((c) => standalone(c));
    expect(decisions.some((d) => d.decision === "deny")).toBe(true);
    expect(decisions.some((d) => d.additionalContext)).toBe(true);
    expect(decisions.some((d) => d.decision === "allow" && !d.additionalContext)).toBe(true);
  }, 300_000);
});

const guard = (emit: object | null, opts: { throws?: boolean; hangs?: boolean } = {}) => async () => {
  if (opts.throws) throw new Error("boom");
  if (opts.hangs) await new Promise(() => {});
  if (emit) {
    const { output } = await import("./pretooluse-helpers.ts");
    output(emit);
  }
};
const decide = (kind: string, reason?: string, additionalContext?: string) => ({
  hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: kind, permissionDecisionReason: reason, additionalContext },
});

describe("aggregation", () => {
  const input = inputFor("anything");

  test("deny outranks an earlier ask", async () => {
    const r = await runBashGuards(input, [
      { name: "a", main: guard(decide("ask", "asked")), timeoutMs: 1000, description: "test" },
      { name: "d", main: guard(decide("deny", "denied")), timeoutMs: 1000, description: "test" },
    ]);
    expect(r).toMatchObject({ decision: "deny", reason: "denied", decidedBy: "d" });
  });

  test("the first deny wins and later guards do not run", async () => {
    let ranLater = false;
    const r = await runBashGuards(input, [
      { name: "d1", main: guard(decide("deny", "first")), timeoutMs: 1000, description: "test" },
      { name: "d2", main: async () => { ranLater = true; }, timeoutMs: 1000, description: "test" },
    ]);
    expect(r.reason).toBe("first");
    expect(ranLater).toBe(false);
  });

  test("a guard that throws or hangs is skipped (fail-open), and the rest still decide", async () => {
    const r = await runBashGuards(input, [
      { name: "throws", main: guard(null, { throws: true }), timeoutMs: 1000, description: "test" },
      { name: "hangs", main: guard(null, { hangs: true }), timeoutMs: 50, description: "test" },
      { name: "nudge", main: guard({ hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: "hint" } }), timeoutMs: 1000, description: "test" },
    ]);
    expect(r.skipped).toEqual(["throws", "hangs"]);
    expect(toHookResponse(r)).toEqual({
      hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow", additionalContext: "hint" },
    });
  });

  test("context is not attached to a deny", () => {
    const response = toHookResponse({ decision: "deny", reason: "no", decidedBy: "d", additionalContext: ["hint"], skipped: [] });
    expect(response).toEqual({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: "no" } });
  });

  test("a guard's late output after its timeout lands in its own run, not the next guard's", async () => {
    const { output } = await import("./pretooluse-helpers.ts");
    const late = async () => {
      await Bun.sleep(80);
      output(decide("deny", "too late"));
    };
    const r = await runBashGuards(input, [
      { name: "late", main: late, timeoutMs: 20, description: "test" },
      { name: "slow-allow", main: async () => { await Bun.sleep(150); }, timeoutMs: 1000, description: "test" },
    ]);
    expect(r.decision).toBe("allow");
    expect(r.skipped).toEqual(["late"]);
  });

  test("every registry entry is a guard file's exported main", async () => {
    for (const entry of BASH_GUARD_REGISTRY) {
      expect(typeof entry.main).toBe("function");
      expect(entry.timeoutMs).toBeGreaterThan(0);
    }
    expect(new Set(BASH_GUARD_REGISTRY.map((e) => e.name)).size).toBe(BASH_GUARD_REGISTRY.length);
    expect(await runGuardMainInProcess(async () => {}, input)).toEqual([]);
  });
});
