/**
 * Tests for posttooluse-ty-type-check.ts when ty is NOT installed.
 *
 * Run with: bun test plugins/itp-hooks/hooks/posttooluse-ty-type-check.test.ts
 *
 * Measured 2026-10-17 on a host without ty: every Python write surfaced
 * "/bin/sh: 1: exec: ty: not found" as a hook error. The guarded spawn runs the tool through
 * `sh -c 'ulimit -t N; exec "$@"'`, so a missing binary was sh's exit 127, never `spawnFailed`,
 * and the classifier reported the shell's message as ty diagnostics. A missing tool must produce
 * at most one install advisory per session, and silence after that.
 */

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail as spawnGuarded } from "./lib/posttooluse-subhook-async-helpers-iter95.ts";
import { classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator as classify } from "./posttooluse-ty-type-check.ts";

// Not under a temp directory: the classifier skips throwaway scripts in /tmp by design.
const fixtureDir = join(import.meta.dir, `.ty-missing-fixture-${process.pid}`);
const pyFile = join(fixtureDir, "module.py");
const savedPath = process.env.PATH;

beforeAll(() => {
  mkdirSync(fixtureDir, { recursive: true });
  writeFileSync(pyFile, "x: int = 1\n");
});

afterAll(() => {
  process.env.PATH = savedPath;
  rmSync(fixtureDir, { recursive: true, force: true });
});

describe("a missing guarded tool is spawnFailed, not a diagnostic", () => {
  test("the guarded spawn of a program that does not exist reports spawnFailed", async () => {
    const result = await spawnGuarded(["definitely-not-installed-zz9", "check"], {
      timeoutMs: 2000,
      residentMemoryGuardedToolName: "definitely-not-installed-zz9",
    });
    expect(result.spawnFailed).toBe(true);
    expect(result.stdoutText).toBe("");
  });

  test("an installed guarded tool still runs and reports its exit code", async () => {
    const result = await spawnGuarded(["sh", "-c", "exit 3"], { timeoutMs: 2000, residentMemoryGuardedToolName: "sh" });
    expect(result.spawnFailed).toBe(false);
    expect(result.exitCode).toBe(3);
  });
});

describe("posttooluse ty check with ty absent", () => {
  test("first edit: one install advisory; later edits in the same session: silence", async () => {
    process.env.PATH = "/nonexistent-bin-dir-zz9";
    const sessionId = `ty-missing-test-${process.pid}-${Date.now()}`;
    const input = { tool_name: "Write", tool_input: { file_path: pyFile }, session_id: sessionId } as never;
    try {
      const first = await classify(input);
      const second = await classify(input);
      expect(first.kind).toBe("additional_context");
      if (first.kind === "additional_context") {
        expect(first.message).toContain("not installed");
        expect(first.message).not.toContain("exec: ty: not found");
      }
      expect(second.kind).toBe("noop");
    } finally {
      process.env.PATH = savedPath;
    }
  });
});
