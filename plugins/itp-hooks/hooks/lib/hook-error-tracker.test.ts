#!/usr/bin/env bun
/**
 * Unit tests for hook-error-tracker.
 *
 * Run with: bun test plugins/itp-hooks/hooks/lib/hook-error-tracker.test.ts
 */

import { describe, it, expect, beforeEach, afterEach, spyOn } from "bun:test";
import { existsSync, readFileSync, rmSync, unlinkSync } from "node:fs";
import {
  trackHookError,
  getSessionErrors,
  getSessionId,
  type HookErrorEntry,
} from "./hook-error-tracker.ts";

const ORIGINAL_HOME = process.env.HOME;
const TEST_HOME = "/tmp/hook-error-tracker-test";
const TEST_LOG_FILE = `${TEST_HOME}/.claude/logs/hook-errors.jsonl`;
const TEST_SESSION = "test-session-001";

// Counts file path mirrors the library's getCountsFile()
function getTestCountsFile(): string {
  return `/tmp/.claude-hook-error-counts-${process.getuid?.() ?? "unknown"}.json`;
}

describe("trackHookError", () => {
  beforeEach(() => {
    process.env.HOME = TEST_HOME;
    // Clean up test artifacts
    if (existsSync(TEST_LOG_FILE)) unlinkSync(TEST_LOG_FILE);
    if (existsSync(TEST_HOME)) rmSync(TEST_HOME, { recursive: true, force: true });
    const countsFile = getTestCountsFile();
    if (existsSync(countsFile)) unlinkSync(countsFile);
  });

  afterEach(() => {
    process.env.HOME = ORIGINAL_HOME;
    if (existsSync(TEST_HOME)) rmSync(TEST_HOME, { recursive: true, force: true });
    const countsFile = getTestCountsFile();
    if (existsSync(countsFile)) unlinkSync(countsFile);
  });

  it("creates log directory and JSONL file on first error", () => {
    trackHookError("test-hook", "something broke", TEST_SESSION);

    expect(existsSync(TEST_LOG_FILE)).toBe(true);
    const content = readFileSync(TEST_LOG_FILE, "utf8").trim();
    const entry = JSON.parse(content);
    expect(entry.hook).toBe("test-hook");
    expect(entry.message).toBe("something broke");
    expect(entry.session_id).toBe(TEST_SESSION);
    expect(entry.ts).toBeDefined();
  });

  it("appends multiple entries as separate JSONL lines", () => {
    trackHookError("hook-a", "error 1", TEST_SESSION);
    trackHookError("hook-b", "error 2", TEST_SESSION);
    trackHookError("hook-a", "error 3", TEST_SESSION);

    const lines = readFileSync(TEST_LOG_FILE, "utf8").trim().split("\n");
    expect(lines.length).toBe(3);

    const entries = lines.map((l) => JSON.parse(l));
    expect(entries[0].hook).toBe("hook-a");
    expect(entries[1].hook).toBe("hook-b");
    expect(entries[2].hook).toBe("hook-a");
  });

  it("is silent (no stderr) for first 2 errors from same hook", () => {
    const spy = spyOn(console, "error").mockImplementation(() => {});

    trackHookError("quiet-hook", "error 1", TEST_SESSION);
    trackHookError("quiet-hook", "error 2", TEST_SESSION);

    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();
  });

  it("emits ONE stderr escalation on 3rd error from same hook", () => {
    const spy = spyOn(console, "error").mockImplementation(() => {});

    trackHookError("noisy-hook", "err 1", TEST_SESSION);
    trackHookError("noisy-hook", "err 2", TEST_SESSION);
    trackHookError("noisy-hook", "err 3", TEST_SESSION);

    expect(spy).toHaveBeenCalledTimes(1);
    expect(spy.mock.calls[0][0]).toContain("noisy-hook");
    expect(spy.mock.calls[0][0]).toContain("3 times");
    expect(spy.mock.calls[0][0]).toContain("hook-errors.jsonl");
    spy.mockRestore();
  });

  it("is silent again after 4th+ errors (no repeated escalation)", () => {
    const spy = spyOn(console, "error").mockImplementation(() => {});

    for (let i = 0; i < 6; i++) {
      trackHookError("repeat-hook", `err ${i + 1}`, TEST_SESSION);
    }

    // Only the 3rd call should have triggered stderr
    expect(spy).toHaveBeenCalledTimes(1);
    spy.mockRestore();
  });

  it("tracks counts independently per hook name", () => {
    const spy = spyOn(console, "error").mockImplementation(() => {});

    // Hook A: 3 errors (should escalate)
    trackHookError("hook-a", "a1", TEST_SESSION);
    trackHookError("hook-a", "a2", TEST_SESSION);
    trackHookError("hook-a", "a3", TEST_SESSION);

    // Hook B: 2 errors (should NOT escalate)
    trackHookError("hook-b", "b1", TEST_SESSION);
    trackHookError("hook-b", "b2", TEST_SESSION);

    expect(spy).toHaveBeenCalledTimes(1);
    expect(spy.mock.calls[0][0]).toContain("hook-a");
    spy.mockRestore();
  });

  it("tracks counts independently per session", () => {
    const spy = spyOn(console, "error").mockImplementation(() => {});

    // Session A: 2 errors
    trackHookError("shared-hook", "s1", "session-a");
    trackHookError("shared-hook", "s2", "session-a");

    // Session B: 2 errors
    trackHookError("shared-hook", "s1", "session-b");
    trackHookError("shared-hook", "s2", "session-b");

    // Neither should escalate (both below threshold)
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();
  });

  it("writes valid ISO-8601 timestamps", () => {
    trackHookError("ts-hook", "check timestamp", TEST_SESSION);

    const content = readFileSync(TEST_LOG_FILE, "utf8").trim();
    const entry = JSON.parse(content);

    const tsRegex = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}.\d{3}Z$/;
    expect(tsRegex.test(entry.ts)).toBe(true);
    expect(new Date(entry.ts).toString()).not.toBe("Invalid Date");
  });
});

