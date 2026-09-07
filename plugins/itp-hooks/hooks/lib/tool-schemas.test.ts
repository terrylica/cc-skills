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
  it("has schemas for 10 built-in tools", () => {
    // 9 -> 10 with AskUserQuestion, added so pretooluse-pr-premise-annotator can label an option
    // that names a pull request. Until then this tool had no schema and every mutation of it fell
    // back to a plain allow.
    expect(Object.keys(TOOL_SCHEMAS)).toHaveLength(10);
  });

  it("includes all expected tool names", () => {
    const expected = ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "NotebookEdit", "LSP"];
    for (const name of expected) {
      expect(TOOL_SCHEMAS[name]).toBeDefined();
    }
  });

  it("does NOT have schemas for UI tools other than AskUserQuestion", () => {
    // AskUserQuestion is now modelled. The rest stay unmodelled, which means a hook cannot mutate
    // them at all -- still the safest default for a tool nothing needs to annotate.
    expect(TOOL_SCHEMAS.AskUserQuestion).toBeDefined();
    expect(TOOL_SCHEMAS.TaskCreate).toBeUndefined();
    expect(TOOL_SCHEMAS.Agent).toBeUndefined();
    expect(TOOL_SCHEMAS.EnterPlanMode).toBeUndefined();
    expect(TOOL_SCHEMAS.Skill).toBeUndefined();
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

  it("now returns valid for a well-formed AskUserQuestion input", () => {
    const r = validateToolInput("AskUserQuestion", { questions: [] });
    expect(r.valid).toBe(true);
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

// The engine gained nested object / array-of-object / open-record support so that AskUserQuestion
// could be expressed at all -- its input is `questions[].options[].description`, three levels deep.
// These guard the property that makes mutating it safe: a shape the registry cannot express must be
// REJECTED, because allowWithInput turns a rejection into a counted error and a plain allow, while
// a wrongly-accepted mutation would corrupt a live tool input (anthropics/claude-code#13439).
describe("nested shapes (AskUserQuestion)", () => {
  const valid = {
    questions: [
      {
        question: "Which approach?",
        header: "Approach",
        multiSelect: true,
        options: [
          { label: "A", description: "first" },
          { label: "B", description: "second", preview: "some preview" },
        ],
      },
    ],
  };

  it("accepts a fully-formed input", () => {
    expect(validateToolInput("AskUserQuestion", valid).valid).toBe(true);
  });

  it("accepts the optional top-level fields, whose keys are the question text", () => {
    const r = validateToolInput("AskUserQuestion", {
      ...valid,
      answers: { "Which approach?": "A" },
      annotations: { "Which approach?": { notes: "n" } },
      metadata: { source: "remember" },
    });
    expect(r.valid).toBe(true);
  });

  it("reports the exact nested path of a missing field", () => {
    const r = validateToolInput("AskUserQuestion", {
      questions: [{ question: "q", header: "h", multiSelect: false, options: [{ label: "A" }] }],
    });
    expect(r.valid).toBe(false);
    if (!r.valid) expect(r.error).toContain("questions.0.options.0.description");
  });

  it("rejects an unknown key at depth, which is the whole point of strictness", () => {
    const withStray = structuredClone(valid) as Record<string, unknown>;
    (withStray.questions as Array<Record<string, unknown>>)[0]!.env = { PATH: "/tmp" };
    const r = validateToolInput("AskUserQuestion", withStray);
    expect(r.valid).toBe(false);
    if (!r.valid) expect(r.error).toContain("env");
  });

  it("rejects a wrong type inside an array element", () => {
    const wrong = structuredClone(valid) as Record<string, unknown>;
    (wrong.questions as Array<Record<string, unknown>>)[0]!.multiSelect = "yes";
    expect(validateToolInput("AskUserQuestion", wrong).valid).toBe(false);
  });

  it("rejects a non-array where an array of objects is required", () => {
    expect(validateToolInput("AskUserQuestion", { questions: {} }).valid).toBe(false);
  });

  it("rejects a non-object open-record", () => {
    expect(validateToolInput("AskUserQuestion", { ...valid, answers: "A" }).valid).toBe(false);
  });
});
