/**
 * Hermetic tests for pretooluse-long-runtime-haiku-monitor-reminder.ts.
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-long-runtime-haiku-monitor-reminder.test.ts
 *
 * Hermetic: every test gets its own fresh temp directory. Subprocess runs get an environment of only
 * PATH, HOME and TMPDIR, with HOME and TMPDIR both inside that directory, and the in-process
 * orchestrator test points TMPDIR there too, so neither the developer's real /tmp stamps nor their
 * home directory can change an outcome, and no run leaves a file behind. No network.
 *
 * Mutation-structured: the companion runner (`...reminder.mutation.test.ts`) points this suite at a
 * mutated copy of the hook through HAIKU_MONITOR_HOOK_UNDER_TEST and requires it to FAIL for every
 * mutant. A test that no mutant can break is not testing anything, so each block below names the
 * mutants it exists to kill.
 */

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const HOOK_PATH = process.env.HAIKU_MONITOR_HOOK_UNDER_TEST
  ?? join(import.meta.dir, "pretooluse-long-runtime-haiku-monitor-reminder.ts");
const UNDER_MUTATION = process.env.HAIKU_MONITOR_HOOK_UNDER_TEST !== undefined;

const hook = (await import(HOOK_PATH)) as typeof import("./pretooluse-long-runtime-haiku-monitor-reminder.ts");
const { longRuntimeSignal, claimCooldown, buildReminder, REMINDER_COOLDOWN_MS } = hook;

const MINUTE = 60_000;
const UID_SUFFIX = typeof process.getuid === "function" ? String(process.getuid()) : process.env.USER ?? "user";

let sandbox: string;
beforeEach(() => {
  // realpath: on macOS os.tmpdir() is under /var, a symlink to /private/var.
  sandbox = realpathSync(mkdtempSync(join(tmpdir(), "haiku-monitor-test-")));
});
afterEach(() => {
  rmSync(sandbox, { recursive: true, force: true });
});

interface RunResult { exitCode: number; stdout: string; stderr: string; context?: string; decision?: string }

/** Run the hook as Claude Code does: JSON on stdin, a minimal environment. */
async function runHook(stdin: string, tmp: string = join(sandbox, "tmp")): Promise<RunResult> {
  const home = join(sandbox, "home");
  mkdirSync(home, { recursive: true });
  mkdirSync(tmp, { recursive: true });
  const proc = Bun.spawn(["bun", HOOK_PATH], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: home, TMPDIR: tmp },
    cwd: sandbox,
  });
  proc.stdin.write(stdin);
  proc.stdin.end();
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);
  const out = stdout.trim();
  const parsed = out === "" ? undefined : JSON.parse(out).hookSpecificOutput;
  return { exitCode, stdout: out, stderr, context: parsed?.additionalContext, decision: parsed?.permissionDecision };
}

function bashInput(toolInput: Record<string, unknown>, sessionId = "s-1", toolName = "Bash"): string {
  return JSON.stringify({ tool_name: toolName, tool_input: toolInput, session_id: sessionId, cwd: sandbox });
}

// Kills: threshold changed, `>` → `>=`, background check loosened or dropped, pueue check dropped or
// unanchored, escape check dropped, minutes arithmetic changed.
describe("which Bash calls count as long-running", () => {
  test("a backgrounded command fires", () => {
    expect(longRuntimeSignal({ command: "make check", run_in_background: true })).toBe("it runs in the background");
  });

  test.each([
    [{ command: "ls -la" }],
    [{ command: "ls -la", run_in_background: false }],
    [{ command: "make check", timeout: 120_000 }],
    [{ command: "make check", timeout: 300_000 }],
    [{}],
  ])("not long-running: %j", (input) => {
    expect(longRuntimeSignal(input)).toBeNull();
  });

  test("a timeout just above 5 minutes fires; exactly 5 minutes does not", () => {
    expect(longRuntimeSignal({ command: "x", timeout: 300_001 })).not.toBeNull();
    expect(longRuntimeSignal({ command: "x", timeout: 330_000 })).not.toBeNull();
    expect(longRuntimeSignal({ command: "x", timeout: 300_000 })).toBeNull();
  });

  test("the timeout is reported in whole minutes", () => {
    expect(longRuntimeSignal({ command: "x", timeout: 600_000 })).toBe("its timeout is 10 minutes");
    // 5.5 minutes rounds to 6. Added after the minutes-floor mutant survived a suite that only had 10.
    expect(longRuntimeSignal({ command: "x", timeout: 330_000 })).toBe("its timeout is 6 minutes");
  });

  test.each([
    ["pueue add -- make check"],
    ["cd repo && pueue add -- cargo build --release"],
    ["/opt/homebrew/bin/pueue add -- sleep 900"],
    ["/home/linuxbrew/.linuxbrew/bin/pueue add -- sleep 900"],
    ["true; pueue add -- x"],
    ["  pueue add -- x"],
    ["sudo pueue add -- x"],
    ["env A=1 pueue add -- x"],
    ["pueue --color never add -- x"],
    ["bash -c 'pueue add -- make check'"],
    ["ssh bigblack 'pueue add -- make check'"],
    ["id=$(pueue add --print-task-id -- make check)"],
  ])("a pueue add invocation fires: %s", (command) => {
    expect(longRuntimeSignal({ command })).toBe("it queues a pueue job");
  });

  test.each([
    ["pueue status"],
    ["pueue log 3"],
    ["pueue status -- add"],
    ["echo 'remember to pueue add it later'"],
    ["echo 'a; pueue add b'"],
    ["git commit -m 'x; pueue add later'"],
    ["grep -n 'pueue add' notes.md"],
    ["cat <<'EOF'\npueue add -- x\nEOF"],
    ["# pueue add -- x"],
    ["git add pueue.yml"],
  ])("a pueue mention or a short pueue command does not fire: %s", (command) => {
    expect(longRuntimeSignal({ command })).toBeNull();
  });

  test("the escape marker silences every trigger", () => {
    expect(longRuntimeSignal({ command: "make check # HAIKU-MONITOR-SKIP", run_in_background: true })).toBeNull();
    expect(longRuntimeSignal({ command: "pueue add -- x # HAIKU-MONITOR-SKIP" })).toBeNull();
    expect(longRuntimeSignal({ command: "x HAIKU-MONITOR-SKIP", timeout: 600_000 })).toBeNull();
  });
});

