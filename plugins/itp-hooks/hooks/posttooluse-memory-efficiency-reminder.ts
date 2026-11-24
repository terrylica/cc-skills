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
 *   - No subprocess: one bounded read of the file's head (up to 256 KiB) and
 *     linear-time regexes until the card fires, then a sub-ms gate check
 *   - Its patterns use [ \t], never \s, at line starts: \s also matches
 *     newlines, which made one pattern quadratic in runs of blank lines
 *     (52 s on 256 KiB of them; PR #104 review)
 *
 * ─── 2026-11-15: fires on data-path code only ─────────────────────────────
 *
 * Until 2026-11-15 the card fired on the first code file of the session,
 * whatever the code did: a 35-line Cloudflare Worker that redirects requests
 * got the zero-copy / Arrow / pd.concat table (operator report, 2026-11-15).
 * The card's own header says "When writing data-path code", so it now
 * fires only when the edited file shows data-path evidence
 * (`detectDataPathEvidenceInSourceText`: a dataframe/array/columnar library,
 * Arrow, Parquet, ClickHouse, numeric typed arrays or vectors, memory maps,
 * memcpy/malloc, binary unpacking, tensors, bulk CSV). The evidence is read
 * from the head of the post-edit file on disk (an Edit's `new_string` rarely
 * carries the imports), falling back to the tool input's text.
 *
 * Precision and the once-per-session gate are one axis: the card fires at
 * most once, so a false positive also spends the session's only shot before
 * the real data-path file is written. The gate is therefore claimed only
 * AFTER evidence is found, never on an ordinary code edit.
 *
 * Gate: fires once per session via atomic O_EXCL gate-file (shared helper),
 *       claimed only after data-path evidence is found.
 * Scope: .py, .rs, .ts, .tsx, .js, .go, .java, .kt, .rb, .cpp, .c, .h, .zig
 * Skips: test files (pattern-matched), temp-dir scratch files, and any file
 *        with no data-path evidence.
 */

import { closeSync, fstatSync, openSync, readSync } from "node:fs";

import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
  isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook,
} from "./lib/posttooluse-subhook-contract-iter93.ts";
import {
  isOncePerSessionGenericReminderGateFileAlreadyClaimed,
  tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName,
} from "./lib/posttooluse-subhook-async-helpers-iter95.ts";
// Iter-124: don't let a throwaway temp-file edit consume the once-per-session
// reminder gate — skip temp dirs so the first REAL code edit still gets it.
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temp-dir-edit-path-detection-iter124.ts";

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

/** Bytes of the post-edit file probed for data-path evidence (imports sit at the top). */
const DATA_PATH_EVIDENCE_FILE_HEAD_PROBE_BYTES = 256 * 1024;

/**
 * Data-path evidence, one named signal per entry; the first match wins and its
 * name is quoted in the reminder so a misfire can be traced to its pattern.
 *
 * Deliberately NOT evidence (each would fire on ordinary service code, which is
 * the misfire this list exists to stop): `Uint8Array` and `ArrayBuffer` (every
 * Worker that hashes or encodes text), `ReadableStream`, `Vec<u8>`, bare `[]byte`,
 * `JSON.parse`, `fetch`, and the word "arrow" alone ("arrow function").
 */
