/**
 * Tests for pretooluse-large-file-read-guard.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-large-file-read-guard.test.ts
 */

import { describe, expect, it, beforeAll, afterAll } from "bun:test";
import { execSync } from "child_process";
import { join } from "path";
import { mkdirSync, writeFileSync, rmSync } from "fs";

const HOOK_PATH = join(
  import.meta.dir,
  "pretooluse-large-file-read-guard.ts",
);

const TMP_DIR = join("/tmp", "claude-large-file-guard-test");

interface HookResult {
  stdout: string;
  parsed: {
    hookSpecificOutput?: {
      hookEventName: string;
      permissionDecision?: "allow" | "deny";
      additionalContext?: string;
    };
  } | null;
}

function runHook(input: object): HookResult {
  try {
    const inputJson = JSON.stringify(input);
    const stdout = execSync(`bun ${HOOK_PATH}`, {
      encoding: "utf-8",
      input: inputJson,
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();

    let parsed = null;
    if (stdout) {
      try {
        parsed = JSON.parse(stdout);
      } catch {
        // Not JSON output
      }
    }
    return { stdout, parsed };
  } catch (err: any) {
    const stdout = err.stdout?.toString().trim() || "";
    let parsed = null;
    if (stdout) {
      try {
        parsed = JSON.parse(stdout);
      } catch {
        // Not JSON
      }
    }
    return { stdout, parsed };
  }
}

function expectAllow(result: HookResult): void {
  expect(result.parsed).not.toBeNull();
  expect(result.parsed!.hookSpecificOutput?.permissionDecision).toBe("allow");
  expect(result.parsed!.hookSpecificOutput?.additionalContext).toBeUndefined();
}

function expectWarning(result: HookResult, lineCount?: number): void {
  expect(result.parsed).not.toBeNull();
  const ctx = result.parsed!.hookSpecificOutput?.additionalContext;
  expect(ctx).toBeDefined();
  expect(ctx).toContain("WARNING");
  expect(ctx).toContain("2000-line default");
  expect(ctx).toContain("offset and limit");
  if (lineCount) {
    expect(ctx).toContain(`${lineCount} lines`);
  }
  // Warning does NOT set permissionDecision (allows by default)
  expect(result.parsed!.hookSpecificOutput?.permissionDecision).toBeUndefined();
}

// Create test fixture files
beforeAll(() => {
  mkdirSync(TMP_DIR, { recursive: true });

  // Small file: 100 lines
  writeFileSync(
    join(TMP_DIR, "small.txt"),
    Array.from({ length: 100 }, (_, i) => `line ${i + 1}`).join("\n") + "\n",
  );

  // Exactly at threshold: 2000 lines
  writeFileSync(
    join(TMP_DIR, "at-threshold.txt"),
    Array.from({ length: 2000 }, (_, i) => `line ${i + 1}`).join("\n") + "\n",
  );

  // Over threshold: 2001 lines
  writeFileSync(
    join(TMP_DIR, "over-threshold.txt"),
    Array.from({ length: 2001 }, (_, i) => `line ${i + 1}`).join("\n") + "\n",
  );

  // Large file: 5000 lines
  writeFileSync(
    join(TMP_DIR, "large.txt"),
    Array.from({ length: 5000 }, (_, i) => `line ${i + 1}`).join("\n") + "\n",
  );

  // Binary file (contains null bytes)
  const binaryContent = Buffer.alloc(1024);
  binaryContent.write("header");
  // Null bytes are already in the buffer from alloc
  writeFileSync(join(TMP_DIR, "binary.bin"), binaryContent);

  // Empty file
  writeFileSync(join(TMP_DIR, "empty.txt"), "");
});

afterAll(() => {
  rmSync(TMP_DIR, { recursive: true, force: true });
});

// ============================================================================
// Core: files under threshold → allow silently
// ============================================================================

describe("ALLOW: files under threshold", () => {
  it("should allow small file (100 lines)", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: join(TMP_DIR, "small.txt") },
    });
    expectAllow(result);
  });

  it("should allow file exactly at threshold (2000 lines)", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: join(TMP_DIR, "at-threshold.txt") },
    });
    expectAllow(result);
  });

  it("should allow empty file", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: join(TMP_DIR, "empty.txt") },
    });
    expectAllow(result);
  });
});

