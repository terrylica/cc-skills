/**
 * Hermetic tests for pretooluse-headless-browser-tier-reminder.ts.
 *
 * Run with: bun test plugins/itp-hooks/hooks/pretooluse-headless-browser-tier-reminder.test.ts
 *
 * Each test gets its own temp directory. Subprocess runs get only PATH, HOME and TMPDIR, both inside that
 * directory, so the developer's real cooldown stamps cannot change an outcome. No network.
 */

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  buildReminder,
  claimCooldown,
  classifyCommand,
  isThrowawayPlaywrightMcp,
  REMINDER_COOLDOWN_MS,
} from "./pretooluse-headless-browser-tier-reminder.ts";

const HOOK_PATH = join(import.meta.dir, "pretooluse-headless-browser-tier-reminder.ts");

let sandbox: string;
beforeEach(() => {
  sandbox = mkdtempSync(join(tmpdir(), "headless-tier-test-"));
});
afterEach(() => {
  rmSync(sandbox, { recursive: true, force: true });
});

async function runHook(stdin: object): Promise<{ code: number; out: string }> {
  const proc = Bun.spawn(["bun", HOOK_PATH], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: { PATH: process.env.PATH ?? "", HOME: sandbox, TMPDIR: sandbox },
  });
  proc.stdin.write(JSON.stringify(stdin));
  proc.stdin.end();
  const out = await new Response(proc.stdout).text();
  return { code: await proc.exited, out };
}
const bash = (command: string, session = "s1") => ({ tool_name: "Bash", tool_input: { command }, session_id: session });
const contextOf = (out: string): string => {
  const parsed = out.trim() ? JSON.parse(out.trim()) : {};
  return parsed?.hookSpecificOutput?.additionalContext ?? "";
};

describe("classifyCommand: heavy browser launches", () => {
  test.each([
    ["python3 -c 'from playwright.sync_api import sync_playwright; p=sync_playwright().start(); b=p.chromium.launch()'"],
    ["node -e 'const b = await chromium.launch({headless:true})'"],
    ["uv run python - <<'EOF'\nctx = p.chromium.launch_persistent_context('/tmp/x')\nEOF"],
    ["node -e 'puppeteer.launch()'"],
    ["npx -y playwright screenshot https://example.com shot.png"],
    ["bunx @playwright/mcp@latest --headless"],
    ["playwright pdf https://example.com out.pdf"],
    ['"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --screenshot https://example.com'],
    ["google-chrome --headless=new --dump-dom https://example.com"],
    ["chromium --headless --screenshot https://example.com"],
  ])("reminds: %s", (command) => {
    expect(classifyCommand(command)).toBe("launch");
  });
});

describe("classifyCommand: publishing a page", () => {
  test.each([["orca artifacts share report.html"], ["orca artifacts update report.html --json"], ["wrangler pages deploy ./site"], ["npx wrangler pages deploy ./dist"]])(
    "reminds: %s",
    (command) => {
      expect(classifyCommand(command)).toBe("publish");
    },
  );
});

describe("classifyCommand: stays silent", () => {
  test.each([
    ["already tier 1", "agent-browser --session s --engine lightpanda open https://example.com"],
    ["already tier 2", "agent-browser --session s --executable-path ~/.local/share/browser-stack/chrome-headless-shell/chrome-headless-shell open https://x"],
    ["lightpanda directly", "lightpanda fetch --dump html https://example.com"],
    ["Playwright over CDP to a Lightpanda server (tier 1)", "lightpanda serve --port 9222 & python3 -c \"b = p.chromium.connect_over_cdp('ws://127.0.0.1:9222')\""],
    ["Playwright driving chrome-headless-shell (tier 2)", "python3 -c \"b = p.chromium.launch(executable_path='chrome-headless-shell/chrome-headless-shell')\""],
    ["real profile named", "python3 -c 'p.chromium.launch_persistent_context(user_data_dir)' --user-data-dir ~/p"],
    ["chrome profile flag", '"Google Chrome" --headless --profile-directory="Profile 3" https://x'],
    ["signed-in tooling", "bun mcp-drive.ts ext someone steps.json"],
    ["searching for the word", "rg -n 'chromium.launch(' src/"],
    ["reading a file", "cat scripts/shot.sh | grep 'google-chrome --headless'"],
    ["git log mention", "git log --grep 'playwright screenshot'"],
    ["plain curl check", "curl -sI https://example.com"],
    ["running an existing Playwright test suite", "npx playwright test"],
    ["installing Playwright's browsers", "npx playwright install --with-deps chromium"],
    ["a Playwright report", "npx playwright show-report"],
    ["Playwright's test runner version", "bunx @playwright/test --version"],
    ["attaching over CDP is not a launch", "python3 -c 'b = p.chromium.connect_over_cdp(\"http://127.0.0.1:9222\")'"],
    ["a Worker deploy is not a page", "npx wrangler deploy"],
    ["a PR body that mentions a launch", "gh pr create --title t --body 'replaces npx playwright screenshot with agent-browser'"],
    ["escape token", "npx playwright screenshot https://x a.png # HEADLESS-TIER-SKIP: needs Chromium's PDF engine"],
    ["empty", ""],
  ])("%s", (_name, command) => {
    expect(classifyCommand(command)).toBeNull();
  });
});