export const DATA_PATH_EVIDENCE_SIGNALS: ReadonlyArray<{ name: string; pattern: RegExp }> = [
  {
    name: "dataframe, array or columnar library",
    pattern:
      /\b(?:polars|pandas|numpy|pyarrow|duckdb|datafusion|ndarray|xarray|dask|numba|cupy|h5py|zarr|vaex|modin|gonum|danfojs|arquero|hyparquet)\b/,
  },
  { name: "Apache Arrow", pattern: /apache[-./]arrow\b|\barrow(?:2|_[a-z]+)?::|\bred-arrow\b/ },
  { name: "Parquet", pattern: /\bparquet\b/i },
  { name: "ClickHouse", pattern: /\bclickhouse\b/i },
  { name: "frame or record-batch type", pattern: /\b(?:DataFrame|LazyFrame|RecordBatch)\b/ },
  {
    name: "numeric typed array",
    pattern: /\b(?:Float16|Float32|Float64|Int16|Int32|Uint16|Uint32|BigInt64|BigUint64)Array\b|\bSharedArrayBuffer\b/,
  },
  {
    name: "numeric vector or slice",
    pattern: /\bVec<(?:f32|f64|i32|i64|u32|u64)>|&\[(?:f32|f64)\]|\[\](?:float32|float64)\b|std::vector<(?:float|double|u?int(?:32|64)_t)>/,
  },
  {
    name: "memory map, raw copy or binary unpacking",
    pattern: /\b(?:memoryview|mmap|memmap2?|memcpy|ByteBuffer|bytemuck)\b|\bstruct\.(?:iter_)?unpack\b/,
  },
  { name: "manual allocation", pattern: /\b(?:malloc|calloc|realloc)\s*\(|\bstd\.mem\.Allocator\b/ },
  { name: "tensor library", pattern: /^[ \t]*(?:import|from)[ \t]+(?:torch|jax|tensorflow)\b/m },
  { name: "bulk CSV reader or writer", pattern: /\bcsv\.(?:reader|DictReader|writer|DictWriter)\b/ },
];

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

/** The name of the first data-path signal found in `text`, or null when there is none. */
export function detectDataPathEvidenceInSourceText(text: string): string | null {
  for (const signal of DATA_PATH_EVIDENCE_SIGNALS) {
    if (signal.pattern.test(text)) return signal.name;
  }
  return null;
}

/** The first DATA_PATH_EVIDENCE_FILE_HEAD_PROBE_BYTES of a file, or null when it cannot be read. */
function readFileHeadForDataPathEvidence(filePath: string): string | null {
  let fd: number | undefined;
  try {
    fd = openSync(filePath, "r");
    // Sized to the file (capped), not a fixed 256 KiB zero-filled buffer per probe.
    const buffer = Buffer.allocUnsafe(Math.min(fstatSync(fd).size, DATA_PATH_EVIDENCE_FILE_HEAD_PROBE_BYTES));
    const bytesRead = readSync(fd, buffer, 0, buffer.length, 0);
    return buffer.subarray(0, bytesRead).toString("utf8");
  } catch {
    return null;
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

/**
 * The text to probe: the post-edit file on disk (PostToolUse runs after the
 * write, and an Edit's new_string rarely carries the imports), else the text
 * in the tool input.
 */
function resolveEditedSourceTextForDataPathEvidence(input: PostToolUseInput, filePath: string): string {
  const onDisk = readFileHeadForDataPathEvidence(filePath);
  if (onDisk !== null) return onDisk;
  const toolInput = input.tool_input ?? {};
  if (typeof toolInput.content === "string") return toolInput.content;
  if (typeof toolInput.new_string === "string") return toolInput.new_string;
  return "";
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Classify a PostToolUse Write|Edit event for memory-efficiency-reminder
 * relevance.
 *
 *   - Returns `additional_context` ONCE PER SESSION on the first eligible
 *     code-file edit whose file shows data-path evidence (gated atomically
 *     via shared O_EXCL helper, claimed only after the evidence is found).
 *   - Code edits without evidence return `noop` and leave the gate unclaimed.
 *     The probe is one bounded head read of the edited file (≤256 KiB) plus a
 *     handful of regex tests; no subprocess.
 *   - All edits after the reminder fired return `noop` (gate already claimed).
 *   - Skips test files (test fixtures legitimately use memory-inefficient
 *     patterns for clarity).
 *
 * The message is the pre-iter-98 card text plus one line naming the file
 * and the signal that matched, so a misfire can be traced to its pattern.
 */
export async function classifyMemoryEfficiencyBestPracticesReminderOncePerSessionForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    // Honor Write|Edit via the canonical contract helper.
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
    if (
      isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
        filePath,
      )
    ) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const sessionId =
      input.session_id || process.env.CLAUDE_SESSION_ID || String(process.ppid); // SSoT-OK: hook-runtime session id, not app config
    if (
      isOncePerSessionGenericReminderGateFileAlreadyClaimed(
        MEMORY_EFFICIENCY_REMINDER_NAME_FOR_ONCE_PER_SESSION_GATE_FILE_NAMESPACE,
        sessionId,
      )
    ) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Evidence BEFORE the claim: an ordinary code edit must not spend the
    // session's single reminder (2026-11-15 misfire on a redirect Worker).
    const dataPathEvidence = detectDataPathEvidenceInSourceText(
      resolveEditedSourceTextForDataPathEvidence(input, filePath),
    );
    if (dataPathEvidence === null) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    if (
      !tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName(
        MEMORY_EFFICIENCY_REMINDER_NAME_FOR_ONCE_PER_SESSION_GATE_FILE_NAMESPACE,
        sessionId,
      )
    ) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    return buildPostToolUseAdditionalContextDecision(
      `${MEMORY_EFFICIENCY_BEST_PRACTICES_STATIC_REMINDER_MESSAGE}\n\nShown because ${filePath} contains data-path code (${dataPathEvidence}).`,
    );
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

/**
 * Symmetric-naming alias matching the sibling subhooks (ty, tsc, oxlint,
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
