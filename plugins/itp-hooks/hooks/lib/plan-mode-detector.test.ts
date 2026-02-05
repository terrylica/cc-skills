#!/usr/bin/env bun
/**
 * Tests for plan-mode-detector.ts
 *
 * ADR: /docs/adr/2026-02-05-plan-mode-detection-hooks.md
 */

import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  isPlanMode,
  isQuickPlanMode,
  getActivePlanFiles,
  PLAN_MODE_CONFIG,
  type HookInputWithPlanMode,
} from "./plan-mode-detector.ts";

// ============================================================================
// Test Fixtures
// ============================================================================

function createMockInput(
  overrides: Partial<HookInputWithPlanMode> = {}
): HookInputWithPlanMode {
  return {
    tool_name: "Write",
    tool_input: {
      file_path: "/tmp/test.md",
      content: "test content",
    },
    tool_use_id: "toolu_test123",
    cwd: "/tmp",
    ...overrides,
  };
}

// ============================================================================
// isPlanMode Tests
// ============================================================================

describe("isPlanMode", () => {
  describe("permission_mode detection", () => {
    test("returns true when permission_mode is 'plan'", () => {
      const input = createMockInput({ permission_mode: "plan" });
      const result = isPlanMode(input);

      expect(result.inPlanMode).toBe(true);
      expect(result.signals.permissionModeIsPlan).toBe(true);
      expect(result.permissionMode).toBe("plan");
      expect(result.reason).toContain("permission_mode is 'plan'");
    });

    test("returns false when permission_mode is 'default'", () => {
      const input = createMockInput({ permission_mode: "default" });
      const result = isPlanMode(input);

      expect(result.inPlanMode).toBe(false);
      expect(result.signals.permissionModeIsPlan).toBe(false);
    });

    test("returns false when permission_mode is undefined", () => {
      const input = createMockInput({ permission_mode: undefined });
      const result = isPlanMode(input);

      expect(result.signals.permissionModeIsPlan).toBe(false);
    });

    test("skips permission check when checkPermission is false", () => {
      const input = createMockInput({ permission_mode: "plan" });
      const result = isPlanMode(input, { checkPermission: false });

      expect(result.signals.permissionModeIsPlan).toBe(false);
      // But still not in plan mode because path check is false too
      expect(result.inPlanMode).toBe(false);
    });
  });

  describe("file path detection", () => {
    test("returns true for ~/.claude/plans/ paths", () => {
      const input = createMockInput({
        tool_input: {
          file_path: `${process.env.HOME}/.claude/plans/abstract-unicorn.md`,
        },
      });
      const result = isPlanMode(input);

      expect(result.inPlanMode).toBe(true);
      expect(result.signals.filePathIsPlanFile).toBe(true);
      expect(result.reason).toContain("file path matches plan directory");
    });

    test("returns true for /plans/*.md paths", () => {
      const input = createMockInput({
        tool_input: { file_path: "/tmp/plans/my-plan.md" },
      });
      const result = isPlanMode(input);

      expect(result.inPlanMode).toBe(true);
      expect(result.signals.filePathIsPlanFile).toBe(true);
    });

    test("returns true for /tmp/plans/ paths", () => {
      const input = createMockInput({
        tool_input: { file_path: "/tmp/plans/archived-plan.md" },
      });
      const result = isPlanMode(input);

      expect(result.inPlanMode).toBe(true);
      expect(result.signals.filePathIsPlanFile).toBe(true);
    });

    test("returns false for non-plan paths", () => {
      const input = createMockInput({
        tool_input: { file_path: "/tmp/docs/README.md" },
      });
      const result = isPlanMode(input);

      expect(result.signals.filePathIsPlanFile).toBe(false);
    });

    test("returns true for any file in plans directory (defensive)", () => {
      // Note: The pattern /\/plans\/.*\.md$/i requires .md extension
      // but /\/\.claude\/plans\//i catches any file in ~/.claude/plans/
      // For /tmp/plans/ we use the first pattern which requires .md
      const input = createMockInput({
        tool_input: { file_path: "/tmp/plans/script.sh" },
      });
      const result = isPlanMode(input);

      // /tmp/plans/script.sh matches /\/plans\// but not .*\.md$
      // Actually checking: the pattern /\/plans\/.*\.md$/i won't match .sh
      // But /\/tmp\/plans\//i pattern exists which will match
      expect(result.signals.filePathIsPlanFile).toBe(true);
    });

    test("skips path check when checkPath is false", () => {
      const input = createMockInput({
        tool_input: { file_path: "/tmp/plans/my-plan.md" },
      });
      const result = isPlanMode(input, { checkPath: false });

      expect(result.signals.filePathIsPlanFile).toBe(false);
    });
  });

  describe("combined signals", () => {
    test("returns true when both permission_mode and path match", () => {
      const input = createMockInput({
        permission_mode: "plan",
        tool_input: { file_path: "/tmp/plans/my-plan.md" },
      });
      const result = isPlanMode(input);

      expect(result.inPlanMode).toBe(true);
      expect(result.signals.permissionModeIsPlan).toBe(true);
      expect(result.signals.filePathIsPlanFile).toBe(true);
      expect(result.reason).toContain("permission_mode is 'plan'");
      expect(result.reason).toContain("file path matches");
    });

    test("returns false when all checks disabled", () => {
      const input = createMockInput({
        permission_mode: "plan",
        tool_input: { file_path: "/tmp/plans/my-plan.md" },
      });
      const result = isPlanMode(input, {
        checkPermission: false,
        checkPath: false,
        checkActiveFiles: false,
      });

      expect(result.inPlanMode).toBe(false);
    });
  });

  describe("null input handling", () => {
    test("returns false for null input", () => {
      const result = isPlanMode(null);

      expect(result.inPlanMode).toBe(false);
      expect(result.permissionMode).toBeUndefined();
      expect(result.filePath).toBeUndefined();
      expect(result.reason).toBe("no input provided");
    });
  });

  describe("context output", () => {
    test("includes filePath in context", () => {
      const input = createMockInput({
        tool_input: { file_path: "/tmp/test.md" },
      });
      const result = isPlanMode(input);

      expect(result.filePath).toBe("/tmp/test.md");
    });

    test("includes permissionMode in context", () => {
      const input = createMockInput({ permission_mode: "acceptEdits" });
      const result = isPlanMode(input);

      expect(result.permissionMode).toBe("acceptEdits");
    });
  });
});

