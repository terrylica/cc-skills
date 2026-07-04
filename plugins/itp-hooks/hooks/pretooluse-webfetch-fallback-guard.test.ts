/**
 * Tests for pretooluse-webfetch-fallback-guard.ts
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-webfetch-fallback-guard.test.ts
 */

import { describe, expect, it } from "bun:test";
import { execSync } from "child_process";
import { join } from "path";

const HOOK_PATH = join(import.meta.dir, "pretooluse-webfetch-fallback-guard.ts");

interface HookResult {
  stdout: string;
  parsed: {
    hookSpecificOutput?: {
      hookEventName: string;
      permissionDecision: "allow" | "deny" | "ask";
      permissionDecisionReason?: string;
    };
  } | null;
}

function runHook(input: object): HookResult {
  try {
    const stdout = execSync(`bun ${HOOK_PATH}`, {
      encoding: "utf-8",
      input: JSON.stringify(input),
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

function expectDeny(result: HookResult, containsText?: string): void {
  expect(result.parsed).not.toBeNull();
  expect(result.parsed!.hookSpecificOutput?.permissionDecision).toBe("deny");
  expect(result.parsed!.hookSpecificOutput?.permissionDecisionReason).toContain("[WEBFETCH-FALLBACK]");
  if (containsText) {
    expect(result.parsed!.hookSpecificOutput?.permissionDecisionReason).toContain(containsText);
  }
}

function expectAllow(result: HookResult): void {
  expect(result.parsed).not.toBeNull();
  expect(result.parsed!.hookSpecificOutput?.permissionDecision).toBe("allow");
}

describe("pretooluse-webfetch-fallback-guard", () => {
  it("denies a WebFetch call", () => {
    const result = runHook({
      tool_name: "WebFetch",
      tool_input: { url: "https://www.vw.ca/", prompt: "list trims" },
    });
    expectDeny(result);
  });

  it("deny message names the curl → agent-reach → WebSearch fallback chain", () => {
    const result = runHook({
      tool_name: "WebFetch",
      tool_input: { url: "https://example.com/", prompt: "summarize" },
    });
    expectDeny(result, "curl");
    expect(result.parsed!.hookSpecificOutput?.permissionDecisionReason).toContain("agent-reach");
    expect(result.parsed!.hookSpecificOutput?.permissionDecisionReason).toContain("WebSearch");
  });

  it("allows non-WebFetch tools (Bash)", () => {
    const result = runHook({
      tool_name: "Bash",
      tool_input: { command: "curl -sL https://example.com" },
    });
    expectAllow(result);
  });

  it("allows WebSearch (the recommended fallback)", () => {
    const result = runHook({
      tool_name: "WebSearch",
      tool_input: { query: "vw jetta 2026 trims" },
    });
    expectAllow(result);
  });

  it("denies WebFetch unconditionally (no escape hatch, even with no prompt)", () => {
    const result = runHook({
      tool_name: "WebFetch",
      tool_input: { url: "https://example.com/" },
    });
    expectDeny(result);
  });

  it("fails open (allow) on unparseable stdin", () => {
    const result = runHook("this is not json" as unknown as object);
    // parseStdinOrAllow emits allow() on parse failure.
    expect(result.parsed?.hookSpecificOutput?.permissionDecision ?? "allow").toBe("allow");
  });
});