describe("isThrowawayPlaywrightMcp", () => {
  test("matches a throwaway Playwright server's tools, plain or plugin-namespaced", () => {
    expect(isThrowawayPlaywrightMcp("mcp__playwright-throwaway-headless__browser_navigate")).toBe(true);
    expect(isThrowawayPlaywrightMcp("mcp__plugin_tools_playwright-throwaway__browser_navigate")).toBe(true);
    expect(isThrowawayPlaywrightMcp("mcp__throwaway-playwright__browser_snapshot")).toBe(true);
  });
  test("ignores signed-in extension servers and other MCP tools", () => {
    expect(isThrowawayPlaywrightMcp("mcp__chrome-someone__browser_navigate")).toBe(false);
    expect(isThrowawayPlaywrightMcp("mcp__playwright-extension__browser_navigate")).toBe(false);
    expect(isThrowawayPlaywrightMcp("mcp__codegraph__codegraph_explore")).toBe(false);
  });
});

describe("classifyCommand on very long commands", () => {
  test("stays fast on a 400 KB single line full of browser names (review finding, 2026-11-07)", () => {
    // No --headless anywhere: the pattern must fail, which is the case that rescans from every browser name.
    const line = "chromium ".repeat(45_000);
    const t0 = performance.now();
    classifyCommand(line);
    expect(performance.now() - t0).toBeLessThan(200);
  });
  test("still catches a launch near the start of a long command", () => {
    expect(classifyCommand("npx playwright screenshot https://x a.png; " + "echo x; ".repeat(10_000))).toBe("launch");
  });
});

describe("claimCooldown", () => {
  test("fires once per kind per session inside the cooldown, again after it", () => {
    const t0 = 1_000_000;
    expect(claimCooldown("s", "launch", t0, sandbox)).toBe(true);
    expect(claimCooldown("s", "launch", t0 + 60_000, sandbox)).toBe(false);
    expect(claimCooldown("s", "publish", t0 + 60_000, sandbox)).toBe(true);
    expect(claimCooldown("s", "launch", t0 + REMINDER_COOLDOWN_MS + 1, sandbox)).toBe(true);
  });
  test("always fires without a usable session id", () => {
    expect(claimCooldown(undefined, "launch", 1, sandbox)).toBe(true);
    expect(claimCooldown("../x", "launch", 1, sandbox)).toBe(true);
  });
});

describe("buildReminder", () => {
  test("names all three tiers and the close step, with no personal detail", () => {
    for (const kind of ["launch", "publish"] as const) {
      const text = buildReminder(kind);
      expect(text).toContain("--engine lightpanda");
      expect(text).toContain("chrome-headless-shell");
      expect(text).toContain("--profile");
      expect(text).toContain("agent-browser close --all");
      expect(text).toContain("HEADLESS-TIER-SKIP");
      expect(text).not.toMatch(/@[a-z0-9-]+\.[a-z]{2,}|\/Users\/|Profile \d+/i);
    }
  });
});

describe("main, run as Claude Code runs it", () => {
  test("adds the reminder to a heavy launch and allows it", async () => {
    const r = await runHook(bash("npx playwright screenshot https://example.com a.png"));
    expect(r.code).toBe(0);
    expect(contextOf(r.out)).toContain("[HEADLESS-BROWSER-TIER]");
    expect(r.out).not.toContain('"deny"');
  });
  test("says nothing the second time in the same session", async () => {
    await runHook(bash("npx playwright screenshot https://example.com a.png", "same"));
    const second = await runHook(bash("google-chrome --headless --dump-dom https://example.com", "same"));
    expect(contextOf(second.out)).toBe("");
  });
  test("says nothing for an agent-browser command", async () => {
    const r = await runHook(bash("agent-browser --engine lightpanda open https://example.com"));
    expect(contextOf(r.out)).toBe("");
  });
  test("says nothing inside a subagent", async () => {
    const r = await runHook({ ...bash("npx playwright screenshot https://x a.png"), agent_id: "a1" });
    expect(contextOf(r.out)).toBe("");
  });
  test("reminds on a throwaway Playwright MCP tool call", async () => {
    const r = await runHook({ tool_name: "mcp__playwright-throwaway-headless__browser_navigate", tool_input: {}, session_id: "m1" });
    expect(contextOf(r.out)).toContain("[HEADLESS-BROWSER-TIER]");
  });
  test("fails open on malformed input", async () => {
    const proc = Bun.spawn(["bun", HOOK_PATH], { stdin: "pipe", stdout: "pipe", stderr: "pipe", env: { PATH: process.env.PATH ?? "", HOME: sandbox, TMPDIR: sandbox } });
    proc.stdin.write("not json");
    proc.stdin.end();
    expect(await proc.exited).toBe(0);
  });
});
