#!/usr/bin/env bun
/**
 * PostToolUse hook: net-new markdown hard-wrap reminder.
 *
 * Fires on Write/Edit/MultiEdit of a `.md`/`.markdown` file when the edit
 * INTRODUCES hard-wrapped prose — a paragraph broken mid-sentence at a fixed
 * column instead of authored as one line that the renderer reflows.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why a reminder here at all — the surface-dependent truth
 * ════════════════════════════════════════════════════════════════════════
 *
 * Hard wrapping does NOT break a repository `.md` file's rendering. Per the
 * GFM spec §6.13 a soft line break renders as a SPACE, so GitHub reflows a
 * wrapped paragraph in a README/CLAUDE.md correctly. Any reminder claiming
 * otherwise would be false, and this one does not claim it.
 *
 * What DOES break is every GitHub surface that enables hard-break rendering —
 * release notes, issue bodies, PR bodies, and comments — where each newline
 * becomes a literal `<br>`. This marketplace's markdown is routinely lifted
 * into exactly those surfaces (release notes are built from repo prose, issues
 * quote skill docs), which is why the sibling guards exist:
 *
 *   - `pretooluse-github-hard-wrap-guard.ts` — blocks `gh release|issue|pr|api`
 *   - `release.config.cjs` → `reflowCommitBodyForGfm()` — reflows semantic-release
 *   - `pretooluse-gmail-body-guard.ts` — blocks a hard-wrapped Gmail draft
 *
 * Those cover the PUBLISH boundary. This hook covers the AUTHORING boundary,
 * which was the one unguarded surface: `stop-markdown-lint.ts` runs prettier
 * with `--prose-wrap preserve`, so a hard wrap written into a `.md` is
 * preserved forever — never fixed, and until now never flagged.
 *
 * The second, always-applicable harm is diff noise: rewording one sentence in
 * a hard-wrapped paragraph re-flows every following line, so `git diff` and
 * `git blame` report the whole paragraph as changed.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why NET-NEW only
 * ════════════════════════════════════════════════════════════════════════
 *
 * Measured over this repo's 1,114 tracked `.md` files: 193 of them (17%) are
 * already hard-wrapped, 3,389 wrap points in total. A hook that fired whenever
 * an edited file CONTAINED a wrap would nag on every one of those files, every
 * time, for debt the current edit did not create — and a guard that cries wolf
 * is a guard that gets disabled.
 *
 * So the Edit/MultiEdit arms compare wrap counts BEFORE and AFTER and fire only
 * when the count increases, exactly as `posttooluse-invented-fallback-reminder.ts`
 * does for invented display values. Touching a legacy wrapped paragraph is
 * silent; introducing a new one is not.
 *
 * The Write arm is the one non-strict case, and deliberately so: PostToolUse
 * fires AFTER the write, so the previous content is already gone from disk and
 * there is no before-state to compare against. Firing on any hit is correct
 * there anyway — a whole-file Write IS authoring, and freshly authored prose
 * should not arrive pre-wrapped.
 *
 * Output channel: `{ kind: "additional_context" }`, which the iter-93
 * orchestrator folds into one `{ decision: "block", reason }` emission. That
 * does NOT undo the edit — for PostToolUse it is the documented mechanism for
 * surfacing a Claude-visible system reminder next to the tool result.
 *
 * Escape hatch: `MD-HARD-WRAP-OK` anywhere in the edited text (iter-111
 * canonical registry). Fail-open everywhere: any error → noop, never noise.
 */

import { existsSync, statSync } from "node:fs";
import {
  buildPostToolUseAdditionalContextDecision,
  isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook,
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  type PostToolUseInput,
  type PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import { detectHardWraps, type WrapIssue } from "./lib/hard-wrap-detector.ts";
import { trackHookError } from "./lib/hook-error-tracker.ts";
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

const HOOK_NAME = "markdown-hard-wrap-reminder";
const MD_HARD_WRAP_OK_MARKER = "MD-HARD-WRAP-OK";

/** `PostToolUseInput.tool_input` with the MultiEdit `edits[]` array named. */
interface MultiEditCapableToolInput {
  file_path?: string;
  content?: string;
  old_string?: string;
  new_string?: string;
  replace_all?: boolean;
  edits?: Array<{ old_string?: string; new_string?: string; replace_all?: boolean }>;
}

/** Match `.md` / `.markdown` (case-insensitive), mirroring the table guard. */
function isMarkdownFilePath(filePath: string): boolean {
  return /\.(?:md|markdown)$/i.test(filePath);
}

/**
 * Pure activation gate (exported for tests): a Write/Edit/MultiEdit of a
 * durable `.md` file, never a throwaway copy in a temp scratch dir.
 */
export function isMarkdownHardWrapReminderEligibleTarget(
  toolName: string,
  filePath: string,
): boolean {
  if (!isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(toolName)) return false;
  if (!filePath || !isMarkdownFilePath(filePath)) return false;
  if (
    isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
      filePath,
    )
  ) {
    return false;
  }
  return true;
}

