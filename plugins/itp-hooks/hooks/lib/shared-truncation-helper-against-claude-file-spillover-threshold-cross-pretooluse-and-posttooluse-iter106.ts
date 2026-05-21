/**
 * Shared truncation helper against Claude's hook-output file-spillover threshold
 * (iter-106 helper-extraction follow-up to iter-105 marketplace-wide invariant).
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why this file exists (iter-106 design rationale)
 * ════════════════════════════════════════════════════════════════════════
 *
 * Iter-104 introduced `truncateHookOutputToStayBelowClaudeFileSpilloverThreshold`
 * inside the PostToolUse contract lib because the FIRST adopter was a
 * PostToolUse classifier (posttooluse-vale-claude-md.ts). Iter-105 scaled the
 * helper marketplace-wide to 8 cohort hooks — but ONE of those hooks
 * (pretooluse-vale-claude-md-guard.ts) is a PreToolUse classifier, creating a
 * PRAGMATIC-BUT-AWKWARD cross-lib import pattern:
 *
 *     pretooluse-vale-claude-md-guard.ts
 *       imports truncateHookOutputToStayBelowClaudeFileSpilloverThreshold
 *       FROM ./lib/posttooluse-subhook-contract-...iter93.ts
 *
 * The helper is PURE STRING TRUNCATION — it has no PostToolUse-specific
 * semantics; it's about the Claude-visible 10,000-character hook-output cap
 * documented in 2026 Anthropic Claude Code hook docs:
 *
 *     "Hook output strings, including additionalContext, systemMessage, and
 *      plain stdout, are capped at 10,000 characters. Output that exceeds
 *      this limit is saved to a file and replaced with a preview and file
 *      path, the same way large tool results are handled."
 *
 *     Source: https://code.claude.com/docs/en/hooks
 *
 * The cap applies SYMMETRICALLY to PreToolUse deny-reasons, PostToolUse
 * additionalContext / decision-reasons, Stop hook reasons, SessionStart
 * additionalContext, etc. — every hook-output surface where Claude reads a
 * string. Hosting the helper inside the PostToolUse contract lib was an
 * iter-104 expediency, NOT a semantic correctness statement.
 *
 * Iter-106 (this file) makes the helper's canonical home a dedicated shared-
 * lib file that BOTH PreToolUse + PostToolUse contract libs can re-export
 * from, and that direct consumers (the 8 iter-105 cohort hooks) can import
 * from without the cross-lib awkwardness. The previous PostToolUse-contract
 * exports are PRESERVED as transitive re-exports to keep the iter-104 helper
 * API stable for any external consumers (audit tasks, regression tests,
 * documentation references).
 *
 * ════════════════════════════════════════════════════════════════════════
 *  What's in here vs. what's NOT in here
 * ════════════════════════════════════════════════════════════════════════
 *
 * IN: the 3 exports related to the 10K file-spillover threshold defense —
 *     - MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER (constant)
 *     - HOOK_OUTPUT_TRUNCATION_MARKER_SUFFIX_FOR_CLAUDE_VISIBLE_AWARENESS_OF_CONTEXT_LOSS (constant)
 *     - truncateHookOutputToStayBelowClaudeFileSpilloverThreshold (function)
 *
 * NOT IN: PreToolUse/PostToolUse contract types, subhook decision builders,
 *     orchestrator-specific helpers, async-spawn helpers, gate-file helpers,
 *     etc. — those remain in their respective contract libs because they
 *     CARRY pre/post-specific semantics. This shared lib only hosts helpers
 *     that are PURELY about the Claude-visible hook-output surface (a
 *     cross-cutting concern that doesn't belong to either Pre or Post path).
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Migration path for future similar helpers
 * ════════════════════════════════════════════════════════════════════════
 *
 * When the next cross-Pre/PostToolUse helper appears (e.g., a shared
 * deny-reason actionability formatter, a shared escape-hatch comment
 * detector, etc.), it should land here directly — not in either contract
 * lib. The iter-106 establishment of this file as the canonical shared-
 * helper home avoids future cross-lib import churn.
 */

