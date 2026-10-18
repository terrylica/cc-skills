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
import { walkShellInvocations } from "./lib/shell-command-invocation-walker.ts";

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

/** pueue global options that take a value. */
const PUEUE_GLOBAL_OPTIONS_WITH_VALUE: ReadonlySet<string> = new Set(["-c", "--config", "-p", "--profile", "--color"]);

/** Cheap prefilter before lexing: nothing to do unless `pueue` appears at all. */
const MENTIONS_PUEUE = /\bpueue\b/;

/** `/home/<user>` prefixes named in the text. */
const HOME_PREFIX = /\/home\/([\w.-]+)/g;

/**
 * Is a Linux `/home/<user>` path in this text REMOTE?
 *
 * The guard was written on a Mac, where no local path starts with `/home/`, so every `/home/` path
 * was taken as proof of a remote target. On a Linux host (el02, the fleet's research machine) the
 * same path is the local home directory, and every local `pueue add` naming a file in it was
 * denied (2026-10-17; the repository there had to carry a standing PUEUE-LOCAL-OK rule). A
 * `/home/<user>` that exists on THIS machine is local; one that does not is still an indicator.
 */
function namesNonLocalHome(text: string): boolean {
  for (const match of text.matchAll(HOME_PREFIX)) {
    if (!existsSync(`/home/${match[1]}`)) return true;
  }
  return false;
}

/**
 * Remote-context indicators — patterns that suggest a command was intended for a remote host, not
 * this machine. Each one is tested against the `pueue add` invocation's own arguments, and the
 * path and binary indicators only count when the thing they name does not exist locally.
 */
interface RemoteIndicator {
  readonly label: string;
  readonly test: (text: string) => boolean;
}

function remoteContextIndicators(): RemoteIndicator[] {
  const localBin = join(homedir(), ".local", "bin");
  return [
    // Remote temp paths (gen/sweep scripts only exist on the remote host)
    { label: "/tmp/gen*", test: (t) => /\/tmp\/gen\d/.test(t) },
    { label: "/tmp/sweep_*", test: (t) => /\/tmp\/sweep_/.test(t) },

    // Linux home paths, unless that home exists here
    { label: "/home/ path not on this machine", test: namesNonLocalHome },

    // Remote-only binary paths, unless this machine has ~/.local/bin too
    { label: "~/.local/bin/", test: (t) => /~\/\.local\/bin\//.test(t) && !existsSync(localBin) },

    // Explicit hostname references — opt-in, see configuredRemoteHosts() above
    ...configuredRemoteHosts().map((host) => {
      const pattern = new RegExp(`\\b${escapeRegExp(host)}\\b`, "i");
      return { label: host, test: (t: string) => pattern.test(t) };
    }),

    // ClickHouse client, unless it is installed here
    { label: "clickhouse-client", test: (t) => /\bclickhouse-client\b/.test(t) && Bun.which("clickhouse-client") === null },
  ];
}

/**
 * The argument text of every real `pueue add` INVOCATION in the command.
 *
 * Matched with the shared invocation walker, so `pueue add` in a quoted grep pattern, a commit
 * message, a comment or a heredoc written to a file is not an invocation (2026-10-17: a read-only
 * `grep -rln 'TASK_ID=$(pueue add' ~/.claude/…` was denied because the text `pueue add` and a
 * `/home/` path both appeared somewhere in it). `pueue add` inside `ssh host '…'` targets the remote
 * already and is skipped, as the bare SSH check did before.
 */
export function localPueueAddArguments(command: string): string[] {
  const found: string[] = [];
  walkShellInvocations(command, MENTIONS_PUEUE, (invocation) => {
    if (invocation.program !== "pueue" || invocation.context === "ssh remote command") return;
    // pueue's GLOBAL options come before the subcommand (`pueue -p prof add`, `pueue --color
    // never add`); found in review, 2026-10-17.
    const args = invocation.args.map((w) => w.value);
    let a = 0;
    while (a < args.length && args[a]!.startsWith("-")) {
      a += PUEUE_GLOBAL_OPTIONS_WITH_VALUE.has(args[a]!) ? 2 : 1;
    }
    if (args[a] !== "add") return;
    found.push(args.join(" "));
  });
  return found;
}

/** Labels of the remote-context indicators in the command's `pueue add` invocations. */
export function remoteIndicatorsIn(command: string): string[] {
  const invocations = localPueueAddArguments(command);
  if (invocations.length === 0) return [];
  const labels = new Set<string>();
  for (const indicator of remoteContextIndicators()) {
    if (invocations.some((args) => indicator.test(args))) labels.add(indicator.label);
  }
  return [...labels];
}

export async function main() {
  const input = await parseStdinOrAllow("PUEUE-LOCAL-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;

  // Only check Bash commands
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";

  // Fast path: pueue not mentioned at all
  if (!MENTIONS_PUEUE.test(command)) {
    allow();
    return;
  }

  // Escape hatch: explicit local OK
  if (LOCAL_OK_COMMENT.test(command)) {
    allow();
    return;
  }

  const indicators = remoteIndicatorsIn(command);
  if (indicators.length === 0) {
    allow();
    return;
  }

  deny(
    `BLOCKED: pueue add with remote-context indicators detected (${indicators.join(", ")}). ` +
      `This command appears intended for a remote host but would execute locally. ` +
      `Wrap with SSH: \`ssh <remote-host> 'pueue add ...'\`. ` +
      `Add \`# PUEUE-LOCAL-OK\` to bypass this guard.`
  );
}

// Standalone entry point. The Bash orchestrator (#111) imports `main` and runs it in-process.
if (import.meta.main) void main().catch((err) => {
  trackHookError("pretooluse-pueue-local-guard", err instanceof Error ? err.message : String(err));
  allow();
});
