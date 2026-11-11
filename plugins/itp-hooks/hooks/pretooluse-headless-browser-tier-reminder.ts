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
import { walkShellInvocations } from "./lib/shell-command-invocation-walker.ts";

export const REMINDER_COOLDOWN_MS = 20 * 60 * 1000;

const ESCAPE_MARKER = "HEADLESS-TIER-SKIP";
const ESCAPE_HATCH: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  "markerNameTokenIncludingSuffix" | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
> = {
  markerNameTokenIncludingSuffix: ESCAPE_MARKER,
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 0,
};

/** Already on the decided stack: say nothing. Checked per invocation, so `…; agent-browser close` cannot silence a launch. */
const ON_THE_STACK = /\bagent-browser\b|\blightpanda\b|chrome-headless-shell/i;
/** The real profile is involved, which is the legitimate tier-3 or signed-in case. */
const NAMES_A_PROFILE = /--profile(-directory)?\b|--user-data-dir\b|chrome-profile\.sh|mcp-drive\.ts|fill-secret\.mjs/;
/**
 * Only the first 16 KB of a command is classified. A launch that matters sits near the start of a command, and
 * matching is synchronous, so the orchestrator's timeout cannot cut a slow match off (review, 2026-11-07).
 */
export const MAX_CLASSIFIED_CHARS = 16 * 1024;