// ────────────────────────────────────────────────────────────────────────
//  Hook-output size cap (Claude-visible 10,000-character file-spillover
//  threshold per 2026 Anthropic schema docs)
// ────────────────────────────────────────────────────────────────────────
//
// The silent-degradation hazard: when a hook emits output >10K chars,
// Claude only sees the preview, NOT the full content. The classifier may
// believe it gave Claude actionable context but Claude actually sees a
// truncated stub with a file path it cannot read (the file is on the
// operator's machine; Claude's sandbox cannot follow). Net effect: the
// subhook's diagnostic intelligence is LOST.
//
// Marketplace cohort hooks (iter-104+iter-105) adopting the helper:
//   - posttooluse-vale-claude-md.ts          (iter-104 baseline)
//   - posttooluse-ty-type-check.ts           (iter-105 scope)
//   - posttooluse-tsgo-type-check.ts         (iter-105 scope)
//   - posttooluse-oxlint-check.ts            (iter-105 scope)
//   - posttooluse-biome-lint.ts              (iter-105 scope)
//   - posttooluse-ssot-principles.ts         (iter-105 scope)
//   - pretooluse-vale-claude-md-guard.ts     (iter-105 cross-lib — fixed iter-106)
//   - posttooluse-orchestrator (aggregation) (iter-105 sum-overflow defense)
//
// Naming: `MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER`
// encodes the SEMANTIC INVARIANT (Claude-visible threshold, beyond which
// output gets silent-spilled to a file Claude can't follow). The 9000
// value provides a 1000-char safety margin below the documented 10000
// threshold (room for the truncation-marker suffix without overflow).

export const MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER = 9000;

export const HOOK_OUTPUT_TRUNCATION_MARKER_SUFFIX_FOR_CLAUDE_VISIBLE_AWARENESS_OF_CONTEXT_LOSS =
  "\n\n[... output truncated to stay below Claude's 10,000-character hook-output file-spillover threshold; full diagnostic content remains available in the operator transcript via Ctrl-R. Claude: act on the visible findings above; assume there may be additional unseen issues of the same kind ...]";

/**
 * Iter-104 canonical truncation helper for hook outputs that risk exceeding
 * Claude's 10,000-character file-spillover threshold. Iter-106 relocates the
 * canonical home from the PostToolUse contract lib to this dedicated shared
 * lib (the helper is symmetric across PreToolUse + PostToolUse paths; the
 * iter-104 PostToolUse-contract-lib location was iter-105-era expediency).
 *
 * Per 2026 Anthropic Claude Code hook docs, any hook output (additionalContext,
 * systemMessage, deny-reason, decision-reason, plain stdout) >10K chars gets
 * SILENTLY replaced with a preview + filesystem-path reference. Claude only
 * sees the preview; the full content is written to a file the Claude sandbox
 * cannot access. The hook author's intended diagnostic intelligence is LOST.
 *
 * This helper guards against that silent context-degradation by:
 *   - Returning the input verbatim if already under the safe threshold
 *   - Otherwise: truncating to (safe_threshold - marker_length) chars + appending
 *     the marker so Claude EXPLICITLY KNOWS truncation occurred AND that there
 *     may be additional findings beyond what's visible (preserves classifier's
 *     diagnostic credibility instead of silently lying about completeness)
 *
 * Use at every hook emission site where the output could grow with input size
 * (lint findings, type errors, vale warnings, AST-pattern matches, etc.).
 *
 * Iter-106 stability invariant: this function's signature + behavior MUST
 * remain backward-compatible with the iter-104 baseline. Audit task
 * `.mise/tasks/audit-pretooluse-and-posttooluse-hook-classifiers-for-unbounded-reason-emission-not-wrapped-in-canonical-truncation-helper-against-claude-file-spillover-threshold-iter105-marketplace-scale-of-iter104-single-hook-fix.sh`
 * verifies marketplace-wide consumption; iter-106 regression test verifies the
 * shared-lib relocation + transitive re-export contract preservation.
 */
export function truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
  rawOutput: string,
): string {
  if (rawOutput.length <= MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER) {
    return rawOutput;
  }
  const markerLength =
    HOOK_OUTPUT_TRUNCATION_MARKER_SUFFIX_FOR_CLAUDE_VISIBLE_AWARENESS_OF_CONTEXT_LOSS.length;
  const truncationBudgetForContent =
    MAX_HOOK_OUTPUT_SAFE_LENGTH_BEFORE_CLAUDE_FILE_SPILLOVER - markerLength;
  return (
    rawOutput.slice(0, truncationBudgetForContent) +
    HOOK_OUTPUT_TRUNCATION_MARKER_SUFFIX_FOR_CLAUDE_VISIBLE_AWARENESS_OF_CONTEXT_LOSS
  );
}
