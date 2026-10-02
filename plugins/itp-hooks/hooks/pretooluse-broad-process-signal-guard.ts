#!/usr/bin/env bun

/**
 * PreToolUse hook: broad process-signal guard (kill guard v2).
 *
 * Bash: denies a kill / pkill / killall that is broad by construction — `kill -1` or `kill 0` as a
 * target, a shared runtime or host program by name (`pkill node`, `killall bun`, `kill $(pgrep
 * claude)`), a user-wide `-u` with no name, or a pkill pattern whose literal text is under five
 * characters. Detection: lib/broad-process-signal-detector.ts.
 *
 * Write / Edit of a SHELL SCRIPT: runs that check AND the pkill option-order check on
 * the text being written. v1 (pretooluse-pkill-option-after-pattern-guard.ts) inspected only Bash
 * commands, so a script written first and run second passed straight through — its documented gap.
 *
 * WHY. Measured 2026-09-27: one pattern-aimed pkill SIGTERMed eight Claude Code sessions and every
 * Electron app's crash reporter on the operator's Mac. The kernel sandbox now confines sandboxed
 * commands to their own subtree, but unsandboxed sessions, ssh remote commands and hosts without
 * the managed policy still reach everything the user owns. Signalling the PID you started is always
 * possible and never broad.
 *
 * Spoke: docs/broad-process-signal-guard.md. Fails open on its own errors.
 */

import { existsSync, readFileSync } from "node:fs";
import {
  type EscapeHatchMarkerDetectionConfiguration,
  hasFileWideEscapeHatchMarkerInContent,
} from "./lib/escape-hatch-marker-detection-iter107.ts";
import {
  type BroadProcessSignalFinding,
  findBroadProcessSignals,
  MINIMUM_SPECIFIC_PATTERN_LITERAL_LENGTH,
} from "./lib/broad-process-signal-detector.ts";
import { findPkillOptionAfterPattern } from "./lib/pkill-option-after-pattern-detector.ts";
import { explainPkillOptionOrderFindings } from "./pretooluse-pkill-option-after-pattern-guard.ts";
import {
  allow,
  deny,
  parseStdinOrAllow,
  trackHookError,
} from "./pretooluse-helpers.ts";

type EscapeConfig = Pick<
  EscapeHatchMarkerDetectionConfiguration,
  | "markerNameTokenIncludingSuffix"
  | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
>;

/** Operator escape hatch. A >=10-character justification is mandatory. */
const BROAD_SIGNAL_ESCAPE_HATCH: EscapeConfig = {
  markerNameTokenIncludingSuffix: "BROAD-PROCESS-SIGNAL-OK",
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
};

/** v1's escape, honoured for the option-order check this hook now applies to scripts. */
const PKILL_OPTION_ORDER_ESCAPE_HATCH: EscapeConfig = {
  markerNameTokenIncludingSuffix: "PKILL-OPTION-ORDER-OK",
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
};

const SHELL_SCRIPT_EXTENSION = /\.(?:sh|bash|zsh|ksh|dash|command)$/i;
const SHELL_SHEBANG = /^#!\s*\S*(?:\/|\s)(?:ba|z|k|da)?sh\b/;

function firstLineOf(text: string): string {
  const nl = text.indexOf("\n");
  return nl === -1 ? text : text.slice(0, nl);
}

/** True when the file being written is a shell script, by extension or by shebang. */
export function isShellScript(filePath: string, newText: string): boolean {
  if (SHELL_SCRIPT_EXTENSION.test(filePath)) return true;
  if (SHELL_SHEBANG.test(firstLineOf(newText))) return true;
  try {
    if (filePath && existsSync(filePath)) {
      return SHELL_SHEBANG.test(firstLineOf(readFileSync(filePath, "utf8").slice(0, 512)));
    }
  } catch {
    // Unreadable: judge by what we were given.
  }
  return false;
}

/** The text a Write / Edit would put into the file. */
export function textBeingWritten(toolName: string, toolInput: Record<string, unknown>): string {
  if (toolName === "Write") return typeof toolInput.content === "string" ? toolInput.content : "";
  if (toolName === "Edit") return typeof toolInput.new_string === "string" ? toolInput.new_string : "";
  return "";
}