/** Wrap count of a text fragment. An empty/one-line fragment is always 0. */
function countWraps(text: string): number {
  if (!text) return 0;
  return detectHardWraps(text).length;
}

/**
 * The `{ oldS, newS }` replacements a tool call performed, in applied order.
 *
 * `all` mirrors the tool's `replace_all` flag. Dropping it silently corrupts the
 * before-state: `replace_all` rewrote EVERY occurrence, so undoing only the
 * first leaves the rest of the new text in the reconstruction and the wrap
 * delta comes out short.
 */
function extractEditPairs(ti: MultiEditCapableToolInput, toolName: string) {
  return toolName === "MultiEdit"
    ? (ti.edits || []).map((e) => ({
        oldS: e.old_string || "",
        newS: e.new_string || "",
        all: e.replace_all === true,
      }))
    : [
        {
          oldS: ti.old_string || "",
          newS: ti.new_string || "",
          all: ti.replace_all === true,
        },
      ];
}

/**
 * Reconstruct the file as it stood BEFORE this tool call, by undoing each
 * replacement in reverse order.
 *
 * `String.prototype.replace` with a string pattern rewrites the FIRST match
 * only, which is exactly Edit's own contract (Edit requires `old_string` to be
 * unique unless `replace_all` is set). Reverse order matters for MultiEdit
 * because a later edit may have landed inside text an earlier one produced.
 */
function reconstructContentBeforeEdits(
  contentAfter: string,
  pairs: ReadonlyArray<{ oldS: string; newS: string; all: boolean }>,
): string {
  let content = contentAfter;
  pairs
    .toReversed()
    .forEach(({ oldS, newS, all }) => {
      if (newS === "") return; // pure deletion — nothing to undo by substitution
      content = all ? content.replaceAll(newS, oldS) : content.replace(newS, oldS);
    });
  return content;
}

/**
 * Identify a wrap by its SHAPE, not its line number. Undoing an edit shifts
 * every subsequent line, so a line-number join would report the whole tail of
 * the file as new; width + continuation text is stable across that shift.
 */
const wrapSignature = (w: WrapIssue): string => `${w.width} ${w.nextPreview}`;

/** Multiset difference: the `after` wraps that were not already in `before`. */
function wrapsAddedBetween(before: WrapIssue[], after: WrapIssue[]): WrapIssue[] {
  const remaining = new Map<string, number>();
  for (const w of before) {
    const k = wrapSignature(w);
    remaining.set(k, (remaining.get(k) ?? 0) + 1);
  }
  const added: WrapIssue[] = [];
  for (const w of after) {
    const k = wrapSignature(w);
    const n = remaining.get(k) ?? 0;
    if (n > 0) remaining.set(k, n - 1);
    else added.push(w);
  }
  return added;
}

/**
 * The net-new verdict (exported for tests): the wraps this tool call ADDED, or
 * an empty array when it added none.
 *
 * `fileContentAfterEdit` is the whole file as it now stands on disk. Passing it
 * is what makes the result trustworthy: an Edit fragment lifted from INSIDE a
 * fenced code block carries no ``` markers, so scanning the fragment alone
 * reads shell commands as wrapped prose (two `bun …` lines in a ```bash block
 * were a measured false positive). Scanning the reconstructed whole file gives
 * the fence scanner the state it needs. When the file cannot be read the
 * fragment comparison is used as a best-effort fallback rather than going
 * silent.
 *
 * Write has no before-state — PostToolUse fires after the write, so the prior
 * content is already gone — and reports every wrap it wrote.
 */
