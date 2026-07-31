#!/usr/bin/env bun
/**
 * PreToolUse hook: headless `claude -p` guard.
 *
 * Blocks ONLY invocations that provably cannot do what their author is asking for. It does not lecture
 * about style, and it does not fire on a bare `claude -p` with no `--effort` — that runs at the
 * documented default (`high`) and is frequently correct.
 *
 * WHY THIS EXISTS. On 2026-07-31 a day was spent establishing how `-p` really behaves, and the
 * expensive part was not the answer — it was three separate false conclusions drawn from probes that
 * could not observe what they claimed:
 *   - `--output-format stream-json` silently produced ZERO output (missing `--verbose`, error on
 *     stderr) and was almost written up as "extended thinking is unavailable on this path".
 *   - `CLAUDE_EFFORT=xhigh` was assumed to be setting reasoning depth. It is not an input at all.
 *   - An `--effort` typo would have been accepted with exit 0 and silently ignored.
 * Each is now a hard block, because each produces a CONFIDENT WRONG ANSWER rather than an error.
 *
 * Knowledge SSoT (this file duplicates none of it):
 *   plugins/itp-hooks/docs/headless-claude-p.md
 */

import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { explainViolations, findHeadlessViolations } from "./headless-claude-p-patterns.ts";
import {
  hasFileWideEscapeHatchMarkerInContent,
  type EscapeHatchMarkerDetectionConfiguration,
} from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

const HEADLESS_P_ESCAPE_HATCH: Pick<
  EscapeHatchMarkerDetectionConfiguration,
  "markerNameTokenIncludingSuffix" | "caseSensitivityMode"
> = {
  markerNameTokenIncludingSuffix: "HEADLESS-P-OK",
  caseSensitivityMode: "CASE_INSENSITIVE",
};

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("HEADLESS-CLAUDE-P-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";
  if (hasFileWideEscapeHatchMarkerInContent(command, HEADLESS_P_ESCAPE_HATCH)) {
    allow();
    return;
  }

  const violations = findHeadlessViolations(command);
  if (violations.length === 0) {
    allow();
    return;
  }

  deny(explainViolations(violations));
}

main().catch((err) => {
  // Fail OPEN. A guard that blocks work when its own logic throws is worse than the bug it prevents.
  trackHookError(
    "pretooluse-headless-claude-p-guard",
    err instanceof Error ? err.message : String(err),
  );
  allow();
});
