#!/usr/bin/env bun
/**
 * PreToolUse reminder: browser work that needs no desktop window runs on the lightest engine that can do it.
 *
 * Motivation (operator, 2026-11-07): a machine ran out of memory with many agent sessions and desktop Chrome
 * open, and had to be hard-rebooted. A measured trial then ranked agent browsers by memory against
 * compatibility, and the operator chose three tiers, all driven by Vercel's `agent-browser` CLI:
 *   1. public pages: Lightpanda (`--engine lightpanda`), about 145 MB per five-page job;
 *   2. a login, or a page Lightpanda cannot render: Google's chrome-headless-shell (`--executable-path`),
 *      about 600 MB, with a saved login file (`--state`);
 *   3. only when the real profile itself is needed: branded Chrome with a profile copy (`--profile`),
 *      about 2.3 GB.
 * Without a reminder, agents reach for what they know: a Playwright `chromium.launch()`, `npx playwright
 * screenshot`, or branded Chrome with `--headless`, each costing tier-3 memory for tier-1 work.
 *
 * Soft: it adds context and allows, never denies. Whether a page needs a login or the real profile is the
 * model's call; the hook cannot see that.
 *
 * Fires on Bash when the command
 *   - starts a heavy browser for automation or a web check: a Playwright or Puppeteer launch, starting the
 *     `@playwright/mcp` server, `playwright screenshot|pdf|open|codegen|cr`, or branded Chrome / Chromium run
 *     with `--headless` (attaching with `connect_over_cdp` is not a launch, and `playwright test|install` is
 *     not tier-1 work); or
 *   - publishes an HTML page (`orca artifacts share|update`, `wrangler pages deploy`),
 *     the moment its rendering usually gets checked;
 * and on a tool call to a throwaway Playwright MCP server (its name contains "throwaway").
 * Silent when the command already uses agent-browser, Lightpanda or chrome-headless-shell, or names a real
 * profile (`--profile`, `--profile-directory`, `--user-data-dir`, the chrome-profiles tools), when it only
 * reads text (grep, cat, git …), inside a subagent, and for 20 minutes per session per kind after firing.
 *
 * Escape: HEADLESS-TIER-SKIP anywhere in the command. Fails open.
 * Spoke: docs/headless-browser-tier-reminder.md.
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { allow, output, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { perUserGateDirectory } from "./lib/posttooluse-subhook-async-helpers-iter95.ts";
import {
  type EscapeHatchMarkerDetectionConfiguration,
  hasFileWideEscapeHatchMarkerInContent,
} from "./lib/escape-hatch-marker-detection-iter107.ts";

export const REMINDER_COOLDOWN_MS = 20 * 60 * 1000;

const ESCAPE_MARKER = "HEADLESS-TIER-SKIP";
const ESCAPE_HATCH: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  "markerNameTokenIncludingSuffix" | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
> = {
  markerNameTokenIncludingSuffix: ESCAPE_MARKER,
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 0,
};

/** Already on the decided stack: say nothing. */
const ON_THE_STACK = /\bagent-browser\b|\blightpanda\b|chrome-headless-shell/i;
/** The real profile is involved, which is the legitimate tier-3 or signed-in case. */
const NAMES_A_PROFILE = /--profile(-directory)?\b|--user-data-dir\b|chrome-profile\.sh|mcp-drive\.ts|fill-secret\.mjs/;
/** Commands that only read or search text mention these words without starting anything. */
const READ_ONLY_FIRST_WORD = /^\s*(rg|grep|egrep|ag|cat|bat|less|more|head|tail|sed|awk|wc|ls|find|fd|git|gh|echo|printf|man|which|type)\b/;
/**
 * Only the first 16 KB of a command is classified. The branded-browser pattern rescans the rest of a line from every
 * browser name, which on a single 400 KB line took 7.9 s (review, 2026-11-07); matching is synchronous, so the
 * orchestrator's timeout cannot cut it off. A browser launch that matters sits near the start of a command.
 */
export const MAX_CLASSIFIED_CHARS = 16 * 1024;

