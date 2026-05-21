#!/usr/bin/env bun
/**
 * PostToolUse hook: Memory Efficiency Reminder
 *
 * Fires ONCE PER SESSION after the first Write/Edit of a code file to
 * remind Claude about zero-copy, pre-allocation, cache-locality, and
 * lazy-evaluation patterns. Prevents the common anti-pattern of building
 * Python lists then converting to Arrow/Polars, or making unnecessary
 * copies in hot paths.
 *
 * ─── Iter-98 architectural change ─────────────────────────────────────────
 *
 * Iter-98 inlines this hook as the SEVENTH PostToolUse orchestrator subhook
 * (7/15 in the iter-93+ migration arc). Two improvements landed in the
 * same iteration:
 *
 *   1. LONG-STANDING SILENT CONTEXT-DROP BUG FIXED. The pre-iter-98
 *      standalone hook emitted the reminder via plain `console.log(...)`
 *      (raw text, NOT `{decision: "block", reason: ...}` JSON). Per the
 *      iter-66/93 forensic finding + Anthropic PostToolUse schema docs,
 *      plain-text stdout from PostToolUse hooks is transcript-visible-only
 *      (Ctrl-R operator transcript) and is NEVER delivered to Claude's
 *      next-turn context. The reminder was therefore effectively invisible
 *      to Claude — a silent context-drop. The iter-92 async-eligibility
 *      audit had classified this hook as `[M] MIXED` (couldn't statically
 *      determine output shape) — meaning the bug existed in plain sight
 *      but wasn't caught by structural pattern-matching.
 *
 *      Iter-98 fix: classifier returns a proper `additional_context`
 *      decision; the orchestrator wraps it in `{decision: "block", reason:
 *      aggregate}` JSON which IS Claude-visible. The standalone-CLI
 *      `import.meta.main` path now ALSO emits proper JSON (not raw text),
 *      so direct-CLI invocation produces the same Claude-visible behavior.
 *
 *   2. ITER-95 SHARED-LIB CONSUMPTION. The pre-iter-98 hook had its own
 *      verbose gate-file logic (mkdirSync + writeFileSync — note this
 *      wasn't even atomic-O_EXCL like ssot-principles or the iter-95
 *      install-reminder helper; two near-simultaneous Write|Edit calls
 *      could both pass the gate and double-fire the reminder). Iter-98
 *      migrates to the new iter-98 shared
 *      `tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName`
 *      helper which uses O_CREAT|O_EXCL for race-safety.
 *
 * Why this hook is well-suited to the orchestrator path:
 *   - Once-per-session work → most invocations are sub-ms gate-claim noop
 *   - No subprocess spawn (purely static reminder text) → no timeout risk
 *   - Overlaps with ALL existing inlined classifiers via extension union
 *     (.py with ty + ssot; .ts with tsgo+oxlint+biome+ssot; .rs/.go/.java/
 *     .kt/.rb with ssot) — the orchestrator's Promise.all wins
 *
 * Gate: fires once per session via atomic O_EXCL gate-file (shared helper).
 * Scope: .py, .rs, .ts, .tsx, .js, .go, .java, .kt, .rb, .cpp, .c, .h, .zig
 * Skips: test files (pattern-matched).
 */

import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
  isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import { tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName } from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts";

// ══════════════════════════════════════════════════════════════════════════
//  Constants
// ══════════════════════════════════════════════════════════════════════════

const MEMORY_EFFICIENCY_REMINDER_NAME_FOR_ONCE_PER_SESSION_GATE_FILE_NAMESPACE = "memory-efficiency";

const CODE_FILE_EXTENSIONS_ELIGIBLE_FOR_MEMORY_EFFICIENCY_REMINDER = new Set([
  ".py",
  ".rs",
  ".ts",
  ".tsx",
  ".js",
  ".go",
  ".java",
  ".kt",
  ".rb",
  ".cpp",
  ".c",
  ".h",
  ".zig",
]);

const TEST_FILE_PATH_PATTERN_EXCLUDED_FROM_MEMORY_EFFICIENCY_REMINDER =
  /(?:^|\/)(?:test_|tests\/|__tests__\/|_test\.|_spec\.|\.test\.|\.spec\.)/;

// ══════════════════════════════════════════════════════════════════════════
//  Reminder message (preserved verbatim from pre-iter-98 standalone hook)
// ══════════════════════════════════════════════════════════════════════════

const MEMORY_EFFICIENCY_BEST_PRACTICES_STATIC_REMINDER_MESSAGE = `[MEMORY-EFFICIENCY] When writing data-path code, prefer these patterns:

┌──────────────────┬─────────────────────────────────────┐
│ AVOID COPIES     │ zero-copy, view, slice, borrow,     │
│                  │ pass-by-reference, move semantics   │
├──────────────────┼─────────────────────────────────────┤
│ AVOID ALLOCATION │ pre-allocate, buffer reuse, arena,  │
│                  │ stack allocation, object pool       │
├──────────────────┼─────────────────────────────────────┤
│ CACHE EFFICIENCY │ contiguous, data locality, SoA,     │
│                  │ cache-friendly, cache-oblivious     │
├──────────────────┼─────────────────────────────────────┤
│ LAZY EVALUATION  │ streaming, iterator, generator,     │
│                  │ predicate pushdown, lazy frame      │
└──────────────────┴─────────────────────────────────────┘

Anti-patterns: Python list → Arrow (copy!), df.to_dict() in loops, .values() materializing lazy frames, repeated pd.concat instead of pre-sized buffer.`;