// Kills: cooldown length changed, `<` → `<=` or flipped, stamp not written, sessionless or
// traversal guard dropped or inverted, sessions sharing one stamp.
describe("cooldown: at most one reminder per 20 minutes per session", () => {
  const t0 = 1_800_000_000_000;

  test("the cooldown is 20 minutes", () => {
    expect(REMINDER_COOLDOWN_MS).toBe(20 * MINUTE);
  });

  test("first fires; repeats inside 20 minutes do not; at 20 minutes it fires again", () => {
    expect(claimCooldown("s", t0, sandbox)).toBe(true);
    expect(claimCooldown("s", t0 + 1 * MINUTE, sandbox)).toBe(false);
    expect(claimCooldown("s", t0 + 20 * MINUTE - 1, sandbox)).toBe(false);
    expect(claimCooldown("s", t0 + 20 * MINUTE, sandbox)).toBe(true);
    expect(claimCooldown("s", t0 + 21 * MINUTE, sandbox)).toBe(false);
  });

  test("sessions are independent", () => {
    expect(claimCooldown("a", t0, sandbox)).toBe(true);
    expect(claimCooldown("b", t0, sandbox)).toBe(true);
    expect(claimCooldown("a", t0 + MINUTE, sandbox)).toBe(false);
  });

  test("the stamp is one per-user directory under the base directory", () => {
    claimCooldown("s", t0, sandbox);
    expect(readdirSync(sandbox)).toEqual([`.claude-haiku-monitor-reminder-${UID_SUFFIX}`]);
    expect(existsSync(join(sandbox, `.claude-haiku-monitor-reminder-${UID_SUFFIX}`, "s.last"))).toBe(true);
  });

  test.each([[undefined], [""], [42]])("no usable session id (%p): always fires", (sid) => {
    expect(claimCooldown(sid, t0, sandbox)).toBe(true);
    expect(claimCooldown(sid, t0 + MINUTE, sandbox)).toBe(true);
    expect(readdirSync(sandbox)).toEqual([]);
  });

  test("a session id with a path separator writes nothing and always fires", () => {
    expect(claimCooldown("../escape", t0, sandbox)).toBe(true);
    expect(claimCooldown("../escape", t0 + MINUTE, sandbox)).toBe(true);
    expect(readdirSync(sandbox)).toEqual([]);
  });

  test("a corrupt stamp fires rather than silencing the session", () => {
    const dir = join(sandbox, `.claude-haiku-monitor-reminder-${UID_SUFFIX}`);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "s.last"), "not a number");
    expect(claimCooldown("s", t0, sandbox)).toBe(true);
  });

  test("an unwritable base directory still fires", () => {
    const file = join(sandbox, "a-file");
    writeFileSync(file, "");
    expect(claimCooldown("s", t0, file)).toBe(true);
  });
});

