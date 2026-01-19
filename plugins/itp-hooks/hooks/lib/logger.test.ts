#!/usr/bin/env bun
/**
 * Unit tests for NDJSON structured logger.
 *
 * Run with: bun test plugins/itp-hooks/hooks/lib/
 */

import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import { readFileSync, existsSync, unlinkSync, rmSync } from "node:fs";
import { log, createHookLogger, type LogLevel, type HookLogContext } from "./logger.ts";

// Use temp directory for test logs to avoid polluting user's ~/.claude/logs
const TEST_LOG_DIR = "/tmp/itp-hooks-test-logs";
const TEST_LOG_FILE = `${TEST_LOG_DIR}/itp-hooks.jsonl`;

// Store original HOME for restoration
const ORIGINAL_HOME = process.env.HOME;

describe("log function", () => {
  beforeEach(() => {
    // Point logs to temp directory
    process.env.HOME = "/tmp/itp-hooks-test";
    // Clean up any existing test log
    if (existsSync("/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl")) {
      unlinkSync("/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl");
    }
  });

  afterEach(() => {
    // Restore HOME
    process.env.HOME = ORIGINAL_HOME;
    // Clean up test directory
    if (existsSync("/tmp/itp-hooks-test")) {
      rmSync("/tmp/itp-hooks-test", { recursive: true, force: true });
    }
  });

  it("writes valid NDJSON to file", () => {
    log("test-component", "info", "Test message");

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    expect(existsSync(logFile)).toBe(true);

    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    expect(entry).toBeDefined();
    expect(typeof entry).toBe("object");
  });

  it("includes required fields (ts, level, msg, component, env, pid)", () => {
    log("test-component", "info", "Test message");

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    expect(entry.ts).toBeDefined();
    expect(entry.level).toBe("info");
    expect(entry.msg).toBe("Test message");
    expect(entry.component).toBe("test-component");
    expect(entry.env).toBeDefined();
    expect(typeof entry.pid).toBe("number");
  });

  it("ts is valid UTC ISO-8601 format", () => {
    log("test-component", "debug", "Timestamp test");

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    // ISO-8601 format check
    const tsRegex = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z$/;
    expect(tsRegex.test(entry.ts)).toBe(true);

    // Should be parseable as Date
    const date = new Date(entry.ts);
    expect(date.toString()).not.toBe("Invalid Date");
  });

  it("sanitizes paths containing $HOME", () => {
    // Use the test HOME and verify path sanitization
    const testHome = "/tmp/itp-hooks-test";
    process.env.HOME = testHome;

    log("test-component", "info", "Path test", {
      file_path: `${testHome}/some/file.txt`,
    });

    const logFile = `${testHome}/.claude/logs/itp-hooks.jsonl`;
    expect(existsSync(logFile)).toBe(true);

    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    // Path should be sanitized to ~
    expect(entry.ctx?.file_path).toBe("~/some/file.txt");
  });

  it("includes optional hook_event and decision fields when provided", () => {
    log("test-component", "info", "Decision test", {
      hook_event: "PreToolUse",
      decision: "allow",
      tool_name: "Write",
    });

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    expect(entry.hook_event).toBe("PreToolUse");
    expect(entry.decision).toBe("allow");
    expect(entry.tool_name).toBe("Write");
  });

  it("includes trace_id for correlation when provided", () => {
    log("test-component", "info", "Trace test", {
      trace_id: "toolu_abc123",
    });

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    expect(entry.trace_id).toBe("toolu_abc123");
  });

  it("includes duration_ms when provided", () => {
    log("test-component", "info", "Duration test", {
      duration_ms: 42,
    });

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    expect(entry.duration_ms).toBe(42);
  });

  it("supports all log levels", () => {
    const levels: LogLevel[] = ["debug", "info", "warn", "error"];

    for (const level of levels) {
      log("test-component", level, `${level} message`);
    }

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    const lines = readFileSync(logFile, "utf8").trim().split("\n");
    expect(lines.length).toBe(4);

    const entries = lines.map((line) => JSON.parse(line));
    const loggedLevels = entries.map((e) => e.level);

    expect(loggedLevels).toContain("debug");
    expect(loggedLevels).toContain("info");
    expect(loggedLevels).toContain("warn");
    expect(loggedLevels).toContain("error");
  });

  it("omits ctx field when no extra context provided", () => {
    log("test-component", "info", "No context");

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    expect(entry.ctx).toBeUndefined();
  });

  it("puts extra context fields in ctx object", () => {
    log("test-component", "info", "With context", {
      pattern_matched: "np.random.randn",
      custom_field: "custom_value",
    });

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    expect(entry.ctx).toBeDefined();
    expect(entry.ctx.pattern_matched).toBe("np.random.randn");
    expect(entry.ctx.custom_field).toBe("custom_value");
  });
});

describe("createHookLogger", () => {
  beforeEach(() => {
    process.env.HOME = "/tmp/itp-hooks-test";
    if (existsSync("/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl")) {
      unlinkSync("/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl");
    }
  });

  afterEach(() => {
    process.env.HOME = ORIGINAL_HOME;
    if (existsSync("/tmp/itp-hooks-test")) {
      rmSync("/tmp/itp-hooks-test", { recursive: true, force: true });
    }
  });

  it("returns logger with all levels (debug, info, warn, error)", () => {
    const logger = createHookLogger("test-hook");

    expect(typeof logger.debug).toBe("function");
    expect(typeof logger.info).toBe("function");
    expect(typeof logger.warn).toBe("function");
    expect(typeof logger.error).toBe("function");
  });

  it("uses component name in all log entries", () => {
    const logger = createHookLogger("fake-data-guard");
    logger.info("Test message");

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    expect(entry.component).toBe("fake-data-guard");
  });

  it("passes context through to log function", () => {
    const logger = createHookLogger("test-hook");
    logger.warn("Warning", {
      hook_event: "PreToolUse",
      decision: "deny",
    });

    const logFile = "/tmp/itp-hooks-test/.claude/logs/itp-hooks.jsonl";
    const content = readFileSync(logFile, "utf8").trim();
    const entry = JSON.parse(content);

    expect(entry.level).toBe("warn");
    expect(entry.hook_event).toBe("PreToolUse");
    expect(entry.decision).toBe("deny");
  });
});
