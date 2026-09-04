#!/usr/bin/env bun
/**
 * PreToolUse hook: Pueue Local Submission Guard
 *
 * Detects `pueue add` commands that contain remote-context indicators
 * (remote paths, hostnames, remote-only binaries) and denies them.
 * This prevents accidental local execution of commands intended for
 * a remote host.
 *
 * Root cause: When Claude Code runs `pueue add` inside a background
 * Bash task, the SSH context is lost and commands execute locally.
 *
 * Escape hatch: # PUEUE-LOCAL-OK comment bypasses the guard.
 * SSH-wrapped commands are automatically skipped.
 */

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";

/**
 * Remote hostnames to treat as remote-context indicators.
 *
 * This hook ships in a public marketplace, so no specific hostname is baked in
 * — a maintainer's private host names would otherwise be published to every
 * installer, and would match nothing on their machines anyway. Configure your
 * own, either way:
 *
 *   ITP_REMOTE_HOSTS=host1,host2          (env var, wins if set)
 *   ${XDG_CONFIG_HOME:-~/.config}/itp-hooks/remote-hosts   (one host per line,
 *                                          `#` comments and blanks ignored)
 *
 * With neither configured this returns [] and the guard still works: every
 * generic indicator below (Linux /home paths, remote-only binaries,
 * clickhouse-client, `-w /home/`) fires exactly as before. Only the
 * hostname-specific checks become opt-in, so the public default costs nothing
 * and fails silently rather than noisily.
 */
function configuredRemoteHosts(): string[] {
  const fromEnv = process.env.ITP_REMOTE_HOSTS;
  if (fromEnv !== undefined && fromEnv.trim() !== "") {
    return fromEnv.split(",").map((h) => h.trim()).filter(Boolean);
  }
  const configHome = process.env.XDG_CONFIG_HOME || join(homedir(), ".config");
  const configPath = join(configHome, "itp-hooks", "remote-hosts");
  try {
    if (!existsSync(configPath)) return [];
    return readFileSync(configPath, "utf8")
      .split("\n")
      .map((line) => line.replace(/#.*$/, "").trim())
      .filter(Boolean);
  } catch {
    // A malformed or unreadable config must never break the guard.
    return [];
  }
}

/** Escape a hostname for safe embedding in a RegExp. */
function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Escape hatch — explicit opt-in for local pueue submission */
const LOCAL_OK_COMMENT = /# *PUEUE-LOCAL-OK/i;

/** Detect pueue add (the submission command) */
const PUEUE_ADD = /\bpueue\s+add\b/;

/** Detect SSH-wrapped commands (already targeting remote) */
const SSH_WRAPPED = /\bssh\s+\S+/;

/**
 * Remote-context indicators — patterns that suggest a command
 * was intended for a remote Linux host, not the local macOS machine.
 */
const REMOTE_CONTEXT_PATTERNS: { pattern: RegExp; label: string }[] = [
  // Remote temp paths (gen/sweep scripts only exist on the remote host)
  { pattern: /\/tmp\/gen\d/, label: "/tmp/gen*" },
  { pattern: /\/tmp\/sweep_/, label: "/tmp/sweep_*" },

  // Linux home paths (macOS uses /Users/)
  { pattern: /\/home\/\w/, label: "/home/ path" },

  // Remote-only binary paths
  { pattern: /~\/\.local\/bin\//, label: "~/.local/bin/" },

  // Explicit hostname references — opt-in, see configuredRemoteHosts() above
  ...configuredRemoteHosts().map((host) => ({
    pattern: new RegExp(`\\b${escapeRegExp(host)}\\b`, "i"),
    label: host,
  })),

  // Remote working directory flag
  { pattern: /-w\s+\/home\//, label: "-w /home/" },

  // ClickHouse client (not installed locally)
  { pattern: /\bclickhouse-client\b/, label: "clickhouse-client" },
];

async function main() {
  const input = await parseStdinOrAllow("PUEUE-LOCAL-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;

  // Only check Bash commands
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";

  // Fast path: not a pueue add command
  if (!PUEUE_ADD.test(command)) {
    allow();
    return;
  }

  // Escape hatch: explicit local OK
  if (LOCAL_OK_COMMENT.test(command)) {
    allow();
    return;
  }

  // Already SSH-wrapped — targeting remote correctly
  if (SSH_WRAPPED.test(command)) {
    allow();
    return;
  }

  // Check for remote-context indicators
  const matches = REMOTE_CONTEXT_PATTERNS.filter((p) =>
    p.pattern.test(command)
  );

  if (matches.length === 0) {
    allow();
    return;
  }

  const indicators = matches.map((m) => m.label).join(", ");
  deny(
    `BLOCKED: pueue add with remote-context indicators detected (${indicators}). ` +
      `This command appears intended for a remote host but would execute locally. ` +
      `Wrap with SSH: \`ssh <remote-host> 'pueue add ...'\`. ` +
      `Add \`# PUEUE-LOCAL-OK\` to bypass this guard.`
  );
}

main().catch((err) => {
  trackHookError("pretooluse-pueue-local-guard", err instanceof Error ? err.message : String(err));
  allow();
});
