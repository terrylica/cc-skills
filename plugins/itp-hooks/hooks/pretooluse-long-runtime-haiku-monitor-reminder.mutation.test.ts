/**
 * Mutation testing for pretooluse-long-runtime-haiku-monitor-reminder.ts.
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-long-runtime-haiku-monitor-reminder.mutation.test.ts
 *
 * Each mutant is one deliberate defect in the hook. The runner writes the mutated hook into its own
 * fresh temp directory, rewrites its relative imports to absolute paths into this directory (so the
 * real helpers load and nothing is written into the source tree), and runs the hermetic suite against
 * it through HAIKU_MONITOR_HOOK_UNDER_TEST. A mutant the suite does not fail on has SURVIVED: either
 * the suite is missing a test or the mutated code is dead. Either way this file fails.
 *
 * A control run (no mutation) must PASS first, so a broken harness cannot report every mutant killed.
 * Every search string must occur exactly once in the hook, so an edit to the hook cannot silently turn
 * a mutant into a no-op; update the mutant along with the code.
 */

import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const HOOKS_DIR = import.meta.dir;
const HOOK_SOURCE = readFileSync(join(HOOKS_DIR, "pretooluse-long-runtime-haiku-monitor-reminder.ts"), "utf8");
const SUITE = join(HOOKS_DIR, "pretooluse-long-runtime-haiku-monitor-reminder.test.ts");

interface Mutant { id: string; search: string; replace: string }

const MUTANTS: readonly Mutant[] = [
  // Detection
  { id: "threshold-raised", search: "LONG_RUNTIME_THRESHOLD_MS = 5 * 60 * 1000", replace: "LONG_RUNTIME_THRESHOLD_MS = 6 * 60 * 1000" },
  { id: "threshold-inclusive", search: "toolInput.timeout > LONG_RUNTIME_THRESHOLD_MS", replace: "toolInput.timeout >= LONG_RUNTIME_THRESHOLD_MS" },
  { id: "timeout-check-dropped", search: 'typeof toolInput.timeout === "number" &&', replace: "false &&" },
  { id: "minutes-floor", search: "Math.round(toolInput.timeout / 60000)", replace: "Math.floor(toolInput.timeout / 60000)" },
  { id: "background-loosened", search: "toolInput.run_in_background === true", replace: "toolInput.run_in_background !== false" },
  { id: "background-dropped", search: 'if (toolInput.run_in_background === true) return "it runs in the background";', replace: "" },
  { id: "escape-dropped", search: "if (command.includes(ESCAPE_MARKER)) return null;", replace: "" },
  { id: "pueue-dropped", search: 'if (PUEUE_ADD_AT_COMMAND_POSITION.test(command)) return "it queues a pueue job";', replace: "" },
  { id: "pueue-unanchored", search: "/(?:^|[;&|(]\\s*|\\n\\s*)(?:\\S+\\/)?pueue", replace: "/(?:)(?:\\S+\\/)?pueue" },
  { id: "pueue-no-path-prefix", search: "(?:\\S+\\/)?pueue", replace: "pueue" },
  { id: "pueue-any-subcommand", search: "pueue\\s+(?:--?\\S+\\s+)*add\\b", replace: "pueue\\s+\\w+" },
  // Cooldown
  { id: "cooldown-shortened", search: "REMINDER_COOLDOWN_MS = 20 * 60 * 1000", replace: "REMINDER_COOLDOWN_MS = 10 * 60 * 1000" },
  { id: "cooldown-inclusive", search: "nowMs - last < REMINDER_COOLDOWN_MS", replace: "nowMs - last <= REMINDER_COOLDOWN_MS" },
  { id: "cooldown-never-silences", search: "if (Number.isFinite(last) && nowMs - last < REMINDER_COOLDOWN_MS) return false;", replace: "" },
  { id: "cooldown-corrupt-silences", search: "Number.isFinite(last) && ", replace: "!Number.isNaN(last) || " },
  { id: "stamp-not-written", search: "writeFileSync(stamp, String(nowMs));", replace: "" },
  { id: "sessions-share-stamp", search: "`${sessionId}.last`", replace: '"shared.last"' },
  { id: "sessionless-silenced", search: '|| /[/\\\\]/.test(sessionId)) return true;', replace: '|| /[/\\\\]/.test(sessionId)) return false;' },
  { id: "traversal-guard-dropped", search: ' || /[/\\\\]/.test(sessionId)', replace: "" },
  { id: "write-error-silences", search: "// Unwritable /tmp: remind anyway.", replace: "return false;" },
  { id: "stamp-in-slash-tmp", search: "baseDir: string = tmpdir()", replace: 'baseDir: string = "/tmp"' },
  // Text
  { id: "model-pinned", search: '`model: \\"haiku\\"`', replace: '`model: \\"claude-haiku-4-5\\"`' },
  { id: "foreground-monitor", search: "`run_in_background: true`. ", replace: "" },
  { id: "cadence-dropped", search: "(`sleep 240` between checks, ", replace: "(" },
  { id: "report-channel-dropped", search: "ends with its report as its final answer, which reaches you as a completion notification, and it ", replace: "" },
  { id: "monitor-may-kill", search: "It never kills or restarts anything", replace: "It may kill a stalled run" },
  { id: "escape-not-mentioned", search: "put ${ESCAPE_MARKER} in the command", replace: "say so" },
  { id: "tag-renamed", search: "`[LONG-RUNTIME-HEALTH-CHECK] ", replace: "`[HEALTH] " },
  { id: "signal-not-shown", search: "(${signal})", replace: "" },
  // Wiring
  { id: "any-tool", search: 'if (input.tool_name !== "Bash") {', replace: "if (false) {" },
  { id: "denies", search: 'hookEventName: "PreToolUse",\n      additionalContext', replace: 'hookEventName: "PreToolUse",\n      permissionDecision: "deny",\n      additionalContext' },
  { id: "silent", search: "additionalContext: buildReminder(signal),", replace: "" },
];