// ══════════════════════════════════════════════════════════════════════════
//  Helpers
// ══════════════════════════════════════════════════════════════════════════

function getFileExtensionIncludingLeadingDot(filePath: string): string {
  const lastDotIndex = filePath.lastIndexOf(".");
  return lastDotIndex >= 0 ? filePath.slice(lastDotIndex) : "";
}

function isCodeFileExtensionEligibleForMemoryEfficiencyReminder(filePath: string): boolean {
  return CODE_FILE_EXTENSIONS_ELIGIBLE_FOR_MEMORY_EFFICIENCY_REMINDER.has(
    getFileExtensionIncludingLeadingDot(filePath),
  );
}

function isTestFilePathExcludedFromMemoryEfficiencyReminder(filePath: string): boolean {
  return TEST_FILE_PATH_PATTERN_EXCLUDED_FROM_MEMORY_EFFICIENCY_REMINDER.test(filePath);
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Classify a PostToolUse Write|Edit event for memory-efficiency-reminder
 * relevance.
 *
 *   - Returns `additional_context` ONCE PER SESSION on the first eligible
 *     code-file edit (gated atomically via shared O_EXCL helper).
 *   - All subsequent edits in the same session return `noop` (gate already
 *     claimed). The orchestrator's Promise.all parallelism is unaffected —
 *     the gate check + early-return is a sub-millisecond mkdirSync +
 *     openSync(... O_EXCL) round-trip.
 *   - Skips test files (test fixtures legitimately use memory-inefficient
 *     patterns for clarity).
 *
 * Iter-98 invariant: the returned `additional_context.message` is the
 * EXACT pre-iter-98 console.log text — semantic continuity preserved
 * (Claude sees the same reminder string it would have seen if the
 * pre-iter-98 console.log path actually worked, which it didn't because
 * Claude Code's PostToolUse schema silently drops non-JSON stdout).
 */
export async function classifyMemoryEfficiencyBestPracticesReminderOncePerSessionForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    // Iter-100: honor Write|Edit|MultiEdit via canonical contract helper
    // (replaces local Write||Edit equality; centralizes the allow-set so
    // future Anthropic tool additions update ONE constant, not N classifiers).
    if (!isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(input.tool_name)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const filePath = input.tool_input?.file_path;
    if (!filePath) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    if (!isCodeFileExtensionEligibleForMemoryEfficiencyReminder(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (isTestFilePathExcludedFromMemoryEfficiencyReminder(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const sessionId =
      input.session_id || process.env.CLAUDE_SESSION_ID || String(process.ppid);
    if (
      !tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName(
        MEMORY_EFFICIENCY_REMINDER_NAME_FOR_ONCE_PER_SESSION_GATE_FILE_NAMESPACE,
        sessionId,
      )
    ) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    return buildPostToolUseAdditionalContextDecision(
      MEMORY_EFFICIENCY_BEST_PRACTICES_STATIC_REMINDER_MESSAGE,
    );
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

/**
 * Symmetric-naming alias matching the sibling subhooks (ty, tsgo, oxlint,
 * biome, vale, ssot-principles). The precise algorithm-encoding name above
 * captures the once-per-session-static-reminder nature; this alias is what
 * the orchestrator imports.
 */
export const classifyMemoryEfficiencyReminderForPostToolUseOrchestrator =
  classifyMemoryEfficiencyBestPracticesReminderOncePerSessionForPostToolUseOrchestrator;

// ══════════════════════════════════════════════════════════════════════════
//  Standalone CLI entry point
// ══════════════════════════════════════════════════════════════════════════

async function runStandaloneCliMain(): Promise<void> {
  // Iter-96 idiom: Bun.stdin.text() one-shot read
  const inputText = await Bun.stdin.text();

  let input: PostToolUseInput;
  try {
    input = JSON.parse(inputText) as PostToolUseInput;
  } catch {
    process.exit(0);
  }

  const decision =
    await classifyMemoryEfficiencyBestPracticesReminderOncePerSessionForPostToolUseOrchestrator(
      input,
    );

  // Iter-98 silent-drop bug fix: emit `{decision: "block", reason: ...}` JSON
  // (Claude-visible context-injection surface) when contributing, not raw
  // console.log text (transcript-only operator-visible — silently dropped by
  // Claude Code per official PostToolUse schema; iter-66 forensic finding).
  if (decision.kind === "additional_context") {
    console.log(JSON.stringify({ decision: "block", reason: decision.message }));
  }
  process.exit(0);
}

if (import.meta.main) {
  runStandaloneCliMain().catch(() => {
    process.exit(0);
  });
}