/** A launch written as code: only meaningful as an interpreter's inline script or a heredoc it reads. */
const CODE_LAUNCH = /\b(chromium|firefox|webkit)\.(launch|launch_persistent_context|launchPersistentContext)\s*\(|\bpuppeteer\.launch\s*\(/;
/** Programs that run code given inline (`-c`, `-e`, `eval`) or on stdin. */
const INTERPRETER = /^(node|bun|deno|python[0-9.]*|uv|uvx|tsx|ts-node|ruby|npx|bunx)$/;
/** Package runners that put a CLI's name in the first argument. */
const RUNNER = /^(npx|bunx|pnpx)$|^(pnpm|yarn)$/;
const BRANDED_BROWSER = /^(Google Chrome|google-chrome(-stable)?|chromium(-browser)?|Chromium|chrome|msedge|Microsoft Edge)$/;
const PLAYWRIGHT_CLI_SUBCOMMAND = new Set(["screenshot", "pdf", "open", "codegen", "cr"]);
/** Runner flags that come before the package name (`npx -y`, `pnpm dlx`). */
const RUNNER_PREFIX = new Set(["-y", "--yes", "dlx", "exec", "-p", "--package"]);

export type Trigger = "launch" | "publish";

/** The CLI an invocation really runs, with its arguments: unwraps `npx -y pkg@1 …`, `pnpm dlx pkg …`. */
function effectiveCli(program: string, args: string[]): { cli: string; rest: string[] } {
  if (!RUNNER.test(program)) return { cli: program, rest: args };
  let i = 0;
  while (i < args.length && RUNNER_PREFIX.has(args[i])) i++;
  const pkg = args[i] ?? "";
  return { cli: pkg.replace(/^(@[^/@]+\/[^@]+|[^@]+)@.*$/, "$1"), rest: args.slice(i + 1) };
}

/** Which reminder one real program invocation deserves, or null. Pure. */
function classifyInvocation(program: string, args: string[]): Trigger | null {
  if (args.includes("--help") || args.includes("-h")) return null;
  const text = [program, ...args].join(" ");
  if (ON_THE_STACK.test(text) || NAMES_A_PROFILE.test(text)) return null;
  const { cli, rest } = effectiveCli(program, args);
  if (cli === "@playwright/mcp") return "launch";
  if (cli === "playwright" && PLAYWRIGHT_CLI_SUBCOMMAND.has(rest[0] ?? "")) return "launch";
  if (BRANDED_BROWSER.test(program) && args.some((a) => a === "--headless" || a.startsWith("--headless="))) return "launch";
  if (INTERPRETER.test(program) && args.some((a) => CODE_LAUNCH.test(a))) return "launch";
  if (cli === "orca" && rest[0] === "artifacts" && (rest[1] === "share" || rest[1] === "update")) return "publish";
  if (cli === "wrangler" && rest[0] === "pages" && rest[1] === "deploy") return "publish";
  return null;
}

/**
 * Which reminder a Bash command deserves, or null. Pure.
 *
 * Classifies each program the shell would actually run (`walkShellInvocations`: through `&&`, pipes, `bash -c`,
 * substitutions, past assignments and wrappers), so a word inside a quoted argument to grep, gh or echo, a comment,
 * or a heredoc fed to cat/tee never fires. A heredoc body is not an argument, so a code launch fed to an interpreter
 * on stdin (`python3 - <<'EOF'`) is checked against the whole command. A script file (`node shot.js`) is invisible.
 */
export function classifyCommand(fullCommand: string): Trigger | null {
  const command = fullCommand.slice(0, MAX_CLASSIFIED_CHARS);
  if (!command || hasFileWideEscapeHatchMarkerInContent(command, ESCAPE_HATCH)) return null;
  let launch = false;
  let publish = false;
  let interpreterReadsHeredoc = false;
  walkShellInvocations(command, /./, (invocation) => {
    const args = invocation.args.map((w) => w.value);
    const kind = classifyInvocation(invocation.program, args);
    if (kind === "launch") launch = true;
    else if (kind === "publish") publish = true;
    if (INTERPRETER.test(invocation.program)) interpreterReadsHeredoc = true;
  });
  if (launch) return "launch";
  if (interpreterReadsHeredoc && /<<-?\s*['"]?\w/.test(command) && CODE_LAUNCH.test(command) &&
    !ON_THE_STACK.test(command) && !NAMES_A_PROFILE.test(command)) return "launch";
  return publish ? "publish" : null;
}

/**
 * A throwaway (signed-out) Playwright MCP server: a full Chromium for work tier 1 could do. Pure.
 * The server segment (between `mcp__` and the next `__`) must name both "playwright" and "throwaway"; plugin names
 * may contain `_`, so the segment is matched up to the `__` separator, not up to any `_`.
 */
export function isThrowawayPlaywrightMcp(toolName: string): boolean {
  const server = /^mcp__(.+?)__/.exec(toolName)?.[1] ?? "";
  return /playwright/i.test(server) && /throwaway/i.test(server);
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

interface HookInput {
  tool_name?: unknown;
  tool_input?: unknown;
  session_id?: unknown;
  agent_id?: unknown;
}

/** The reminder text this tool call deserves (claiming the cooldown), or null. */
export function reminderFor(input: HookInput): string | null {
  if (typeof input.agent_id === "string" && input.agent_id !== "") return null;
  let kind: Trigger | null = null;
  if (input.tool_name === "Bash") {
    const command = (input.tool_input as { command?: unknown } | undefined)?.command;
    kind = classifyCommand(typeof command === "string" ? command : "");
  } else if (typeof input.tool_name === "string" && isThrowawayPlaywrightMcp(input.tool_name)) {
    kind = "launch";
  }
  if (kind === null || !claimCooldown(input.session_id, kind)) return null;
  return buildReminder(kind);
}

const remind = (text: string) =>
  output({ hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: text } });

/** Bash orchestrator entry point (in-process): the orchestrator merges `allow` with its sibling guards. */
export async function main() {
  const input = await parseStdinOrAllow("HEADLESS-BROWSER-TIER-REMINDER");
  if (!input) return;
  const text = reminderFor(input);
  if (text === null) allow();
  else remind(text);
}

/**
 * Standalone entry point (the MCP matcher in hooks.json). It must never print `permissionDecision: "allow"`, which
 * skips the user's permission prompt for that MCP tool: when there is nothing to remind, or on any error, it prints
 * nothing and exits 0, which leaves the normal permission flow untouched.
 */
async function standaloneMain() {
  let input: HookInput;
  try {
    input = JSON.parse(await Bun.stdin.text()) as HookInput;
  } catch (err) {
    trackHookError("pretooluse-headless-browser-tier-reminder", `Failed to parse stdin: ${String(err)}`);
    return;
  }
  const text = reminderFor(input);
  if (text !== null) remind(text);
}

if (import.meta.main) void standaloneMain().catch((err) => {
  trackHookError("pretooluse-headless-browser-tier-reminder", err instanceof Error ? err.message : String(err));
});
