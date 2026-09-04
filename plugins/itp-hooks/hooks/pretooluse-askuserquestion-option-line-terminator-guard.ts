#!/usr/bin/env bun
/**
 * PreToolUse hook: AskUserQuestion option line-terminator guard.
 *
 * Denies an AskUserQuestion call whose option `description` or `label` contains a line
 * terminator (LF, CR, U+2028, U+2029), because Claude Code replaces each one with U+FFFD
 * before rendering — a multi-paragraph description reaches the user as
 * `...forever.<FFFD><FFFD>II. SHORT-TERM WIN:`. Upstream regression
 * https://github.com/anthropics/claude-code/issues/88836 (introduced 2.1.235, still open;
 * re-measured present in 2.1.260). The detector's docstring carries the byte-level
 * evidence and the explicit CONDITION FOR DELETING THIS GUARD.
 *
 * Only `label` and `description` are inspected. `question` and `preview` take
 * newline-preserving paths, so flagging them would be a false positive.
 *
 * DENY, never repair. `hooks/lib/tool-schemas.ts` deliberately registers no schema for
 * AskUserQuestion (its StrictSchema supports neither nested objects nor arrays of
 * objects), and a tool absent from that registry cannot receive `updatedInput` — the safe
 * default that keeps a hook from corrupting a tool payload it does not fully model. So
 * this guard tells the model exactly what to change and hands the call back; it must NOT
 * be "improved" into an auto-fixer by widening that registry.
 *
 * Escape hatch: ASK-OPTION-NEWLINE-OK anywhere in the tool input (the `question` text is
 * the natural place), read through the iter-107 canonical marker helper. The token is
 * named HERE and in the spoke, and deliberately NOT in the deny message — the marker is
 * matched across the whole serialized input, so a message that spelled it would let the
 * model's own retry echo the guard into silence. See the detector for the full rationale.
 *
 * PreToolUse dispatch to AskUserQuestion is confirmed empirically (probe hook with a Bash
 * control logged `PreToolUse AskUserQuestion`); this guard is not a no-op. See the spoke.
 *
 * Fail-open everywhere: unparseable stdin, an unexpected payload shape, or any thrown
 * error → allow. A guard that crashes must never block the user's own question UI.
 */

import { allow, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import { truncateHookOutputToStayBelowClaudeFileSpilloverThreshold } from "./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts";
import {
  buildLineTerminatorDenyMessage,
  detectOptionLineTerminators,
  ESCAPE_HATCH_MARKER_TOKEN,
} from "./lib/askuserquestion-option-line-terminator-detector.ts";

const HOOK_NAME = "askuserquestion-option-line-terminator-guard";

/**
 * The marker is searched in the SERIALIZED tool input rather than in one named field:
 * AskUserQuestion has no command string, and the model may reasonably place the marker in
 * the question text, an option label, or a header. Serialization failure is treated as
 * "no marker" and falls through to the (fail-open) detection path.
 */
function hasEscapeHatchMarker(toolInput: unknown): boolean {
  let serialized: string;
  try {
    serialized = JSON.stringify(toolInput) ?? "";
  } catch {
    return false;
  }
  return hasFileWideEscapeHatchMarkerInContent(serialized, {
    markerNameTokenIncludingSuffix: ESCAPE_HATCH_MARKER_TOKEN,
  });
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("ASKUSERQUESTION-OPTION-NEWLINE-GUARD");
  if (!input) return;

  const { tool_name, tool_input } = input;
  if (tool_name !== "AskUserQuestion") {
    allow();
    return;
  }

  if (hasEscapeHatchMarker(tool_input)) {
    allow();
    return;
  }

  const findings = detectOptionLineTerminators(tool_input);
  if (findings.length > 0) {
    deny(
      truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
        buildLineTerminatorDenyMessage(findings),
      ),
    );
    return;
  }

  allow();
}

main().catch((err) => {
  trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
  allow();
});
