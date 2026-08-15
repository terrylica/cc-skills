#!/usr/bin/env bun
/**
 * PostToolUse hook: mini-inngest-doctrine soft nudge.
 *
 * Policy (operator directive 2026-07-06; SUBSTRATE RETARGETED 2026-08-15)
 * ──────────────────────────────────────────────────────────────────────
 * External/web-facing services and off-web monitors belong on the Mac Mini
 * as RESTATE tenants (the shared durable-execution engine), deployed with
 * `bun ../_engine/deploy.ts <tenant>` from a mini folder under
 * ~/eon/claude-sys/mac-minis/. This hook emits a soft, non-blocking nudge
 * (decision:"block" does NOT undo the tool per ADR 2025-12-17) when the agent
 * appears to be setting up such a service locally/manually instead.
 *
 * ── WHY THE GUIDANCE CHANGED, BUT THE HOOK DID NOT ──────────────────────────
 * This originally nudged toward INNGEST at ~/vj/cpc/mini-platform. Inngest is
 * retired: the operator ruled "Inngest has long been retired", ADR 0004 §5-F
 * deleted the last two Inngest-era launchd plists on 2026-08-15, and the mini
 * now runs six Restate tenants behind one restate-server singleton.
 *
 * So the hook was telling every author to build on a dead engine, at paths that
 * no longer exist — and authors were escaping it rather than following it. The
 * platform's own ~/eon/claude-sys/mac-minis/_engine/CLAUDE.md carries a
 * MINI-INNGEST-OK marker whose comment says Restate supersedes Inngest, i.e.
 * people were suppressing a hook that enforced a dead doctrine. That teaches
 * escaping hooks in general, which is far more expensive than the original bug.
 *
 * The PRINCIPLE survived the migration untouched — do not hand-roll a bespoke
 * local cron/StartInterval script for work that belongs on the always-on mini —
 * so the detection heuristic is unchanged and only the guidance was corrected.
 *
 * THE ESCAPE MARKER IS DELIBERATELY STILL `MINI-INNGEST-OK`, despite naming a
 * retired engine. Renaming it would silently un-escape every file already using
 * it across ~/own/amonic, ~/eon/claude-sys and this repo, turning a docs fix
 * into a fleet-wide false-positive storm. A slightly stale marker name is much
 * cheaper than that.
 *
 * Trigger heuristic: the tool payload (Bash command, or Write/Edit content)
 * matches web-facing / off-web-monitoring signals — launchd/LaunchAgent plist
 * creation, `launchctl bootstrap|load`, `crontab`, `StartInterval`, OR keyword
 * clusters `webhook|poll|scrape|monitor|uptime|cron|imap|smtp|deploy|serve`
 * — AND an external target is present (use `isRemoteCommand()` via the shared
 * readonly-command-detector helper; pure-local dev that binds localhost/
 * 127.0.0.1/.local/tailnet must NOT fire).
 *
 * Escape hatch: add `MINI-INNGEST-OK` anywhere in the file/command content
 * to silence the nudge (via the iter-107 canonical marker helper).
 *
 * Fail-open: any error or non-detection exits 0 silently. Never blocks real
 * work. Honors the CLAUDE_HOOK_SPAWNED recursion guard.
 *
 * Channel choice: PostToolUse {decision:"block", reason} — the Claude-visible
 * channel per ADR 2025-12-17. Soft nudge only, never blocking.
 *
 * References:
 *   - ADR: docs/adr/2026-07-06-mini-inngest-doctrine-hook.md
 *   - Workflow architecture (explanation SSoT): ~/.claude/skills/homelab/references/workflows.md
 *   - Deployment guide (how-to): homelab skill
 */

import { trackHookError } from "./lib/hook-error-tracker.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import { isRemoteCommand } from "./lib/readonly-command-detector.ts";

// ── Types ────────────────────────────────────────────────────────────────────

interface HookInput {
  tool_name: string;
  tool_input?: {
    command?: string;
    file_path?: string;
    content?: string;
  };
  session_id?: string;
}

// ── Configuration ────────────────────────────────────────────────────────────

const MINI_INNGEST_OK_ESCAPE_HATCH_MARKER_DETECTION_CONFIG = {
  markerNameTokenIncludingSuffix: "MINI-INNGEST-OK",
  caseSensitivityMode: "CASE_SENSITIVE" as const,
};

// ── Detection ────────────────────────────────────────────────────────────────

/**
 * Check if the payload shows signals of an external-service setup that
 * should be running on the Mac Mini instead.
 *
 * Returns true if EITHER:
 *   1. An explicit launchd/cron context is detected (strong signal alone)
 *   2. OR a keyword appears with external URL AND is in actionable context
 */
function detectExternalServiceIntent(content: string, isExternal: boolean): boolean {
  // Explicit context clues that are strong enough standalone
  const explicitContextPatterns = [
    /\blaunchctl\b\s+(bootstrap|load)/,
    /\bLaunchAgent\b|\bLaunchDaemons?\b/,
    /\bStartInterval\b/,
    /\.plist\b.*launchd|launchd.*\.plist/i,
    /\bcrontab\b/,
    /\bcron\b\s+-e/,
  ];

  for (const pattern of explicitContextPatterns) {
    if (pattern.test(content)) {
      return true;
    }
  }

  // For other keywords, require external target presence AND actionable patterns
  if (!isExternal) return false;

  // Match keywords in parameter assignments or function calls
  // Examples: --webhook-url, webhook_url=, webhook(, --forward, monitor_endpoint
  const actionableKeywordPatterns = [
    /webhook[_-]?(?:url|endpoint).*https?:\/\/[a-z0-9.-]+\.[a-z]{2,}/i,
    /poll[_-]?(?:url|endpoint|host|server).*https?:\/\/[a-z0-9.-]+\.[a-z]{2,}/i,
    /monitor[_-]?(?:url|endpoint|host|server).*https?:\/\/[a-z0-9.-]+\.[a-z]{2,}/i,
    /uptime[_-]?(?:url|endpoint|host|server).*https?:\/\/[a-z0-9.-]+\.[a-z]{2,}/i,
    /(?:forward|redirect|notify)[_-]?(?:to|url|endpoint).*https?:\/\/[a-z0-9.-]+\.[a-z]{2,}/i,
    /--(?:webhook|poll|monitor|forward|endpoint).* https?:\/\/[a-z0-9.-]+\.[a-z]{2,}/i,
  ];

  for (const pattern of actionableKeywordPatterns) {
    if (pattern.test(content)) {
      return true;
    }
  }

  return false;
}