// ============================================================================
// isQuickPlanMode Tests
// ============================================================================

describe("isQuickPlanMode", () => {
  test("returns true for permission_mode plan", () => {
    const input = createMockInput({ permission_mode: "plan" });
    expect(isQuickPlanMode(input)).toBe(true);
  });

  test("returns true for plan file path", () => {
    const input = createMockInput({
      tool_input: { file_path: "/tmp/plans/test.md" },
    });
    expect(isQuickPlanMode(input)).toBe(true);
  });

  test("returns false for null input", () => {
    expect(isQuickPlanMode(null)).toBe(false);
  });

  test("returns false for non-plan inputs", () => {
    const input = createMockInput({
      permission_mode: "default",
      tool_input: { file_path: "/tmp/docs/README.md" },
    });
    expect(isQuickPlanMode(input)).toBe(false);
  });
});

// ============================================================================
// getActivePlanFiles Tests
// ============================================================================

describe("getActivePlanFiles", () => {
  const testPlanDir = "/tmp/test-claude-plans";

  beforeEach(() => {
    // Create test directory
    mkdirSync(testPlanDir, { recursive: true });
    // Temporarily override config for testing
    (PLAN_MODE_CONFIG as { planDirectory: string }).planDirectory = testPlanDir;
  });

  afterEach(() => {
    // Clean up
    rmSync(testPlanDir, { recursive: true, force: true });
    // Restore config
    (PLAN_MODE_CONFIG as { planDirectory: string }).planDirectory = `${process.env.HOME}/.claude/plans`;
  });

  test("returns empty array when no plan files exist", () => {
    const files = getActivePlanFiles();
    expect(files).toEqual([]);
  });

  test("returns .md files in plans directory", () => {
    writeFileSync(join(testPlanDir, "abstract-unicorn.md"), "plan content");
    writeFileSync(join(testPlanDir, "fluffy-dragon.md"), "another plan");

    const files = getActivePlanFiles();
    expect(files).toContain("abstract-unicorn.md");
    expect(files).toContain("fluffy-dragon.md");
    expect(files.length).toBe(2);
  });

  test("ignores hidden files", () => {
    writeFileSync(join(testPlanDir, ".hidden.md"), "hidden");
    writeFileSync(join(testPlanDir, "visible.md"), "visible");

    const files = getActivePlanFiles();
    expect(files).not.toContain(".hidden.md");
    expect(files).toContain("visible.md");
  });

  test("only returns .md files", () => {
    writeFileSync(join(testPlanDir, "plan.md"), "markdown");
    writeFileSync(join(testPlanDir, "script.sh"), "bash");
    writeFileSync(join(testPlanDir, "data.json"), "json");

    const files = getActivePlanFiles();
    expect(files).toEqual(["plan.md"]);
  });
});

// ============================================================================
// Active Plan Files Signal Tests (with checkActiveFiles: true)
// ============================================================================

describe("isPlanMode with checkActiveFiles", () => {
  const testPlanDir = "/tmp/test-claude-plans-signal";

  beforeEach(() => {
    mkdirSync(testPlanDir, { recursive: true });
    (PLAN_MODE_CONFIG as { planDirectory: string }).planDirectory = testPlanDir;
  });

  afterEach(() => {
    rmSync(testPlanDir, { recursive: true, force: true });
    (PLAN_MODE_CONFIG as { planDirectory: string }).planDirectory = `${process.env.HOME}/.claude/plans`;
  });

  test("detects active plan files when checkActiveFiles is true", () => {
    writeFileSync(join(testPlanDir, "active-plan.md"), "plan content");

    const input = createMockInput({
      permission_mode: "default",
      tool_input: { file_path: "/tmp/not-a-plan.md" },
    });

    const result = isPlanMode(input, { checkActiveFiles: true });

    expect(result.inPlanMode).toBe(true);
    expect(result.signals.activePlanFilesExist).toBe(true);
    expect(result.reason).toContain("active plan files exist");
  });

  test("does not check active files by default", () => {
    writeFileSync(join(testPlanDir, "active-plan.md"), "plan content");

    const input = createMockInput({
      permission_mode: "default",
      tool_input: { file_path: "/tmp/not-a-plan.md" },
    });

    const result = isPlanMode(input); // checkActiveFiles defaults to false

    expect(result.signals.activePlanFilesExist).toBe(false);
    expect(result.inPlanMode).toBe(false);
  });
});
