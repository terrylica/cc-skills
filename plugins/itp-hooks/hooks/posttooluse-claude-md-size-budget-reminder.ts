#!/usr/bin/env bun
/**
 * PostToolUse subhook: CLAUDE.md size-budget reminder — nudge a refactor
 * BEFORE a CLAUDE.md crosses Claude Code's hard 40,000-character context
 * limit.
 *
 * ─── Why this exists ──────────────────────────────────────────────────────
 *
 * Claude Code refuses to fully load a CLAUDE.md once it exceeds ~40k chars
 * ("⚠ CLAUDE.md is over the 40.0k-char limit · /memory to free up context").
 * When that happens the file's instructions stop being reliably honored —
 * the worst possible failure mode for a behavioural-contract file. The
 * canonical fix in this user's docs system is the hub-and-spoke / link-farm
 * pattern (root is a one-line-per-spoke index; detail lives in nested
 * `<topic>-CLAUDE.md` spokes or sub-hubs). This subhook fires the reminder
 * while there is still headroom to act, instead of after the limit is hit.
 *
 * ─── Behaviour ────────────────────────────────────────────────────────────
 *
 * Trigger:   After Write / Edit / MultiEdit on a file whose basename is
 *            exactly `CLAUDE.md`. (Spokes like `principles-CLAUDE.md` are
 *            intentionally NOT matched — they are on-demand Reads, not
 *            auto-loaded, so the 40k auto-load limit does not apply to them.)
 * Measure:   CHARACTER count of the file as written — `content.length`
 *            (UTF-16 code units, which is exactly how Claude Code's own
 *            JS/TS runtime measures string length). This is exact for the
 *            Basic Multilingual Plane (including CJK, where one char = one
 *            UTF-16 unit) and counts astral-plane chars (emoji) as 2 — a
 *            conservative match for a budget guard.
 *
 *            NOTE (2026-06-07): this hook previously measured BYTES via
 *            statSync().size. That false-alarmed on non-ASCII CLAUDE.md
 *            files — e.g. a Chinese (CJK = 3 UTF-8 bytes/char) file of
 *            28k chars is 42k bytes and was wrongly reported as "OVER the
 *            40k limit / not loading" when it actually loads fine. Counting
 *            characters fixes that. The limit is character-based (the UI
 *            says "40.0k-char limit"); if a future Claude Code release
 *            changes to a byte/token basis, revisit this measurement.
 * Fire when: chars >= WARN_THRESHOLD (90% of the 40k limit). A healthy hub
 *            edit produces a `noop` (silent) so this never nags on normal
 *            work.
 * Escape:    A `CLAUDE-MD-SIZE-OK` marker anywhere in the file silences the
 *            nudge — for an intentionally-flat CLAUDE.md (e.g. a generated
 *            file or an append-only findings log). In markdown add it as an
 *            HTML comment: `<!-- CLAUDE-MD-SIZE-OK -->`. (Marker matched as a
 *            bare substring, mirroring the sibling `FILE-SIZE-OK` convention.
 *            Documented here in the .ts — NOT in any CLAUDE.md — so this
 *            hook's own docs can never accidentally self-silence a CLAUDE.md.)
 * Output:    A PostToolUse `additional_context` decision (the orchestrator
 *            folds it into the aggregated `{decision:"block", reason}` — the
 *            documented Anthropic context-injection mechanism; "block" does
 *            NOT undo the completed edit, it surfaces the reminder to Claude
 *            for the next turn).
 *
 * Non-blocking, fail-open: any error (unreadable file, bad stdin) resolves to
 * a `noop` so a subhook fault can never wedge an edit.
 *
 * ─── Architecture ─────────────────────────────────────────────────────────
 *
 * Dual-mode (mirrors posttooluse-vale-claude-md.ts):
 *   - `classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator`
 *     (alias `classifyClaudeMdSizeBudgetForPostToolUseOrchestrator`) is the
 *     pure classifier imported by the iter-93 PostToolUse orchestrator (8th
 *     inlined subhook) — amortizes the bun cold-start across the registry
 *     instead of paying a separate ~10-15ms bun process on every Write/Edit.
 *   - The `import.meta.main` block keeps it runnable as a standalone CLI.
 *
 * ─── Thresholds ───────────────────────────────────────────────────────────
 *
 *   HARD_LIMIT  = 40000  — Claude Code's own cutoff (characters).
 *   WARN_THRESHOLD = 36000 (90%) — the nudge point. Below this: noop.
 */

import { basename, isAbsolute, join } from "node:path";
import { existsSync, readFileSync } from "node:fs";
import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
  isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import { truncateHookOutputToStayBelowClaudeFileSpilloverThreshold } from "./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts";

// ============================================================================
// CONSTANTS
// ============================================================================

/** Claude Code's hard CLAUDE.md context-load limit, in characters. */
const CLAUDE_MD_HARD_LIMIT_CHARS = 40_000;

/** Nudge point: 90% of the hard limit. Below this the subhook is silent. */
const CLAUDE_MD_WARN_THRESHOLD_CHARS = 36_000;

/** Bare-substring escape hatch (mirrors the `FILE-SIZE-OK` sibling convention). */
const CLAUDE_MD_SIZE_ESCAPE_HATCH_MARKER = "CLAUDE-MD-SIZE-OK";

