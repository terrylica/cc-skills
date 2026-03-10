/**
 * Unit tests for chezmoi-stop-guard.mjs (Stop hook)
 *
 * Tests:
 * - Plan mode bypass (permission_mode === "plan")
 * - Loop prevention (stop_hook_active === true)
 * - Source-dir scoping (only blocks in chezmoi source repo)
 * - Empty input handling
 *
 * Pattern: Same subprocess spawning as itp-hooks tests.
 * Stop hooks output JSON to stdout; exit 0 = allow, decision:block = block.
 */

import { describe, expect, it } from "bun:test";
import { spawn } from "bun";

const HOOK_PATH = import.meta.dir + "/chezmoi-stop-guard.mjs";

interface StopHookResponse {
  decision?: "block";
  reason?: string;
  systemMessage?: string;
}

async function runHook(input: object): Promise<StopHookResponse> {
  const proc = spawn({
    cmd: ["bun", "run", HOOK_PATH],
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, HOME: process.env.HOME },
  });

  proc.stdin.write(JSON.stringify(input));
  proc.stdin.end();

  const output = await new Response(proc.stdout).text();
  await proc.exited;

  const lines = output.trim().split("\n");
  const lastLine = lines[lines.length - 1];
  if (!lastLine || lastLine === "") return {};
  return JSON.parse(lastLine);
}

describe("chezmoi-stop-guard", () => {
  describe("plan mode bypass", () => {
    it("should allow stop silently in plan mode", async () => {
      const result = await runHook({
        permission_mode: "plan",
        stop_hook_active: false,
      });
      expect(result.decision).toBeUndefined();
      expect(result.systemMessage).toBeUndefined();
    });
  });

  describe("loop prevention", () => {
    it("should allow stop when stop_hook_active is true", async () => {
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: true,
      });
      expect(result.decision).toBeUndefined();
      expect(result.systemMessage).toContain("CHEZMOI-GUARD");
      expect(result.systemMessage).toContain("stop_hook_active");
    });
  });

  describe("source-dir scoping", () => {
    it("should silently allow when cwd is a random project", async () => {
      // Any project that isn't the chezmoi source dir should never be blocked
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: false,
        cwd: "/Users/terryli/eon/opendeviationbar-py",
      });
      expect(result.decision).toBeUndefined();
      expect(result.systemMessage).toBeUndefined();
    });

    it("should silently allow when cwd is /tmp", async () => {
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: false,
        cwd: "/tmp/some-project",
      });
      expect(result.decision).toBeUndefined();
    });

    it("should silently allow when cwd is missing", async () => {
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: false,
      });
      expect(result.decision).toBeUndefined();
      expect(result.systemMessage).toBeUndefined();
    });

    it("should silently allow when cwd is home directory", async () => {
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: false,
        cwd: process.env.HOME,
      });
      expect(result.decision).toBeUndefined();
      expect(result.systemMessage).toBeUndefined();
    });

    it("should silently allow when cwd is chezmoi source dir (no drift)", async () => {
      // Even in the source dir, no drift = no block
      // (chezmoi status is currently clean from earlier test cleanup)
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: false,
        cwd: "/Users/terryli/own/dotfiles",
      });
      expect(result.decision).toBeUndefined();
    });
  });

  describe("empty/malformed input", () => {
    it("should handle empty input gracefully", async () => {
      const result = await runHook({});
      expect(result).toBeDefined();
      expect(result.decision).not.toBe("block");
    });
  });

  describe("permission mode variants", () => {
    it("should not bypass in acceptEdits mode", async () => {
      const result = await runHook({
        permission_mode: "acceptEdits",
        stop_hook_active: false,
        cwd: "/tmp/nonexistent-project",
      });
      expect(result.decision).toBeUndefined();
    });

    it("should not bypass in bypassPermissions mode", async () => {
      const result = await runHook({
        permission_mode: "bypassPermissions",
        stop_hook_active: false,
        cwd: "/tmp/nonexistent-project",
      });
      expect(result.decision).toBeUndefined();
    });
  });
});