const HEAVY_LAUNCH: readonly RegExp[] = [
  /\b(chromium|firefox|webkit)\.(launch|launch_persistent_context|launchPersistentContext)\s*\(/,
  /\bpuppeteer\.launch\s*\(/,
  /\b(npx|bunx)\s+(-y\s+|--yes\s+)?@playwright\/mcp(@\S+)?(\s|$)/,
  /\bplaywright(@\S+)?\s+(screenshot|pdf|open|codegen|cr)\b/,
  /(Google Chrome|google-chrome(-stable)?|chromium(-browser)?|Chromium)\b[^|;&\n]*--headless/,
];
const PUBLISHES_A_PAGE: readonly RegExp[] = [
  /\borca\s+artifacts\s+(share|update)\b/,
  /\bwrangler\s+pages\s+deploy\b/,
];

export type Trigger = "launch" | "publish";

/** Which reminder a Bash command deserves, or null. Pure. */
export function classifyCommand(fullCommand: string): Trigger | null {
  const command = fullCommand.slice(0, MAX_CLASSIFIED_CHARS);
  if (!command || hasFileWideEscapeHatchMarkerInContent(command, ESCAPE_HATCH)) return null;
  if (ON_THE_STACK.test(command) || NAMES_A_PROFILE.test(command)) return null;
  if (READ_ONLY_FIRST_WORD.test(command)) return null;
  if (HEAVY_LAUNCH.some((re) => re.test(command))) return "launch";
  if (PUBLISHES_A_PAGE.some((re) => re.test(command))) return "publish";
  return null;
}

/** A throwaway (signed-out) Playwright MCP server: a full Chromium for work tier 1 could do. Pure. */
export function isThrowawayPlaywrightMcp(toolName: string): boolean {
  // Plain (`mcp__playwright-throwaway-headless__…`) or plugin-namespaced (`mcp__plugin_<p>_playwright-throwaway__…`).
  return /^mcp__(plugin_[^_]+_)?[^_]*playwright[^_]*throwaway[^_]*__/i.test(toolName) ||
    /^mcp__(plugin_[^_]+_)?[^_]*throwaway[^_]*playwright[^_]*__/i.test(toolName);
}

/**
 * True when this session's cooldown for `kind` has elapsed (and records now). No session id, or an
 * unwritable temp directory, means remind: a missed reminder costs more than a repeated one.
 */
export function claimCooldown(
  sessionId: unknown,
  kind: Trigger,
  nowMs: number = Date.now(),
  baseDir: string = tmpdir(),
): boolean {
  if (typeof sessionId !== "string" || sessionId === "" || /[/\\]/.test(sessionId)) return true;
  const directory = perUserGateDirectory(join(baseDir, ".claude-headless-browser-tier-reminder"));
  const stamp = join(directory, `${sessionId}.${kind}.last`);
  try {
    const last = Number(readFileSync(stamp, "utf8"));
    if (Number.isFinite(last) && nowMs - last < REMINDER_COOLDOWN_MS) return false;
  } catch {
    // No stamp yet.
  }
  try {
    mkdirSync(directory, { recursive: true });
    writeFileSync(stamp, String(nowMs));
  } catch {
    // Unwritable temp directory: remind anyway.
  }
  return true;
}

export function buildReminder(kind: Trigger): string {
  const head =
    kind === "publish"
      ? "[HEADLESS-BROWSER-TIER] This publishes a page. To check it, use the lightest browser that can do it, not desktop Chrome or a Playwright Chromium. Its text and links: tier 1. How it LOOKS (layout, styling, CJK glyphs): a tier-2 screenshot, because Lightpanda draws no CSS layout and shows CJK as empty boxes (measured 2026-11-07):"
      : "[HEADLESS-BROWSER-TIER] This starts a full browser for work that needs no window. Use the lightest tier that can do the job, all driven by `agent-browser`:";
  return [
    head,
    "1. Public pages (the default): `agent-browser --session S --engine lightpanda open <url>`; about 145 MB. Reads text, links and structure; its screenshots are unstyled, so never judge a page's look from one.",
    "2. A login, a page Lightpanda cannot render, or any check of how a page looks: `agent-browser --session S --executable-path <chrome-headless-shell> [--state <login.json>] open <url>`, where <chrome-headless-shell> is Google's Chrome for Testing headless shell on this host; about 600 MB. Read the login file from the vault at run time.",
    "3. Only when the real Chrome profile itself is needed (its cookies or bookmarks): `agent-browser --session S --profile \"<Profile dir>\" open <url>`, a copy deleted on close; about 2.3 GB. Work in the operator's own signed-in Chrome stays with the chrome-profiles tools.",
    "End every job with `agent-browser close --all`. If agent-browser, Lightpanda or chrome-headless-shell is not installed on this host, say so instead of falling back silently.",
    `This is a reminder, not a block. Skip it when a full browser is genuinely needed: put ${ESCAPE_MARKER} in the command.`,
  ].join("\n");
}

export async function main() {
  const input = await parseStdinOrAllow("HEADLESS-BROWSER-TIER-REMINDER");
  if (!input) return;
  const agentId = (input as { agent_id?: unknown }).agent_id;
  if (typeof agentId === "string" && agentId !== "") {
    allow();
    return;
  }
  let kind: Trigger | null = null;
  if (input.tool_name === "Bash") {
    const command = (input.tool_input as { command?: unknown } | undefined)?.command;
    kind = classifyCommand(typeof command === "string" ? command : "");
  } else if (typeof input.tool_name === "string" && isThrowawayPlaywrightMcp(input.tool_name)) {
    kind = "launch";
  }
  if (kind === null || !claimCooldown(input.session_id, kind)) {
    allow();
    return;
  }
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: buildReminder(kind),
    },
  });
}

// Standalone entry point (the throwaway Playwright MCP matcher). The Bash orchestrator imports `main`.
if (import.meta.main) void main().catch((err) => {
  trackHookError("pretooluse-headless-browser-tier-reminder", err instanceof Error ? err.message : String(err));
  allow();
});