// ============================================================================
// HELPERS
// ============================================================================

/**
 * Resolve the edited file's absolute path. Claude Code normally passes an
 * absolute `file_path`, but if a relative path arrives, resolve it against
 * the hook's `cwd` (provided in the PostToolUse payload) so a relative path
 * is never a silent miss.
 */
function resolveEditedFileAbsolutePath(input: PostToolUseInput): string {
  const raw = input.tool_input?.file_path || "";
  if (!raw) return "";
  if (isAbsolute(raw)) return raw;
  const base = input.cwd || process.cwd();
  return join(base, raw);
}

/**
 * Build the refactor reminder. Two bands: OVER (already past the hard limit —
 * the file is NOT fully loading) vs APPROACHING (still loads, but plan the
 * split now). Both point at the hub-and-spoke / link-farm remedy.
 */
function buildReminderReason(filePath: string, sizeChars: number): string {
  const isOver = sizeChars >= CLAUDE_MD_HARD_LIMIT_CHARS;
  const pct = Math.round((sizeChars / CLAUDE_MD_HARD_LIMIT_CHARS) * 100);
  const headline = isOver
    ? `[CLAUDE.md SIZE] ⛔ ${basename(filePath)} is ${sizeChars.toLocaleString()} chars — OVER the ${CLAUDE_MD_HARD_LIMIT_CHARS.toLocaleString()}-char limit (${pct}%). Claude Code will NOT fully load it, so its instructions are no longer reliably honored.`
    : `[CLAUDE.md SIZE] ⚠ ${basename(filePath)} is ${sizeChars.toLocaleString()} chars — ${pct}% of the ${CLAUDE_MD_HARD_LIMIT_CHARS.toLocaleString()}-char limit. Plan a refactor now, before it crosses the limit and stops loading.`;

  return `${headline}

Refactor toward the hub-and-spoke / link-farm pattern (this docs system's SSoT discipline):
  1. The hub keeps ONE line per spoke — a path + a single clause, not a paragraph. Move prose descriptions into the spoke each row points at.
  2. Collapse clusters of related spokes into a sub-hub: replace N rows with one row pointing at a directory's own CLAUDE.md, whose own index lists the children.
  3. Move time-series narrative (dated decisions, "iter-N did X", migration notes) OUT of the hub into chronicles / the owning spoke — keep the lesson, drop the trace.
  4. Re-measure characters (the limit is character-based, not byte-based): target < 38,000 chars. If this file is intentionally flat (generated / append-only log), add a \`CLAUDE-MD-SIZE-OK\` marker to silence this.

${isOver ? "This is the high-priority failure mode — fix it before relying on anything in this file." : "Cheap to fix now; expensive to notice after it silently stops loading."}`;
}

// ============================================================================
// PURE CLASSIFIER (orchestrator-imported)
// ============================================================================

/**
 * Returns an `additional_context` decision when the edited file is a
 * CLAUDE.md at or above the warn threshold, or `noop` otherwise. Pure except
 * for a single read of the just-written file. Catches its own errors and
 * fails open to `noop` per the PostToolUse subhook contract.
 */
export async function classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const toolName = input.tool_name || "";
    if (!isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(toolName)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const filePath = resolveEditedFileAbsolutePath(input);
    // Strict basename match: only auto-loaded `CLAUDE.md`, not `*-CLAUDE.md`
    // spokes (those are on-demand Reads, exempt from the auto-load limit).
    if (basename(filePath) !== "CLAUDE.md") return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    if (!existsSync(filePath)) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    let content: string;
    try {
      content = readFileSync(filePath, "utf8");
    } catch {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION; // unreadable — fail-open
    }

    // Escape hatch — intentionally-flat CLAUDE.md opts out.
    if (content.includes(CLAUDE_MD_SIZE_ESCAPE_HATCH_MARKER)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Character count (UTF-16 code units = Claude Code's own string-length
    // measure), NOT byte count — see header note on the CJK false-alarm.
    const sizeChars = content.length;
    if (sizeChars < CLAUDE_MD_WARN_THRESHOLD_CHARS) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Wrap in the canonical truncation helper (marketplace invariant: every
    // classifier reason must be guarded against Claude's hook-output
    // file-spillover threshold).
    const reason = truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
      buildReminderReason(filePath, sizeChars),
    );
    return buildPostToolUseAdditionalContextDecision(reason);
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

/** Symmetric-naming alias for the orchestrator registry. */
export const classifyClaudeMdSizeBudgetForPostToolUseOrchestrator =
  classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator;

// ============================================================================
// STANDALONE CLI ENTRY POINT
// ============================================================================

async function runStandaloneCliMain(): Promise<void> {
  const inputText = await Bun.stdin.text();
  if (!inputText.trim()) {
    process.exit(0);
  }

  let input: PostToolUseInput;
  try {
    input = JSON.parse(inputText) as PostToolUseInput;
  } catch {
    process.exit(0);
  }

  const decision =
    await classifyClaudeMdCharacterCountBudgetForPostToolUseOrchestrator(input);
  if (decision.kind === "additional_context") {
    console.log(JSON.stringify({ decision: "block", reason: decision.message }));
  }
  process.exit(0);
}

if (import.meta.main) {
  runStandaloneCliMain().catch(() => process.exit(0));
}
