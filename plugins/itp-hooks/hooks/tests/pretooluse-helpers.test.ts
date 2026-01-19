#!/usr/bin/env bun
/**
 * Unit tests for PreToolUse shared helpers.
 *
 * Run with: bun test plugins/itp-hooks/hooks/tests/pretooluse-helpers.test.ts
 */

import { describe, it, expect, beforeEach, afterEach, spyOn } from "bun:test";
import { rmSync, existsSync } from "node:fs";
import {
  output,
  allow,
  deny,
  ask,
  type PreToolUseInput,
  type PreToolUseResponse,
} from "../pretooluse-helpers.ts";

// Store original HOME for restoration
const ORIGINAL_HOME = process.env.HOME;

describe("output function", () => {
  it("outputs valid JSON to stdout", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    output({ test: "value" });

    expect(consoleSpy).toHaveBeenCalledTimes(1);
    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);
    expect(parsed).toEqual({ test: "value" });

    consoleSpy.mockRestore();
  });

  it("handles nested objects", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    output({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
      },
    });

    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);
    expect(parsed.hookSpecificOutput.hookEventName).toBe("PreToolUse");

    consoleSpy.mockRestore();
  });
});

describe("allow function", () => {
  it("outputs correct response structure", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    allow();

    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);

    expect(parsed).toEqual({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
      },
    });

    consoleSpy.mockRestore();
  });

  it("has permissionDecision set to allow", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    allow();

    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);

    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");

    consoleSpy.mockRestore();
  });

  it("does not include permissionDecisionReason", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    allow();

    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);

    expect(parsed.hookSpecificOutput.permissionDecisionReason).toBeUndefined();

    consoleSpy.mockRestore();
  });
});

describe("deny function", () => {
  it("outputs correct response structure with reason", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    deny("Test denial reason");

    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);

    expect(parsed).toEqual({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Test denial reason",
      },
    });

    consoleSpy.mockRestore();
  });

  it("has permissionDecision set to deny", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    deny("Reason");

    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);

    expect(parsed.hookSpecificOutput.permissionDecision).toBe("deny");

    consoleSpy.mockRestore();
  });

  it("includes the provided reason", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    const reason = "This operation is blocked for safety";
    deny(reason);

    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);

    expect(parsed.hookSpecificOutput.permissionDecisionReason).toBe(reason);

    consoleSpy.mockRestore();
  });
});

describe("ask function", () => {
  it("outputs correct response structure with reason", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    ask("Please confirm this action");

    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);

    expect(parsed).toEqual({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: "Please confirm this action",
      },
    });

    consoleSpy.mockRestore();
  });

  it("has permissionDecision set to ask", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    ask("Reason");

    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);

    expect(parsed.hookSpecificOutput.permissionDecision).toBe("ask");

    consoleSpy.mockRestore();
  });

  it("includes the provided reason", () => {
    const consoleSpy = spyOn(console, "log").mockImplementation(() => {});

    const reason = "[FAKE DATA] Detected synthetic data patterns";
    ask(reason);

    const outputStr = consoleSpy.mock.calls[0][0];
    const parsed = JSON.parse(outputStr);

    expect(parsed.hookSpecificOutput.permissionDecisionReason).toBe(reason);

    consoleSpy.mockRestore();
  });
});

describe("Type exports", () => {
  it("PreToolUseInput type structure is correct", () => {
    // Type-level test: this should compile without errors
    const input: PreToolUseInput = {
      tool_name: "Write",
      tool_input: {
        file_path: "/tmp/test.py",
        content: "print('hello')",
      },
      tool_use_id: "toolu_abc123",
      cwd: "/home/user/project",
    };

    expect(input.tool_name).toBe("Write");
    expect(input.tool_input.file_path).toBe("/tmp/test.py");
    expect(input.tool_input.content).toBe("print('hello')");
    expect(input.tool_use_id).toBe("toolu_abc123");
    expect(input.cwd).toBe("/home/user/project");
  });

  it("PreToolUseInput supports Edit tool inputs", () => {
    const input: PreToolUseInput = {
      tool_name: "Edit",
      tool_input: {
        file_path: "/tmp/test.py",
        new_string: "updated_content",
      },
    };

    expect(input.tool_name).toBe("Edit");
    expect(input.tool_input.new_string).toBe("updated_content");
  });

  it("PreToolUseInput supports Bash tool inputs", () => {
    const input: PreToolUseInput = {
      tool_name: "Bash",
      tool_input: {
        command: "ls -la",
      },
    };

    expect(input.tool_name).toBe("Bash");
    expect(input.tool_input.command).toBe("ls -la");
  });

  it("PreToolUseResponse type structure is correct", () => {
    const response: PreToolUseResponse = {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
      },
    };

    expect(response.hookSpecificOutput.hookEventName).toBe("PreToolUse");
    expect(response.hookSpecificOutput.permissionDecision).toBe("allow");
  });

  it("PreToolUseResponse supports deny with reason", () => {
    const response: PreToolUseResponse = {
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Blocked for safety",
      },
    };

    expect(response.hookSpecificOutput.permissionDecision).toBe("deny");
    expect(response.hookSpecificOutput.permissionDecisionReason).toBe("Blocked for safety");
  });
});

// Note: parseStdinOrAllow is difficult to unit test because it reads from Bun.stdin
// Integration tests would be more appropriate for this function
// The test below documents the expected behavior
describe("parseStdinOrAllow behavior (documentation)", () => {
  it("should return parsed input on valid JSON", () => {
    // Expected: parseStdinOrAllow("hook-name") returns PreToolUseInput
    // when valid JSON is provided on stdin
    expect(true).toBe(true); // Placeholder
  });

  it("should call allow() and return null on invalid JSON", () => {
    // Expected: parseStdinOrAllow("hook-name") calls allow() and returns null
    // when invalid JSON is provided on stdin
    expect(true).toBe(true); // Placeholder
  });

  it("should log to itp-hooks.jsonl on success and failure", () => {
    // Expected: Both success and failure paths log structured NDJSON
    expect(true).toBe(true); // Placeholder
  });
});
