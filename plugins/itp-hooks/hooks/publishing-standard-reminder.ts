#!/usr/bin/env bun
/**
 * Publishing-standard reminder: one line pointing at Skill(devops-tools:publishing-standard) when a session creates an
 * HTML page or publishes pages, so every page carries a live "changed N ago" marker, its build time, version, commit
 * and source, a link to its index, one registry record and a place on the sitemap.
 *
 * Two entry points, each at most once per session (separate gates, so a session that writes pages and later
 * publishes them is reminded at both moments):
 *   - `main` (PreToolUse, Bash; run in-process by pretooluse-bash-guard-orchestrator.ts): before a publish command
 *     (wrangler deploy / pages deploy / versions deploy, orca artifacts share|update, netlify deploy, vercel deploy or
 *     --prod, firebase deploy, surge, gh-pages), as additionalContext. Never denies.
 *   - `classifyPublishingStandardReminderForPostToolUseOrchestrator` (PostToolUse, Write/Edit; registered in
 *     posttooluse-write-edit-orchestrator.ts): after a Write/Edit of an .html/.htm/.xhtml file outside temp scratch
 *     directories.
 *
 * Generic on purpose (this repository is public): no host, account, repository or machine names.
 * Escape: PUBLISHING-STANDARD-OK in the command. Fails open. Spoke: docs/publishing-standard-reminder.md.
 */

import { allow, output, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import type { PostToolUseInput, PostToolUseSubhookDecision } from "./lib/posttooluse-subhook-contract-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
  isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook,
} from "./lib/posttooluse-subhook-contract-iter93.ts";
import { tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName } from "./lib/posttooluse-subhook-async-helpers-iter95.ts";
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temp-dir-edit-path-detection-iter124.ts";
import { type ShellInvocation, walkShellInvocations } from "./lib/shell-command-invocation-walker.ts";

export const ESCAPE_MARKER = "PUBLISHING-STANDARD-OK";

export const REMINDER =
  "[PUBLISHING-STANDARD] Follow Skill(devops-tools:publishing-standard) for every page: a live \"changed N ago\" " +
  "marker with a heat dot, the exact build time, version, commit and source, a link back to its index, one record in " +
  "exactly one registry (published.v1), and the sitemap regenerated after the deploy is recorded.";

const RUNNERS = new Set(["npx", "bunx", "pnpx"]);
const PROGRAMS = /wrangler|orca|netlify|vercel|firebase|surge|gh-pages/;

/** The program an invocation really runs and its arguments, looking through npx/bunx/pnpx and pnpm/yarn dlx, with a
 * trailing @version dropped (`wrangler@4` -> `wrangler`). */
function resolved(inv: ShellInvocation): { prog: string; args: string[] } {
  let prog = inv.program;
  let args = inv.args.map((w) => w.value);
  if (RUNNERS.has(prog) || ((prog === "pnpm" || prog === "yarn") && args[0] === "dlx")) {
    if (args[0] === "dlx") args = args.slice(1);
    const i = args.findIndex((t) => !t.startsWith("-"));
    if (i < 0) return { prog: "", args: [] };
    prog = args[i];
    args = args.slice(i + 1);
  }
  return { prog: prog.replace(/(.)@[\w.^~-]+$/, "$1"), args };
}

function publishes(prog: string, args: string[]): boolean {
  const pos = args.filter((t) => !t.startsWith("-"));
  switch (prog) {
    case "wrangler": {
      const at = args.indexOf("deploy");
      return at !== -1 && args.slice(0, at).filter((t) => !t.startsWith("-")).every((t) => t === "pages" || t === "versions");
    }
    case "orca":
      return pos[0] === "artifacts" && (pos[1] === "share" || pos[1] === "update");
    case "netlify":
    case "firebase":
      return pos[0] === "deploy";
    case "vercel":
      return pos[0] === "deploy" || args.includes("--prod");
    case "surge":
      return pos.length > 0;
    case "gh-pages":
      return args.includes("-d") || args.includes("--dist");
    default:
      return false;
  }
}

/** A command that publishes pages: an invocation the shell would actually run (the shared walker, so `cat`, `grep`,
 * quoted text or a heredoc that only MENTIONS a publish does not count), not a dry run or a help request. */
export function isPublishCommand(cmd: string): boolean {
  if (!cmd || cmd.includes(ESCAPE_MARKER)) return false;
  let found = false;
  walkShellInvocations(cmd, PROGRAMS, (inv) => {
    if (found) return;
    const { prog, args } = resolved(inv);
    if (publishes(prog, args) && !args.some((t) => t === "--dry-run" || t === "-h" || t === "--help")) found = true;
  });
  return found;
}

const PAGE_EXTENSIONS = [".html", ".htm", ".xhtml"];

export function isHtmlPagePath(filePath: unknown): boolean {
  if (typeof filePath !== "string" || !filePath) return false;
  const lower = filePath.toLowerCase();
  return PAGE_EXTENSIONS.some((ext) => lower.endsWith(ext));
}

/** The session id as a gate file name, or "" when absent or not one plain path component (the gate helper puts it
 * straight into a /tmp path). */
export function gateKey(sessionId: unknown): string {
  return typeof sessionId === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(sessionId) ? sessionId : "";
}

/** PreToolUse (Bash): remind before a publish command, once per session. */
export async function main(): Promise<void> {
  const input = await parseStdinOrAllow("PUBLISHING-STANDARD-REMINDER");
  if (!input) return;
  const cmd = (input.tool_input as { command?: unknown } | undefined)?.command;
  if (input.tool_name !== "Bash" || typeof cmd !== "string" || !isPublishCommand(cmd)) {
    allow();
    return;
  }
  const session = gateKey(input.session_id);
  // No usable session id: nothing to gate on, so stay silent rather than remind on every call.
  if (!session || !tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName("publishing-standard-publish", session)) {
    allow();
    return;
  }
  output({ hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: REMINDER } });
}

/** PostToolUse (Write/Edit): remind after an HTML page is written, once per session. */
export async function classifyPublishingStandardReminderForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    if (!isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(input.tool_name)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    const filePath = input.tool_input?.file_path;
    if (!isHtmlPagePath(filePath)) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    if (isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    const session = gateKey(input.session_id);
    if (!session) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    if (!tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName("publishing-standard-page", session)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    return buildPostToolUseAdditionalContextDecision(REMINDER);
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

// Standalone entry point. The Bash orchestrator imports `main` and runs it in-process.
if (import.meta.main) void main().catch((err) => {
  trackHookError("publishing-standard-reminder", err instanceof Error ? err.message : String(err));
  allow();
});