describe("getSessionErrors", () => {
  beforeEach(() => {
    process.env.HOME = TEST_HOME;
    if (existsSync(TEST_HOME)) rmSync(TEST_HOME, { recursive: true, force: true });
    const countsFile = getTestCountsFile();
    if (existsSync(countsFile)) unlinkSync(countsFile);
  });

  afterEach(() => {
    process.env.HOME = ORIGINAL_HOME;
    if (existsSync(TEST_HOME)) rmSync(TEST_HOME, { recursive: true, force: true });
    const countsFile = getTestCountsFile();
    if (existsSync(countsFile)) unlinkSync(countsFile);
  });

  it("returns empty map when no log file exists", () => {
    const result = getSessionErrors(TEST_SESSION);
    expect(result.size).toBe(0);
  });

  it("returns errors grouped by hook name for matching session", () => {
    trackHookError("hook-a", "err 1", TEST_SESSION);
    trackHookError("hook-b", "err 2", TEST_SESSION);
    trackHookError("hook-a", "err 3", TEST_SESSION);
    trackHookError("hook-a", "err 4", "other-session");

    const result = getSessionErrors(TEST_SESSION);

    expect(result.size).toBe(2);
    expect(result.get("hook-a")?.length).toBe(2);
    expect(result.get("hook-b")?.length).toBe(1);
  });

  it("excludes errors from other sessions", () => {
    trackHookError("hook-x", "wrong session", "other-session");

    const result = getSessionErrors(TEST_SESSION);
    expect(result.size).toBe(0);
  });

  it("returns entries with all required fields", () => {
    trackHookError("detail-hook", "detailed error", TEST_SESSION);

    const result = getSessionErrors(TEST_SESSION);
    const entries = result.get("detail-hook");

    expect(entries).toBeDefined();
    expect(entries!.length).toBe(1);
    expect(entries![0].hook).toBe("detail-hook");
    expect(entries![0].message).toBe("detailed error");
    expect(entries![0].session_id).toBe(TEST_SESSION);
    expect(entries![0].ts).toBeDefined();
  });
});

describe("getSessionId", () => {
  const origSessionId = process.env.CLAUDE_SESSION_ID;
  const origConversationId = process.env.CLAUDE_CONVERSATION_ID;

  afterEach(() => {
    // Restore original values
    if (origSessionId !== undefined) {
      process.env.CLAUDE_SESSION_ID = origSessionId;
    } else {
      delete process.env.CLAUDE_SESSION_ID;
    }
    if (origConversationId !== undefined) {
      process.env.CLAUDE_CONVERSATION_ID = origConversationId;
    } else {
      delete process.env.CLAUDE_CONVERSATION_ID;
    }
  });

  it("prefers CLAUDE_SESSION_ID when set", () => {
    process.env.CLAUDE_SESSION_ID = "session-abc";
    process.env.CLAUDE_CONVERSATION_ID = "conv-xyz";

    expect(getSessionId()).toBe("session-abc");
  });

  it("falls back to CLAUDE_CONVERSATION_ID", () => {
    delete process.env.CLAUDE_SESSION_ID;
    process.env.CLAUDE_CONVERSATION_ID = "conv-xyz";

    expect(getSessionId()).toBe("conv-xyz");
  });

  it("falls back to ppid-based ID when no env vars set", () => {
    delete process.env.CLAUDE_SESSION_ID;
    delete process.env.CLAUDE_CONVERSATION_ID;

    const result = getSessionId();
    expect(result).toStartWith("ppid-");
  });
});
