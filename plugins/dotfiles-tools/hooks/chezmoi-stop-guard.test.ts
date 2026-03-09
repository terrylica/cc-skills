/**
 * Unit tests for chezmoi-stop-guard.mjs (Stop hook)
 *
 * Tests:
 * - Plan mode bypass (permission_mode === "plan")
 * - Loop prevention (stop_hook_active === true)
 * - Empty input handling
 * - Outside-project drift (silent allow)
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
      // {} means allow stop — no decision:block, no systemMessage
      expect(result.decision).toBeUndefined();
      expect(result.systemMessage).toBeUndefined();
    });

    it("should not bypass in default mode", async () => {
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: false,
        cwd: "/tmp/nonexistent-project",
      });
      // Should not have decision:block for a nonexistent project
      // (no chezmoi drift would be in-scope for /tmp/nonexistent-project)
      expect(result.decision).toBeUndefined();
    });
  });

  describe("loop prevention", () => {
    it("should allow stop when stop_hook_active is true", async () => {
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: true,
      });
      // Loop prevention allows stop with informational systemMessage
      expect(result.decision).toBeUndefined();
      expect(result.systemMessage).toContain("CHEZMOI-GUARD");
      expect(result.systemMessage).toContain("stop_hook_active");
    });
  });

  describe("scope check", () => {
    it("should silently allow stop when drift is outside cwd", async () => {
      // Use a CWD that definitely won't contain chezmoi drift
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: false,
        cwd: "/tmp/definitely-not-a-chezmoi-project-12345",
      });
      // Either {} (no drift) or {} (drift outside project) — both are silent allow
      expect(result.decision).toBeUndefined();
    });

    it("should silently allow stop when cwd is missing", async () => {
      // Missing CWD means we can't determine scope — don't nag
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: false,
      });
      expect(result.decision).toBeUndefined();
      expect(result.systemMessage).toBeUndefined();
    });

    it("should silently allow stop when cwd is home directory", async () => {
      // CWD === $HOME would make ALL chezmoi files appear in-scope — false positive
      const result = await runHook({
        permission_mode: "default",
        stop_hook_active: false,
        cwd: process.env.HOME,
      });
      expect(result.decision).toBeUndefined();
      expect(result.systemMessage).toBeUndefined();
    });
  });

  describe("empty/malformed input", () => {
    it("should handle empty input gracefully", async () => {
      const result = await runHook({});
      // Should not crash — either allow or inform, never throw
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
      // acceptEdits is not plan mode — should run normally
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