const KIND_EXPLANATION: Record<BroadProcessSignalFinding["kind"], string> = {
  "every-process": "`-1` as a kill TARGET means every process you are allowed to signal.",
  "own-process-group":
    "`0` as a kill target means your whole process group; under an agent harness, pueue or launchd that is more than your command.",
  "shared-program-name":
    "that name is shared by many unrelated processes on an agent workstation (other Claude sessions, their MCP servers, dev servers, the terminal hosting them).",
  "user-wide": "no process name is given, so it reaches every process of that user.",
  "short-pattern": `a pattern with under ${MINIMUM_SPECIFIC_PATTERN_LITERAL_LENGTH} literal characters matches far more than the process you mean (with -f, anywhere in any argv).`,
};

export function explainBroadSignalFindings(
  findings: readonly BroadProcessSignalFinding[],
  where: string,
): string {
  const lines: string[] = [`[BROAD PROCESS SIGNAL GUARD] Blocked a signal that is broad by construction${where}.`];
  for (const f of findings) {
    const ctx = f.context === "command" ? "" : ` (inside a ${f.context})`;
    const target = f.target ? ` — "${f.target}"` : "";
    lines.push(`  ${f.invocationAsWritten}${ctx}${target}\n  Why: ${KIND_EXPLANATION[f.kind]}`);
  }
  lines.push(
    "Signal the exact PID you started instead:\n" +
      '  bun server.ts & pid=$!; …; kill "$pid"\n' +
      "or, when you did not start it, list first and then kill by PID:\n" +
      "  pgrep -fl '<full, specific command line>'   # read-only; then  kill <pid>",
    "Measured 2026-09-27: one pattern-aimed pkill SIGTERMed eight Claude Code sessions and every Electron " +
      "app's crash reporter on the operator's Mac, which then crash-looped until each app was relaunched.",
    "Spoke: plugins/itp-hooks/docs/broad-process-signal-guard.md\n" +
      "Override (almost never correct) with BROAD-PROCESS-SIGNAL-OK: <>=10-character reason>",
  );
  return lines.join("\n\n");
}

export async function main(): Promise<void> {
  const input = await parseStdinOrAllow("BROAD-PROCESS-SIGNAL-GUARD");
  if (!input) return;
  const { tool_name, tool_input = {} } = input;

  if (tool_name === "Bash") {
    const command = tool_input.command || "";
    if (hasFileWideEscapeHatchMarkerInContent(command, BROAD_SIGNAL_ESCAPE_HATCH)) return allow();
    const findings = findBroadProcessSignals(command);
    return findings.length === 0 ? allow() : deny(explainBroadSignalFindings(findings, ""));
  }

  if (tool_name !== "Write" && tool_name !== "Edit") return allow();
  const filePath = typeof tool_input.file_path === "string" ? tool_input.file_path : "";
  const text = textBeingWritten(tool_name, tool_input);
  if (!text || !isShellScript(filePath, text)) return allow();

  const reasons: string[] = [];
  if (!hasFileWideEscapeHatchMarkerInContent(text, BROAD_SIGNAL_ESCAPE_HATCH)) {
    const broad = findBroadProcessSignals(text);
    if (broad.length > 0) reasons.push(explainBroadSignalFindings(broad, ` in the script ${filePath}`));
  }
  if (!hasFileWideEscapeHatchMarkerInContent(text, PKILL_OPTION_ORDER_ESCAPE_HATCH)) {
    const order = findPkillOptionAfterPattern(text);
    if (order.length > 0) reasons.push(`In the script ${filePath}:\n\n${explainPkillOptionOrderFindings(order)}`);
  }
  return reasons.length === 0 ? allow() : deny(reasons.join("\n\n────────\n\n"));
}

if (import.meta.main) {
  main().catch((err) => {
    // Fail OPEN. A guard that blocks work when its own logic throws is worse than the bug it prevents.
    trackHookError(
      "pretooluse-broad-process-signal-guard",
      err instanceof Error ? err.message : String(err),
    );
    allow();
  });
}
