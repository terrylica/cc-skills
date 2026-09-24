#!/usr/bin/env bun
/**
 * Unit tests for allowWithInput() in pretooluse-helpers.
 *
 * Run with: bun test plugins/itp-hooks/hooks/lib/pretooluse-helpers.test.ts
 *
 * Tests the Zod schema validation layer that prevents updatedInput
 * from corrupting tool schemas (e.g., injecting `env` into AskUserQuestion).
 *
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/13439
 */

import { describe, it, expect, spyOn } from "bun:test";
import { allowWithInput, hasToolSchema } from "../pretooluse-helpers.ts";

/**
 * Capture stdout output from allowWithInput() calls.
 * The hook protocol writes JSON to stdout via console.log().
 */
function captureOutput(fn: () => void): string[] {
  const lines: string[] = [];
  const spy = spyOn(console, "log").mockImplementation((...args: unknown[]) => {
    lines.push(String(args[0]));
  });
  // Also suppress stderr from trackHookError
  const errSpy = spyOn(console, "error").mockImplementation(() => {});
  try {
    fn();
  } finally {
    spy.mockRestore();
    errSpy.mockRestore();
  }
  return lines;
}

function parseHookOutput(line: string): Record<string, unknown> {
  return JSON.parse(line) as Record<string, unknown>;
}

describe("allowWithInput", () => {
  it("emits updatedInput for valid Bash command", () => {
    const lines = captureOutput(() => {
      allowWithInput("test-hook", "Bash", { command: "ls -la" });
    });

    expect(lines).toHaveLength(1);
    const output = parseHookOutput(lines[0]);
    const hook = output.hookSpecificOutput as Record<string, unknown>;
    expect(hook.permissionDecision).toBe("allow");
    expect(hook.updatedInput).toEqual({ command: "ls -la" });
  });

  // REGRESSION GUARD. For AskUserQuestion, `updatedInput` is where the dialog's answers travel, so a
  // hook that sends it is taken as having answered: the dialog never renders and the tool returns
  // "The user did not answer the questions." (86 of 86 such calls, 2026-09-12 to 2026-09-24). A
  // VALID schema must not be enough to mutate it.
  it("refuses to mutate AskUserQuestion even when the input is schema-valid", () => {
    const lines = captureOutput(() => {
      allowWithInput("test-hook", "AskUserQuestion", { questions: [] });
    });

    expect(lines).toHaveLength(1);
    const output = parseHookOutput(lines[0]);
    const hook = output.hookSpecificOutput as Record<string, unknown>;
    expect(hook.permissionDecision).toBe("allow");
    expect(hook.updatedInput).toBeUndefined();
  });

  it("still falls back to plain allow when an AskUserQuestion mutation is malformed", () => {
    // The fallback is what makes mutating this tool safe: a shape the registry cannot express is
    // refused and counted, never applied.
    const lines = captureOutput(() => {
      allowWithInput("test-hook", "AskUserQuestion", {
        questions: [{ question: "q", header: "h", multiSelect: false, options: [{ label: "A" }] }],
      });
    });

    const hook = parseHookOutput(lines[0]).hookSpecificOutput as Record<string, unknown>;
    expect(hook.permissionDecision).toBe("allow");
    expect(hook.updatedInput).toBeUndefined();
  });

  it("falls back to plain allow for Bash with extra fields (.strict rejects env)", () => {
    const lines = captureOutput(() => {
      allowWithInput("test-hook", "Bash", { command: "ls", env: {} });
    });

    expect(lines).toHaveLength(1);
    const output = parseHookOutput(lines[0]);
    const hook = output.hookSpecificOutput as Record<string, unknown>;
    expect(hook.permissionDecision).toBe("allow");
    // No updatedInput — Zod .strict() rejected the `env` field
    expect(hook.updatedInput).toBeUndefined();
  });

  it("falls back to plain allow for unknown tools", () => {
    const lines = captureOutput(() => {
      allowWithInput("test-hook", "FutureTool", { data: "test" });
    });

    expect(lines).toHaveLength(1);
    const output = parseHookOutput(lines[0]);
    const hook = output.hookSpecificOutput as Record<string, unknown>;
    expect(hook.permissionDecision).toBe("allow");
    expect(hook.updatedInput).toBeUndefined();
  });

  it("preserves all valid fields in updatedInput", () => {
    const lines = captureOutput(() => {
      allowWithInput("test-hook", "Bash", {
        command: "echo hello",
        description: "Print greeting",
        timeout: 5000,
      });
    });

    expect(lines).toHaveLength(1);
    const output = parseHookOutput(lines[0]);
    const hook = output.hookSpecificOutput as Record<string, unknown>;
    expect(hook.updatedInput).toEqual({
      command: "echo hello",
      description: "Print greeting",
      timeout: 5000,
    });
  });
});

describe("hasToolSchema", () => {
  it("returns true for Bash", () => {
    expect(hasToolSchema("Bash")).toBe(true);
  });

  it("returns true for all 8 registered tools", () => {
    for (const name of ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "NotebookEdit", "LSP"]) {
      expect(hasToolSchema(name)).toBe(true);
    }
  });

  it("returns true for AskUserQuestion, which gained a schema with the premise annotator", () => {
    expect(hasToolSchema("AskUserQuestion")).toBe(true);
  });

  it("returns false for unknown tools", () => {
    expect(hasToolSchema("FutureTool")).toBe(false);
  });
});