/**
 * Check if a command/file refers to an external target (non-localhost,
 * non-.local, non-tailnet). Uses the readonly-command-detector's isRemoteCommand
 * for SSH classification + heuristics for other external references.
 *
 * Returns true if ANY external hostname/IP is found (not localhost/127.0.0.1/
 * .local/tailnet); returns false if only local references are present.
 */
function isExternalTarget(content: string): boolean {
  // SSH to non-localhost/127.0.0.1 — isRemoteCommand already filters out localhost
  if (isRemoteCommand(content)) {
    return true;
  }

  // Look for hostname/domain patterns (simplified to avoid complex lookahead)
  // Match: anything.something (e.g. api.example.com, monitoring.io)
  // or IP addresses (192.168.1.1, etc.)
  const hostnamePattern = /[a-z0-9.-]+\.[a-z]{2,}|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/gi;
  const matches = content.match(hostnamePattern);

  if (!matches) return false;

  // Filter out local/loopback domains
  for (const hostname of matches) {
    const lowerHostname = hostname.toLowerCase();
    // Exclude localhost, 127.x.x.x, ::1, .local, .ts.net, .tailscale.net, .tailnet
    if (
      lowerHostname === "localhost" ||
      lowerHostname.startsWith("127.") ||
      lowerHostname === "::1" ||
      lowerHostname.endsWith(".local") ||
      lowerHostname.includes(".tail") ||
      lowerHostname.includes(".tailscale.net") ||
      lowerHostname.includes(".tailnet")
    ) {
      continue;
    }
    // This is an external hostname
    return true;
  }

  return false;
}

export function detectMiniInngestDoctrineFire(input: HookInput): {
  matched: boolean;
} {
  const ti = input.tool_input || {};

  // Bash: check command
  if (input.tool_name === "Bash") {
    const command = ti.command || "";
    if (!command.trim()) {
      return { matched: false };
    }

    if (
      hasFileWideEscapeHatchMarkerInContent(
        command,
        MINI_INNGEST_OK_ESCAPE_HATCH_MARKER_DETECTION_CONFIG,
      )
    ) {
      return { matched: false };
    }

    const isExternal = isExternalTarget(command);
    return {
      matched: detectExternalServiceIntent(command, isExternal),
    };
  }

  // Write/Edit: check file content
  if (input.tool_name === "Write" || input.tool_name === "Edit") {
    const content = ti.content || "";
    if (!content.trim()) {
      return { matched: false };
    }

    if (
      hasFileWideEscapeHatchMarkerInContent(
        content,
        MINI_INNGEST_OK_ESCAPE_HATCH_MARKER_DETECTION_CONFIG,
      )
    ) {
      return { matched: false };
    }

    const isExternal = isExternalTarget(content);
    return {
      matched: detectExternalServiceIntent(content, isExternal),
    };
  }

  return { matched: false };
}

// ── Reminder ─────────────────────────────────────────────────────────────────

export function buildReminder(): string {
  return [
    // Prefix deliberately still says MINI-INNGEST, matching the escape marker below. Renaming the
    // user-visible token while the marker it pairs with stays MINI-INNGEST-OK would make the nudge
    // harder to silence, not easier — the reader would have no way to guess the marker from it.
    "[MINI-INNGEST] External/web-facing service or off-web monitor detected.",
    "These belong on the Mac Mini as a RESTATE tenant (the shared durable-execution engine),",
    "not as a bespoke local cron/launchd StartInterval script on your laptop.",
    "Deployment path:",
    "  1. Add the tenant to mini.config.ts + services/<name>/ in",
    "     ~/eon/claude-sys/mac-minis/<serial>_<nickname>/",
    "  2. Deploy:  cd <that mini dir> && bun ../_engine/deploy.ts <tenant>",
    "  3. Inspect: restate services list / restate invocations list (on the mini)",
    "Escape hatch: add MINI-INNGEST-OK to this file if this is intentionally local-only.",
  ].join("\n");
}

// ── Entrypoint ───────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  // Recursion guard: if this hook is already running, bail out.
  if (process.env.CLAUDE_HOOK_SPAWNED === "posttooluse-mini-inngest-doctrine") {
    process.exit(0);
  }

  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let input: HookInput;
  try {
    input = JSON.parse(inputText) as HookInput;
  } catch {
    process.exit(0); // invalid JSON → fail-open
  }

  if (!["Bash", "Write", "Edit"].includes(input.tool_name)) {
    process.exit(0);
  }

  const { matched } = detectMiniInngestDoctrineFire(input);
  if (matched) {
    console.log(JSON.stringify({ decision: "block", reason: buildReminder() }));
  }

  process.exit(0);
}

// Run only as a hook entrypoint; stay importable by tests.
if (import.meta.main) {
  main().catch((err) => {
    trackHookError(
      "posttooluse-mini-inngest-doctrine",
      err instanceof Error ? err.message : String(err),
    );
    process.exit(0);
  });
}