/** Run the hermetic suite against `source`; returns the bun test exit code. */
async function runSuiteAgainst(source: string): Promise<{ exitCode: number; tail: string }> {
  const dir = mkdtempSync(join(tmpdir(), "haiku-monitor-mutant-"));
  try {
    const path = join(dir, "hook-under-test.ts");
    writeFileSync(path, source.replaceAll('from "./', `from "${HOOKS_DIR}/`));
    const proc = Bun.spawn(["bun", "test", SUITE], {
      stdout: "pipe",
      stderr: "pipe",
      env: { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: dir, TMPDIR: dir, HAIKU_MONITOR_HOOK_UNDER_TEST: path },
      cwd: dir,
    });
    const [, stderr, exitCode] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
      proc.exited,
    ]);
    return { exitCode, tail: stderr.split("\n").slice(-6).join("\n") };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** Bounded concurrency: never more than this many bun test processes at once. */
const CONCURRENCY = 4;

async function mapBounded<T, R>(items: readonly T[], fn: (item: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(CONCURRENCY, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i]);
    }
  });
  await Promise.all(workers);
  return results;
}

describe("mutation testing", () => {
  test("every mutant targets exactly one site in the current hook", () => {
    for (const m of MUTANTS) {
      expect({ id: m.id, occurrences: HOOK_SOURCE.split(m.search).length - 1 }).toEqual({ id: m.id, occurrences: 1 });
    }
    expect(new Set(MUTANTS.map((m) => m.id)).size).toBe(MUTANTS.length);
  });

  test("control: the unmutated hook passes the suite through the same harness", async () => {
    const { exitCode, tail } = await runSuiteAgainst(HOOK_SOURCE);
    expect({ exitCode, tail }).toEqual({ exitCode: 0, tail: expect.any(String) });
  }, 60_000);

  test("every mutant is killed", async () => {
    const outcomes = await mapBounded(MUTANTS, async (m) => {
      const { exitCode } = await runSuiteAgainst(HOOK_SOURCE.replace(m.search, m.replace));
      return { id: m.id, killed: exitCode !== 0 };
    });
    const survivors = outcomes.filter((o) => !o.killed).map((o) => o.id);
    expect(survivors).toEqual([]);
  }, 300_000);
});