export function detectNetNewMarkdownHardWraps(
  input: PostToolUseInput,
  fileContentAfterEdit: string | null = null,
): WrapIssue[] {
  const ti = (input.tool_input || {}) as MultiEditCapableToolInput;
  const suppressed = (text: string) =>
    hasFileWideEscapeHatchMarkerInContent(text, {
      markerNameTokenIncludingSuffix: MD_HARD_WRAP_OK_MARKER,
    });

  if (input.tool_name === "Write") {
    const content = ti.content || "";
    return suppressed(content) ? [] : detectHardWraps(content);
  }

  const pairs = extractEditPairs(ti, input.tool_name);

  if (fileContentAfterEdit !== null) {
    if (suppressed(fileContentAfterEdit)) return [];
    const after = detectHardWraps(fileContentAfterEdit);
    if (after.length === 0) return [];
    const before = detectHardWraps(reconstructContentBeforeEdits(fileContentAfterEdit, pairs));
    return wrapsAddedBetween(before, after);
  }

  // Fallback: no file on disk (synthetic input, deleted file). Compare the
  // replaced fragment against its replacement, per-edit.
  for (const { oldS, newS } of pairs) {
    if (suppressed(newS)) continue;
    const after = detectHardWraps(newS);
    if (after.length > countWraps(oldS)) return after;
  }
  return [];
}

/** Build the Claude-visible reminder for the wraps this edit introduced. */
export function buildMarkdownHardWrapReminder(filePath: string, wraps: WrapIssue[]): string {
  const lines: string[] = [
    `[MD-HARD-WRAP] This edit added hard-wrapped prose to ${filePath}.`,
    "",
    `${wraps.length} paragraph line(s) break mid-sentence at a fixed column:`,
  ];

  for (const w of wraps.slice(0, 3)) {
    lines.push(`  L${w.line}: ${w.width} cols → continues: "${w.nextPreview}"`);
  }
  if (wraps.length > 3) lines.push(`  …and ${wraps.length - 3} more.`);

  lines.push(
    "",
    "Why it matters: a repo .md renders fine (GFM soft breaks collapse to a space), but this",
    "prose breaks when it reaches a surface that renders newlines as <br> — release notes,",
    "issue and PR bodies, comments. It also makes every reword re-diff the whole paragraph.",
    "",
    "Fix: author each PARAGRAPH as ONE unbroken line and let the renderer reflow it. Keep",
    "only structural breaks (list items, headings, code blocks, table rows, blank lines).",
    "",
    "To reflow an existing file: bun scripts/reflow-release-notes.ts < file.md > file.new.md",
    "(joins wrapped prose and list items; it does NOT understand 4-space-indented code blocks,",
    "so check the diff if the file has any).",
    "",
    `Override: add ${MD_HARD_WRAP_OK_MARKER} to the file when the wrapping is deliberate.`,
  );

  return lines.join("\n");
}

/**
 * Orchestrator classifier (iter-93 contract). Pure + fail-open: never throws,
 * never touches stdio, resolves well inside its registry timeout — it reads no
 * files and runs one linear scan over the edited fragment.
 */
export async function classifyMarkdownHardWrapReminderForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const filePath = (input.tool_input?.file_path as string) || "";
    if (!isMarkdownHardWrapReminderEligibleTarget(input.tool_name, filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    // PostToolUse runs after the write, so the file on disk IS the post-edit
    // state — reading it is what gives the fence scanner whole-file context.
    //
    // Read ONLY a regular file. `Bun.file(p).text()` on a FIFO blocks until a
    // writer appears, which would hang this subhook until the orchestrator's
    // timeout fires on every edit — a guard that can hang is a guard that gets
    // removed. Same isFile() gate the sibling github-hard-wrap-guard uses.
    let contentOnDisk: string | null = null;
    try {
      if (existsSync(filePath) && statSync(filePath).isFile()) {
        contentOnDisk = await Bun.file(filePath).text();
      }
    } catch {
      contentOnDisk = null; // unreadable → fragment fallback, never a crash
    }
    const wraps = detectNetNewMarkdownHardWraps(input, contentOnDisk);
    if (wraps.length === 0) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    return buildPostToolUseAdditionalContextDecision(
      buildMarkdownHardWrapReminder(filePath, wraps),
    );
  } catch (err: unknown) {
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

// ── Standalone CLI (kept runnable like every sibling subhook) ────────────────

async function main(): Promise<never> {
  try {
    const stdin = await Bun.stdin.text();
    if (stdin.trim()) {
      const input = JSON.parse(stdin) as PostToolUseInput;
      const decision = await classifyMarkdownHardWrapReminderForPostToolUseOrchestrator(input);
      if (decision.kind === "additional_context") {
        console.log(JSON.stringify({ decision: "block", reason: decision.message }));
      }
    }
  } catch (err: unknown) {
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
  }
  return process.exit(0);
}

if (import.meta.main) {
  void main();
}
