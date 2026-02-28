#!/usr/bin/env bun
/**
 * Unit tests for Zod tool schema registry.
 *
 * Run with: bun test plugins/itp-hooks/hooks/lib/tool-schemas.test.ts
 *
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/13439
 */

import { describe, it, expect } from "bun:test";
import {
  BashSchema,
  ReadSchema,
  GrepSchema,
  TOOL_SCHEMAS,
  validateToolInput,
} from "./tool-schemas.ts";

describe("TOOL_SCHEMAS", () => {
  it("has schemas for 8 built-in tools", () => {
    expect(Object.keys(TOOL_SCHEMAS)).toHaveLength(8);
  });

  it("includes all expected tool names", () => {
    const expected = ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "NotebookEdit", "LSP"];
    for (const name of expected) {
      expect(TOOL_SCHEMAS[name]).toBeDefined();
    }
  });

  it("does NOT have schemas for UI tools", () => {
    expect(TOOL_SCHEMAS["AskUserQuestion"]).toBeUndefined();
    expect(TOOL_SCHEMAS["TaskCreate"]).toBeUndefined();
    expect(TOOL_SCHEMAS["Agent"]).toBeUndefined();
    expect(TOOL_SCHEMAS["EnterPlanMode"]).toBeUndefined();
    expect(TOOL_SCHEMAS["Skill"]).toBeUndefined();
  });
});

describe("BashSchema", () => {
  it("accepts valid Bash input", () => {
    expect(BashSchema.safeParse({ command: "ls" }).success).toBe(true);
  });

  it("accepts all optional fields", () => {
    const result = BashSchema.safeParse({
      command: "ls -la",
      description: "List files",
      timeout: 5000,
      run_in_background: true,
    });
    expect(result.success).toBe(true);
  });

  it("rejects unknown properties (.strict)", () => {
    const result = BashSchema.safeParse({ command: "ls", env: { FOO: "bar" } });
    expect(result.success).toBe(false); // This is the bug we're preventing!
  });

  it("requires command field", () => {
    expect(BashSchema.safeParse({}).success).toBe(false);
  });

  it("rejects non-string command", () => {
    expect(BashSchema.safeParse({ command: 42 }).success).toBe(false);
  });
});

describe("ReadSchema", () => {
  it("accepts file_path only", () => {
    expect(ReadSchema.safeParse({ file_path: "/tmp/test.txt" }).success).toBe(true);
  });

  it("accepts optional offset and limit", () => {
    const result = ReadSchema.safeParse({ file_path: "/tmp/test.txt", offset: 10, limit: 50 });
    expect(result.success).toBe(true);
  });

  it("rejects unknown properties", () => {
    expect(ReadSchema.safeParse({ file_path: "/tmp/test.txt", env: {} }).success).toBe(false);
  });
});

describe("GrepSchema", () => {
  it("accepts pattern only", () => {
    expect(GrepSchema.safeParse({ pattern: "TODO" }).success).toBe(true);
  });

  it("accepts all optional fields", () => {
    const result = GrepSchema.safeParse({
      pattern: "TODO",
      path: "/src",
      glob: "*.ts",
      type: "ts",
      output_mode: "content",
      "-A": 3,
      "-B": 3,
      "-C": 5,
      "-i": true,
      "-n": true,
      context: 2,
      head_limit: 100,
      offset: 0,
      multiline: false,
    });
    expect(result.success).toBe(true);
  });

  it("rejects invalid output_mode enum", () => {
    expect(GrepSchema.safeParse({ pattern: "TODO", output_mode: "invalid" }).success).toBe(false);
  });
});

describe("validateToolInput", () => {
  it("returns valid for correct Bash input", () => {
    const r = validateToolInput("Bash", { command: "ls -la" });
    expect(r.valid).toBe(true);
    if (r.valid) {
      expect(r.data.command).toBe("ls -la");
    }
  });

  it("returns invalid for AskUserQuestion (no schema)", () => {
    const r = validateToolInput("AskUserQuestion", { questions: [] });
    expect(r.valid).toBe(false);
    if (!r.valid) {
      expect(r.error).toContain("No schema");
      expect(r.error).toContain("AskUserQuestion");
    }
  });

  it("returns invalid for Bash with extra fields (.strict catches env injection)", () => {
    const r = validateToolInput("Bash", { command: "ls", env: { TERM: "dumb" } });
    expect(r.valid).toBe(false);
    if (!r.valid) {
      expect(r.error).toContain("Schema validation failed");
    }
  });

  it("returns invalid for unknown tools", () => {
    const r = validateToolInput("FutureTool", { data: "test" });
    expect(r.valid).toBe(false);
    if (!r.valid) {
      expect(r.error).toContain("No schema");
    }
  });

  it("strips no fields from valid input (data passthrough)", () => {
    const r = validateToolInput("Edit", {
      file_path: "/tmp/test.ts",
      old_string: "foo",
      new_string: "bar",
      replace_all: true,
    });
    expect(r.valid).toBe(true);
    if (r.valid) {
      expect(r.data.file_path).toBe("/tmp/test.ts");
      expect(r.data.old_string).toBe("foo");
      expect(r.data.new_string).toBe("bar");
      expect(r.data.replace_all).toBe(true);
    }
  });

  it("returns descriptive error messages with path info", () => {
    const r = validateToolInput("Bash", { command: 123 });
    expect(r.valid).toBe(false);
    if (!r.valid) {
      expect(r.error).toContain("command");
    }
  });
});
