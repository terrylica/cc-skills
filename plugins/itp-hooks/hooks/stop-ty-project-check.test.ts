import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// The Stop hook must act only on its own session's gate: never run for another
// session's edits, never delete another session's gate.
// Every run is hermetic: a private gate directory (CLAUDE_TY_EDIT_GATE_DIR) and a fake
// `ty` on PATH that records that it was invoked, so no live session state is touched
// and no real type checker runs.

const STOP_HOOK = join(import.meta.dir, "stop-ty-project-check.ts");
const SESSION_A = "session-a-0000";
const SESSION_B = "session-b-1111";

let root: string;
let gateDir: string;
let projectDir: string;
let fakeBinDir: string;
let tyRanMarker: string;

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "stop-ty-gate-"));
  gateDir = join(root, "gates");
  projectDir = join(root, "project");
  fakeBinDir = join(root, "bin");
  tyRanMarker = join(root, "ty-ran");
  mkdirSync(gateDir);
  mkdirSync(projectDir);
  mkdirSync(fakeBinDir);
  writeFileSync(join(projectDir, "a.py"), "x: int = 1\n");
  const fakeTy = join(fakeBinDir, "ty");
  writeFileSync(
    fakeTy,
    `#!/bin/sh\n: > "${tyRanMarker}"\necho "a.py:1:1: error: fake diagnostic"\nexit 0\n`,
  );
  chmodSync(fakeTy, 0o755);
});

afterEach(() => {
  rmSync(root, { recursive: true, force: true });
});

function gate(sessionId: string): string {
  return join(gateDir, `${sessionId}.edited`);
}

function runStopHook(payload: Record<string, unknown>): string {
  const env: Record<string, string | undefined> = {
    ...process.env,
    CLAUDE_TY_EDIT_GATE_DIR: gateDir,
    PATH: `${fakeBinDir}:${process.env.PATH ?? ""}`,
  };
  delete env.CLAUDE_SESSION_ID;
  const run = Bun.spawnSync(["bun", STOP_HOOK], {
    cwd: projectDir,
    env,
    stdin: Buffer.from(JSON.stringify({ hook_event_name: "Stop", ...payload })),
    stdout: "pipe",
    stderr: "pipe",
  });
  expect(run.exitCode).toBe(0);
  return run.stdout.toString();
}

describe("stop-ty-project-check per-session gate", () => {
  test("session B's Stop does not run for, or delete, session A's gate", () => {
    writeFileSync(gate(SESSION_A), "");
    const out = runStopHook({ session_id: SESSION_B });
    expect(JSON.parse(out)).toEqual({});
    expect(existsSync(tyRanMarker)).toBe(false);
    expect(existsSync(gate(SESSION_A))).toBe(true);
  });

  test("with its own gate it runs and deletes only its own gate file", () => {
    // The project check shares two machine-wide concurrency slots with live sessions'
    // ty runs and SKIPS (not queues) when both are busy, so allow a brief retry.
    let ran = false;
    let out = "";
    for (let attempt = 0; attempt < 3 && !ran; attempt++) {
      writeFileSync(gate(SESSION_A), "");
      writeFileSync(gate(SESSION_B), "");
      out = runStopHook({ session_id: SESSION_B });
      ran = existsSync(tyRanMarker);
      if (!ran) Bun.sleepSync(1000);
    }
    expect(ran).toBe(true);
    expect(out).toContain("[TY] Project type check: 1 error(s)");
    expect(existsSync(gate(SESSION_B))).toBe(false);
    expect(existsSync(gate(SESSION_A))).toBe(true);
    expect(existsSync(gateDir)).toBe(true);
  });

  test("missing session_id skips the check and deletes nothing", () => {
    writeFileSync(gate(SESSION_A), "");
    const out = runStopHook({});
    expect(JSON.parse(out)).toEqual({});
    expect(existsSync(tyRanMarker)).toBe(false);
    expect(existsSync(gate(SESSION_A))).toBe(true);
  });
});