// Kills: a pinned or dated model id, a dropped instruction, the escape marker missing from the text.
describe("the reminder text", () => {
  const text = buildReminder("it runs in the background");

  test("names the model by the bare alias and nothing pinned", () => {
    expect(text).toContain('`model: "haiku"`');
    expect(text).not.toMatch(/model:\s*"(?!haiku")/);
    // A dated or numbered id may appear only as the counter-example on the "Never write" line.
    for (const line of text.split("\n")) {
      if (/claude-haiku-\d|haiku \d/.test(line)) expect(line).toContain("Never write");
    }
  });

  test.each([
    ["the trigger", "(it runs in the background)"],
    ["backgrounding", "`run_in_background: true`"],
    ["the cadence", "`sleep 240`"],
    ["the sleep's Bash timeout", "`timeout: 270000`"],
    ["the report channel", "its report as its final answer"],
    ["the hands-off rule", "never kills or restarts"],
    ["the escape", "HAIKU-MONITOR-SKIP"],
  ])("states %s", (_label, fragment) => {
    expect(text).toContain(fragment);
  });

  test("starts with its tag", () => {
    expect(text.startsWith("[LONG-RUNTIME-HEALTH-CHECK]")).toBe(true);
  });
});

// Kills: the tool-name check dropped, a deny or ask emitted, the cooldown not applied end to end,
// the stamp written outside TMPDIR, a crash on bad input.
describe("end to end, as Claude Code runs it (hermetic subprocess)", () => {
  test("a backgrounded Bash call gets the reminder and is never denied", async () => {
    const r = await runHook(bashInput({ command: "make check", run_in_background: true }));
    expect(r.exitCode).toBe(0);
    expect(r.context).toContain("[LONG-RUNTIME-HEALTH-CHECK]");
    expect(r.decision).toBeUndefined();
  });

  test("the second long call in the same session is silent; another session is not", async () => {
    const first = await runHook(bashInput({ command: "a", run_in_background: true }, "same"));
    const second = await runHook(bashInput({ command: "b", timeout: 600_000 }, "same"));
    const other = await runHook(bashInput({ command: "c", run_in_background: true }, "other"));
    expect(first.context).toBeDefined();
    expect(second.context).toBeUndefined();
    expect(second.decision).toBe("allow");
    expect(other.context).toBeDefined();
  });

  test("a short call is allowed with no context", async () => {
    const r = await runHook(bashInput({ command: "ls" }));
    expect(r.exitCode).toBe(0);
    expect(r.context).toBeUndefined();
    expect(r.decision).toBe("allow");
  });

  test("a subagent's call (agent_id present) is ignored, so a monitor never monitors itself", async () => {
    const input = JSON.parse(bashInput({ command: "sleep 240", run_in_background: true }, "sub"));
    const r = await runHook(JSON.stringify({ ...input, agent_id: "a123", agent_type: "general-purpose" }));
    expect(r.context).toBeUndefined();
    expect(r.decision).toBe("allow");
    const empty = await runHook(JSON.stringify({ ...input, agent_id: "" }));
    expect(empty.context).toBeDefined();
  });

  test("a non-Bash tool is ignored even when backgrounded", async () => {
    const r = await runHook(bashInput({ prompt: "x", run_in_background: true }, "s-1", "Agent"));
    expect(r.context).toBeUndefined();
    expect(r.decision).toBe("allow");
  });

  test("the stamp lands under TMPDIR, including a macOS-style path with spaces and a trailing slash", async () => {
    const tmp = join(sandbox, "var folders", "T") + "/";
    const r = await runHook(bashInput({ command: "x", run_in_background: true }, "mac"), tmp);
    expect(r.context).toBeDefined();
    expect(existsSync(join(tmp, `.claude-haiku-monitor-reminder-${UID_SUFFIX}`, "mac.last"))).toBe(true);
  });

  test("malformed stdin fails open", async () => {
    const r = await runHook("{not json");
    expect(r.exitCode).toBe(0);
    expect(r.context).toBeUndefined();
  });
});

// Integration with the real orchestrator. Skipped under mutation: it imports the unmutated hook.
describe.skipIf(UNDER_MUTATION)("inside the Bash guard orchestrator", () => {
  test("it is registered and its context reaches the aggregated response", async () => {
    // In-process run: point os.tmpdir() at the sandbox so the cooldown stamp stays out of /tmp.
    const realTmpdirEnv = process.env.TMPDIR;
    process.env.TMPDIR = sandbox;
    const { BASH_GUARD_REGISTRY, runBashGuards } = await import("./pretooluse-bash-guard-orchestrator.ts");
    expect(BASH_GUARD_REGISTRY.map((e) => e.name)).toContain("pretooluse-long-runtime-haiku-monitor-reminder");
    const result = await runBashGuards({
      tool_name: "Bash",
      tool_input: { command: "echo hi", run_in_background: true },
      cwd: sandbox,
      session_id: `orchestrator-${process.pid}-${Date.now()}`,
    });
    if (realTmpdirEnv === undefined) delete process.env.TMPDIR;
    else process.env.TMPDIR = realTmpdirEnv;
    expect(result.decision).toBe("allow");
    expect(result.additionalContext.join("\n")).toContain("[LONG-RUNTIME-HEALTH-CHECK]");
    expect(readdirSync(sandbox)).toContain(`.claude-haiku-monitor-reminder-${UID_SUFFIX}`);
  });
});