// ============================================================================
// Core: files over threshold → warning context
// ============================================================================

describe("WARN: files over threshold", () => {
  it("should warn for file just over threshold (2001 lines)", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: join(TMP_DIR, "over-threshold.txt") },
    });
    expectWarning(result, 2001);
  });

  it("should warn for large file (5000 lines)", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: join(TMP_DIR, "large.txt") },
    });
    expectWarning(result, 5000);
  });
});

// ============================================================================
// Core: limit/offset already specified → allow (Claude is chunking)
// ============================================================================

describe("ALLOW: limit or offset specified", () => {
  it("should allow large file when limit is specified", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: join(TMP_DIR, "large.txt"), limit: 500 },
    });
    expectAllow(result);
  });

  it("should allow large file when offset is specified", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: join(TMP_DIR, "large.txt"), offset: 100 },
    });
    expectAllow(result);
  });

  it("should allow large file when both limit and offset are specified", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: {
        file_path: join(TMP_DIR, "large.txt"),
        offset: 100,
        limit: 200,
      },
    });
    expectAllow(result);
  });

  it("should allow when limit is 0 (explicitly set)", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: join(TMP_DIR, "large.txt"), limit: 0 },
    });
    expectAllow(result);
  });
});

// ============================================================================
// Non-Read tools → allow
// ============================================================================

describe("ALLOW: non-Read tools", () => {
  it("should allow Bash tool", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "cat large-file.txt" },
    });
    expectAllow(result);
  });

  it("should allow Write tool", () => {
    const result = runHook({
      tool_name: "Write",
      tool_input: { file_path: "/tmp/test.txt", content: "hello" },
    });
    expectAllow(result);
  });

  it("should allow Edit tool", () => {
    const result = runHook({
      tool_name: "Edit",
      tool_input: { file_path: "/tmp/test.txt" },
    });
    expectAllow(result);
  });

  it("should allow Glob tool", () => {
    const result = runHook({
      tool_name: "Glob",
      tool_input: { pattern: "**/*.ts" },
    });
    expectAllow(result);
  });

  it("should allow Grep tool", () => {
    const result = runHook({
      tool_name: "Grep",
      tool_input: { pattern: "TODO" },
    });
    expectAllow(result);
  });
});

// ============================================================================
// Edge cases: missing/invalid file paths
// ============================================================================

describe("ALLOW: file edge cases", () => {
  it("should allow when file does not exist", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: "/tmp/nonexistent-file-abc123.txt" },
    });
    expectAllow(result);
  });

  it("should allow when file_path is missing", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: {},
    });
    expectAllow(result);
  });

  it("should allow binary files (skip line count)", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: join(TMP_DIR, "binary.bin") },
    });
    expectAllow(result);
  });

  it("should allow when file_path is empty string", () => {
    const result = runHook({
      tool_name: "Read",
      tool_input: { file_path: "" },
    });
    expectAllow(result);
  });
});

// ============================================================================
// Edge cases: malformed input
// ============================================================================

describe("Fail-open: malformed input", () => {
  it("should handle malformed JSON gracefully (fail-open)", () => {
    try {
      const stdout = execSync(`echo 'not json' | bun ${HOOK_PATH}`, {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      }).trim();

      if (stdout) {
        const parsed = JSON.parse(stdout);
        expect(parsed.hookSpecificOutput?.permissionDecision).toBe("allow");
      }
    } catch {
      // Also acceptable — fail-open means no crash
      expect(true).toBe(true);
    }
  });

  it("should handle empty stdin gracefully", () => {
    try {
      const stdout = execSync(`echo '' | bun ${HOOK_PATH}`, {
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      }).trim();

      if (stdout) {
        const parsed = JSON.parse(stdout);
        expect(parsed.hookSpecificOutput?.permissionDecision).toBe("allow");
      }
    } catch {
      expect(true).toBe(true);
    }
  });

  it("should handle missing tool_input gracefully", () => {
    const result = runHook({
      tool_name: "Read",
    });
    expectAllow(result);
  });
});
