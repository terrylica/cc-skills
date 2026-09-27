#!/usr/bin/env bun

/**
 * PreToolUse hook: pkill / pgrep option-after-pattern guard.
 *
 * Denies a Bash command in which `pkill` or `pgrep` has an option-looking argument AFTER its first
 * pattern, e.g. `pkill -f 'bun server.ts' -n`. On macOS these tools parse options with BSD getopt,
 * which stops at the first non-option argument, so the trailing `-n` is a SECOND PATTERN and the
 * command signals every process whose command line contains "-n". Linux procps permutes arguments,
 * so the line reads as correct to anyone who learned it there.
 *
 * WHY A HARD BLOCK. Measured 2026-09-27 on the operator's Mac: one such cleanup line, run by an
 * agent after a Playwright scenario, SIGTERMed eight Claude Code sessions, the crash reporter of
 * every Electron app (Code, Orca, Synergy, Typeless, Discord, Time Doctor), an agent Chrome and
 * Orca's terminals. macOS 15.8.1 then refused each app's respawned crash reporter
 * (`mach_port_request_notification: (os/kern) invalid capability`), so the apps crash-looped the
 * reporter through "<App> quit unexpectedly" dialogs and ~4 failed spawns a second until relaunched.
 * The corrected form costs nothing and is right on both platforms, so there is no false positive
 * worth tolerating a silent fleet-wide kill for.
 *
 * Detection lives in lib/pkill-option-after-pattern-detector.ts (pure, statically lexes the
 * command, never executes it). Spoke: docs/pkill-option-after-pattern-guard.md.
 */

import {
  type EscapeHatchMarkerDetectionConfiguration,
  hasFileWideEscapeHatchMarkerInContent,
} from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import {
  findPkillOptionAfterPattern,
  type OptionAfterPatternFinding,
} from "./lib/pkill-option-after-pattern-detector.ts";
import {
  allow,
  deny,
  parseStdinOrAllow,
  trackHookError,
} from "./pretooluse-helpers.ts";

/** Operator escape hatch. A >=10-character justification is mandatory. */
const PKILL_OPTION_ORDER_ESCAPE_HATCH: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  | "markerNameTokenIncludingSuffix"
  | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
> = {
  markerNameTokenIncludingSuffix: "PKILL-OPTION-ORDER-OK",
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 10,
};

export function explainPkillOptionOrderFindings(
  findings: readonly OptionAfterPatternFinding[],
): string {
  const lines: string[] = [
    "[PKILL OPTION ORDER GUARD] Blocked: an option comes AFTER the pattern.",
  ];

  for (const f of findings) {
    const stray = f.optionLikeArgumentsAfterPattern.map((s) => `"${s}"`).join(", ");
    const where = f.context === "command" ? "" : ` (inside a ${f.context})`;
    lines.push(
      `\n  ${f.invocationAsWritten}${where}\n\n` +
        `On macOS, ${f.program} reads options with BSD getopt, which stops at the first non-option ` +
        `argument. So ${stray} ${f.optionLikeArgumentsAfterPattern.length === 1 ? "is" : "are"} not ` +
        `${f.optionLikeArgumentsAfterPattern.length === 1 ? "an option" : "options"} here but extra ` +
        `PATTERNS, and ${f.program} ${f.program === "pkill" ? "signals" : "reports"} EVERY process whose ` +
        "command line contains them (with -f that is the whole argv: --no-sandbox, --no-rate-limit, " +
        "--no-chrome, --num-raster-threads, …).\n\n" +
        `Put every option before the first pattern:\n\n  ${f.correctedInvocation}`,
    );
  }

  lines.push(
    "Better still, signal the exact PID you started instead of pattern-matching the whole machine:\n" +
      '  bun server.ts & pid=$!; …; kill "$pid"\n' +
      "A pattern that genuinely begins with '-' goes after --:  pkill -f -- '-n'",
    "Measured 2026-09-27: `pkill -f 'bun server.ts --build build-preview' -n` SIGTERMed eight Claude " +
      "Code sessions and every Electron app's crash reporter on this Mac; the apps then crash-looped " +
      "their reporters through 'quit unexpectedly' dialogs until relaunched. Linux procps permutes " +
      "arguments, so the original happens to work there; the corrected form is right on both.",
    "Spoke: plugins/itp-hooks/docs/pkill-option-after-pattern-guard.md\n" +
      "Override (almost never correct) with PKILL-OPTION-ORDER-OK: <>=10-character reason>",
  );

  return lines.join("\n\n");
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("PKILL-OPTION-ORDER-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";
  if (
    hasFileWideEscapeHatchMarkerInContent(
      command,
      PKILL_OPTION_ORDER_ESCAPE_HATCH,
    )
  ) {
    allow();
    return;
  }

  const findings = findPkillOptionAfterPattern(command);
  if (findings.length === 0) {
    allow();
    return;
  }

  deny(explainPkillOptionOrderFindings(findings));
}

if (import.meta.main) {
  main().catch((err) => {
    // Fail OPEN. A guard that blocks work when its own logic throws is worse than the bug it prevents.
    trackHookError(
      "pretooluse-pkill-option-after-pattern-guard",
      err instanceof Error ? err.message : String(err),
    );
    allow();
  });
}
