/**
 * Shared escape-hatch-marker detection helper (iter-107 — second cross-Pre/
 * PostToolUse shared-lib helper after iter-106's truncation helper).
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why this file exists (iter-107 design rationale)
 * ════════════════════════════════════════════════════════════════════════
 *
 * Most marketplace hooks support some form of "escape-hatch comment" by
 * which the operator can opt OUT of the hook's normal enforcement at a
 * specific source location (e.g., `# BASH-LAUNCHD-OK`, `# SSoT-OK`,
 * `# CWD-DELETE-OK`, `# PROCESS-STORM-OK`, `# FILE-SIZE-OK`,
 * `// INLINE-IGNORE-OK`, `# LAYER3-STRIPPED-PATH-OK: <reason ≥ 10 chars>`,
 * `// CARGO-TTY-SKIP`, etc.).
 *
 * Pre-iter-107 each hook rolled its own marker detection: a regex
 * literal plus (for hooks that scope the marker to a per-line window
 * rather than file-wide) a hand-coded lookup loop. Iter-78's layer3-
 * stripped-path guard has the most sophisticated existing variant —
 * marker + ≥10-char reason + 3-line preceding-line lookback window.
 * Iter-107 web research confirmed (2026 Claude Code docs reference,
 * https://code.claude.com/docs/en/hooks; Anthropic GitHub issue #20259)
 * that there is NO official Claude Code escape-hatch convention — each
 * hook author defines their own marker grammar. That gap leaves the
 * marketplace open to:
 *
 *   - Drift between hooks (some require ≥10-char reason, others accept
 *     bare `-OK`; some scan file-wide, others scope to per-line windows)
 *   - Bug-prone re-implementation (window-lookup loops are easy to get
 *     wrong; off-by-one at the file boundary is a recurring class)
 *   - Audit pain (a marketplace-wide inventory of escape-hatch markers
 *     requires regex-grepping every hook source file independently)
 *
 * Iter-107 (this file) establishes the canonical helper:
 *
 *   - Single `detectEscapeHatchMarkerCoveringTargetSourceLine` API that
 *     supports the 3 known window-semantics modes (same-line-only,
 *     same-line-or-preceding-N-lines, file-wide) and an optional
 *     minimum-reason-character-count policy
 *   - Single `hasFileWideEscapeHatchMarkerInContent` convenience for the
 *     simplest case (marker anywhere in file → suppress everything)
 *   - Single canonical regex grammar — `{MARKER-NAME}[:\s]` with optional
 *     reason capture, comment-style-agnostic (#, //, <!-- --> all work
 *     because the marker name only appears inside comments by convention)
 *
 * Iter-78 layer3-stripped-path guard is the FIRST migration target —
 * its hand-rolled implementation becomes a single helper call. Iter-108+
 * scope: migrate the remaining 8-10 hand-rolled implementations to the
 * shared helper, then promote the audit task from informational to
 * strict-block once all hooks are migrated.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  2026-09-03 — INVOKING a marker vs MENTIONING one (issue #106)
 * ════════════════════════════════════════════════════════════════════════
 *
 * `hasFileWideEscapeHatchMarkerInContent` is a plain substring regex over the
 * whole blob, and that is correct for a Bash COMMAND (the marker can only be
 * there because the operator typed it) but wrong for a DOCUMENT: a file that
 * merely writes the token down — a CLAUDE.md explaining the hatch, a README
 * documenting the hook, a CHANGELOG entry naming it — permanently disables
 * that hook for itself. Measured on this repo: all four tracked `.md` files
 * containing the markdown hard-wrap marker were documentation, none of them
 * was an opt-out, and all four were silently exempt from that reminder.
 *
 * `hasMarkdownCommentInvokedEscapeHatchMarkerInMarkdownContent` below is the
 * document-safe variant: the marker must sit inside an HTML comment, in live
 * markdown. See its doc comment for why the stripping is PER LINE.
 */

import { computeFencedCodeLineMask } from "./markdown-fence-scanner.ts";

// ────────────────────────────────────────────────────────────────────────
//  Window-semantics enumeration (the three canonical scoping modes)
// ────────────────────────────────────────────────────────────────────────
//
// Documented modes (iter-107 baseline; future iters may add more if a hook
// surfaces a novel window-semantics requirement):
//
//   - SAME_LINE_ONLY:
//       The marker must appear on the same line as the offending construct.
//       Used by: pretooluse-inline-ignore-guard (`// INLINE-IGNORE-OK`
//       suppresses ignore-comments only on the exact line where they appear).
//
//   - SAME_LINE_OR_PRECEDING_N_LINES:
//       The marker may appear on the offending line OR on any of the N lines
//       immediately preceding it. Best for editor-friendly opt-outs where
//       the operator places the marker as a comment above the offending
//       block. Used by: pretooluse-iter78-layer3-stripped-path-edit-time-
//       guard (`# LAYER3-STRIPPED-PATH-OK: <reason ≥ 10 chars>` with N=3).
//
//   - FILE_WIDE:
//       The marker anywhere in the file suppresses ALL enforcement for
//       that file. Used by: pretooluse-file-size-guard (`# FILE-SIZE-OK`),
//       pretooluse-version-guard (`# SSoT-OK`), pretooluse-native-binary-
//       guard (`# BASH-LAUNCHD-OK` / `<!-- BASH-LAUNCHD-OK -->`).

export type EscapeHatchMarkerWindowSemanticsMode =
  | "SAME_LINE_ONLY"
  | "SAME_LINE_OR_PRECEDING_N_LINES"
  | "FILE_WIDE";

// ────────────────────────────────────────────────────────────────────────
//  Case-sensitivity mode (iter-108 extension)
// ────────────────────────────────────────────────────────────────────────
//
// Iter-107 baseline assumed strict UPPER-KEBAB-CASE marker convention (e.g.,
// `BASH-LAUNCHD-OK`, `LAYER3-STRIPPED-PATH-OK`). Iter-108 audit of the
// pre-existing marketplace hand-rolled regexes surfaced that several hooks
// historically used `/i` (case-insensitive matching) — process-storm-guard
// (`/#\s*PROCESS-STORM-OK/i`), cwd-deletion-guard (`/#\s*CWD-DELETE-OK/i`),
// native-binary-guard (`/[#/]\s*BASH-LAUNCHD-OK/i`), cargo-tty-guard
// (`/# *CARGO-TTY-SKIP/i` + `/# *CARGO-TTY-WRAP/i`). Behavior-preserving
// migrations of those hooks require case-insensitive matching at the helper
// level. Iter-108 adds the `caseSensitivityMode` knob:
//
//   - CASE_SENSITIVE (DEFAULT): strict UPPER-KEBAB-CASE marker. `# foo-ok`
//     does NOT suppress when configured marker is `FOO-OK`. Aligns with the
//     marketplace convention going forward.
//
//   - CASE_INSENSITIVE: legacy compatibility. Lowercase, mixed-case, or any
//     casing matches. Use ONLY when migrating a hook that historically used
//     `/i` so the migration is behavior-preserving.
//
// Note on the version-guard marker: `SSoT-OK` is mixed-case (Single Source
// of Truth) and intentionally NOT UPPER-KEBAB-CASE. Hook authors writing
// the literal string `# SSoT-OK` in their content will continue to match
// the configured marker token `SSoT-OK` regardless of mode (substring
// match against the literal). Mode only matters when the operator types a
// DIFFERENT casing than the configured token (e.g., `# SSOT-OK` or
// `# ssot-ok`). Most marketplace hooks tolerate this divergence loosely
// via `/i`, but iter-108+ migrations default to strict because operators
// are expected to copy/paste the canonical token from documentation.

export type EscapeHatchMarkerCaseSensitivityMode =
  | "CASE_SENSITIVE"
  | "CASE_INSENSITIVE";

// ────────────────────────────────────────────────────────────────────────
//  Configuration shape
// ────────────────────────────────────────────────────────────────────────

export interface EscapeHatchMarkerDetectionConfiguration {
  /**
   * The marker token, INCLUDING the conventional `-OK` (or `-SKIP` / `-WRAP`)
   * suffix. Example: `"BASH-LAUNCHD-OK"`, `"LAYER3-STRIPPED-PATH-OK"`,
   * `"CARGO-TTY-SKIP"`. Marketplace convention is UPPER-KEBAB-CASE; case
   * sensitivity controlled by `caseSensitivityMode`.
   */
  markerNameTokenIncludingSuffix: string;
  /** One of the 3 documented window-semantics modes. See enum docs. */
  windowSemanticsMode: EscapeHatchMarkerWindowSemanticsMode;
  /**
   * Required only when `windowSemanticsMode === "SAME_LINE_OR_PRECEDING_N_LINES"`.
   * The number of lines BEFORE the target line that the lookup window
   * extends to (the target line itself is always included). Iter-78
   * convention: 3.
   */
  precedingLineLookbackWindowLineCount?: number;
  /**
   * Optional reason-policy gate. When > 0, the marker MUST be followed by
   * `:` (optional whitespace) then at least N non-whitespace characters of
   * reason text. Defends against meaningless `# FOO-OK` opt-outs that
   * provide no operator-facing rationale. Iter-78 + iter-105 use 10.
   * Defaults to 0 (no reason required) for backward compat with markers
   * that don't enforce a reason.
   */
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional?: number;
  /**
   * Iter-108 extension: case-sensitivity policy. Defaults to `CASE_SENSITIVE`
   * which aligns with the marketplace UPPER-KEBAB-CASE marker convention.
   * Set to `CASE_INSENSITIVE` ONLY when migrating a hook that historically
   * used `/i` so the migration is behavior-preserving. New hooks should
   * leave this unset (defaults to strict).
   */
  caseSensitivityMode?: EscapeHatchMarkerCaseSensitivityMode;
}

// ────────────────────────────────────────────────────────────────────────
//  Helper internals
// ────────────────────────────────────────────────────────────────────────

/**
 * Build the regex that matches the marker token PLUS the optional reason
 * gate, in a comment-style-agnostic way. Marker convention is UPPER-KEBAB-
 * CASE which never collides with code identifiers, so substring matching
 * is safe without comment-prefix anchors.
 *
 * If `requireMinimumReasonCharacterCountAfterColonOrZeroForOptional` is 0:
 *   Match `<MARKER-TOKEN>` anywhere in the line.
 *
 * If > 0:
 *   Match `<MARKER-TOKEN>:` optionally-whitespaced reason of ≥N non-whitespace
 *   start char + ≥(N-1) any-char continuation. Mirrors iter-78's existing
 *   regex shape so the migration is behavior-preserving.
 */
function buildEscapeHatchMarkerRegexForConfiguration(
  configuration: EscapeHatchMarkerDetectionConfiguration,
): RegExp {
  const escapedMarkerToken = configuration.markerNameTokenIncludingSuffix.replace(
    /[.*+?^${}()|[\]\\]/g,
    "\\$&",
  );
  const minimumReasonCharacterCount =
    configuration.requireMinimumReasonCharacterCountAfterColonOrZeroForOptional ?? 0;
  // Iter-108: case-sensitivity mode controls the `/i` flag on the
  // compiled regex. Default CASE_SENSITIVE aligns with marketplace
  // UPPER-KEBAB-CASE convention; CASE_INSENSITIVE preserves legacy
  // /i behavior for hooks being migrated from hand-rolled regexes.
  const regexFlags =
    (configuration.caseSensitivityMode ?? "CASE_SENSITIVE") === "CASE_INSENSITIVE"
      ? "i"
      : "";
  if (minimumReasonCharacterCount <= 0) {
    return new RegExp(escapedMarkerToken, regexFlags);
  }
  // Mirror iter-78 grammar exactly: <MARKER>:\s*[^\s].{(N-1),}
  // (first non-whitespace char + N-1 more chars = ≥N chars of reason)
  const reasonContinuationCount = Math.max(0, minimumReasonCharacterCount - 1);
  return new RegExp(
    `${escapedMarkerToken}:\\s*[^\\s].{${reasonContinuationCount},}`,
    regexFlags,
  );
}

// ────────────────────────────────────────────────────────────────────────
//  Public API — single-line target (per-line scoping)
// ────────────────────────────────────────────────────────────────────────

/**
 * Determine whether an escape-hatch marker (per the supplied configuration)
 * covers the target source line. The lookup window is determined by the
 * `windowSemanticsMode`:
 *
 *   - SAME_LINE_ONLY: only `targetLineZeroBasedIndex` is searched.
 *   - SAME_LINE_OR_PRECEDING_N_LINES: the target line plus
 *     `precedingLineLookbackWindowLineCount` lines immediately before it
 *     are searched. (Iter-78 convention; matches release-time audit
 *     `audit-pretooluse-...-l3-stripped-path-...` window exactly.)
 *   - FILE_WIDE: every line in `allSourceLines` is searched. Equivalent to
 *     `hasFileWideEscapeHatchMarkerInContent` against the joined content.
 *
 * Returns `true` if a marker matches inside the window; `false` otherwise.
 * Does NOT mutate `allSourceLines`. O(window-size × marker-regex) per call.
 */
export function detectEscapeHatchMarkerCoveringTargetSourceLine(
  allSourceLines: readonly string[],
  targetLineZeroBasedIndex: number,
  configuration: EscapeHatchMarkerDetectionConfiguration,
): boolean {
  if (targetLineZeroBasedIndex < 0 || targetLineZeroBasedIndex >= allSourceLines.length) {
    return false;
  }
  const markerRegex = buildEscapeHatchMarkerRegexForConfiguration(configuration);
  switch (configuration.windowSemanticsMode) {
    case "SAME_LINE_ONLY": {
      return markerRegex.test(allSourceLines[targetLineZeroBasedIndex] ?? "");
    }
    case "SAME_LINE_OR_PRECEDING_N_LINES": {
      const lookbackCount = configuration.precedingLineLookbackWindowLineCount ?? 0;
      if (lookbackCount < 0) {
        throw new Error(
          `iter-107 escape-hatch helper: precedingLineLookbackWindowLineCount must be ≥0 (got ${lookbackCount})`,
        );
      }
      const windowStartIndex = Math.max(0, targetLineZeroBasedIndex - lookbackCount);
      const windowText = allSourceLines
        .slice(windowStartIndex, targetLineZeroBasedIndex + 1)
        .join("\n");
      return markerRegex.test(windowText);
    }
    case "FILE_WIDE": {
      const wholeFileText = allSourceLines.join("\n");
      return markerRegex.test(wholeFileText);
    }
  }
}

// ────────────────────────────────────────────────────────────────────────
//  Public API — file-wide scoping (convenience wrapper)
// ────────────────────────────────────────────────────────────────────────

/**
 * Convenience wrapper for the file-wide case: a single marker anywhere in
 * the content suppresses ALL enforcement for the file. Equivalent to
 * `detectEscapeHatchMarkerCoveringTargetSourceLine` with
 * `windowSemanticsMode: "FILE_WIDE"` but accepts a single content blob
 * instead of pre-split lines (saves an allocation when the caller doesn't
 * already have lines).
 *
 * Used by file-size-guard (`# FILE-SIZE-OK`), version-guard (`# SSoT-OK`),
 * native-binary-guard (`# BASH-LAUNCHD-OK`), process-storm-guard
 * (`# PROCESS-STORM-OK`), cwd-deletion-guard (`# CWD-DELETE-OK`), and
 * cargo-tty-guard (`// CARGO-TTY-SKIP`, `// CARGO-TTY-WRAP`).
 */
export function hasFileWideEscapeHatchMarkerInContent(
  contentBlob: string,
  configuration: Pick<
    EscapeHatchMarkerDetectionConfiguration,
    | "markerNameTokenIncludingSuffix"
    | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
  >,
): boolean {
  const markerRegex = buildEscapeHatchMarkerRegexForConfiguration({
    ...configuration,
    windowSemanticsMode: "FILE_WIDE",
  });
  return markerRegex.test(contentBlob);
}

// ────────────────────────────────────────────────────────────────────────
//  Public API — markdown documents (invoking vs mentioning, issue #106)
// ────────────────────────────────────────────────────────────────────────

/**
 * An indented code block line: four spaces or a tab before the first non-space.
 * Local copy rather than an import from `hard-wrap-detector.ts`, so this helper
 * keeps its single markdown dependency (the fence scanner) and no hook pays for
 * the wrap detector just to test an escape hatch.
 */
function isIndentedCodeBlockLine(rawLine: string): boolean {
  return /^(?: {4,}|\t)\S/.test(rawLine);
}

/**
 * Blank out inline-code spans ON ONE LINE, preserving the line's length so
 * character offsets stay valid.
 *
 * 🔴 PER LINE, never whole-file. A whole-file stripper re-pairs backticks across
 * the entire document, so the moment a file contains an ODD number of backticks
 * — one stray tick in prose, which 19 of this repo's 1,094 tracked `.md` files
 * have — the stripper eats from that stray tick through the first backtick
 * inside a legitimate escape comment, deleting the `<!--` opener and the marker
 * with it. The file the operator deliberately exempted silently stops being
 * exempt. That is not hypothetical: `~/eon/ccmax-monitor`'s PROVENANCE.md opens
 * with a multi-line escape comment whose interior contains a code span.
 *
 * Per-line stripping cannot reach across a line boundary, so a stray tick can
 * corrupt at most its own line, and the marker line survives.
 */
function blankInlineCodeSpansWithinSingleLine(line: string): string {
  return line.replace(/(`+)[^\n]*?\1/g, (span) => " ".repeat(span.length));
}

/**
 * The character ranges of `content` that sit inside an HTML comment.
 * An unterminated `<!--` runs to end of input, mirroring how the fence scanner
 * treats an unterminated fence — an operator who opened a comment and never
 * closed it still meant everything after it to be a comment.
 */
function computeHtmlCommentCharacterRanges(content: string): Array<[number, number]> {
  const ranges: Array<[number, number]> = [];
  let cursor = 0;
  for (;;) {
    const open = content.indexOf("<!--", cursor);
    if (open === -1) break;
    const close = content.indexOf("-->", open + 4);
    const end = close === -1 ? content.length : close + 3;
    ranges.push([open, end]);
    cursor = end;
  }
  return ranges;
}

/**
 * File-wide escape-hatch detection for a MARKDOWN DOCUMENT: true only when the
 * marker is INVOKED, not merely MENTIONED.
 *
 * Invoking means all of the following, and the union is the whole grammar:
 *
 *   1. the marker sits inside an HTML comment — `<!-- MARKER -->`, single- or
 *      multi-line — which is how every real opt-out in this fleet was already
 *      written, and is what distinguishes "I am switching this off" from "this
 *      is the token you would type to switch it off";
 *   2. that line is not inside a fenced code block — a doc showing the marker
 *      in a ```` ``` ```` example is teaching, not opting out;
 *   3. that line is not an indented (4-space / tab) code block line, same
 *      reason;
 *   4. the marker is not inside an inline-code span — `` `<!-- MARKER -->` ``
 *      in prose is a quotation of the syntax.
 *
 * Scope is still FILE_WIDE: one invocation anywhere exempts the whole file.
 * Only the grammar narrowed.
 *
 * RESIDUAL LIMIT, stated plainly: any raw `<!-- MARKER -->` sequence that is
 * outside a fence, outside an inline-code span and outside an indented code
 * block DOES suppress, whatever the surrounding prose says. A document that
 * needs to show a live-looking comment example must fence it, indent it, or
 * wrap it in backticks — all three of which are the normal way to show markup
 * anyway. There is no way to write a genuinely raw comment "as an example" and
 * have it not count, because at that point it is indistinguishable from an
 * opt-out.
 */
export function hasMarkdownCommentInvokedEscapeHatchMarkerInMarkdownContent(
  markdownContent: string,
  configuration: Pick<
    EscapeHatchMarkerDetectionConfiguration,
    | "markerNameTokenIncludingSuffix"
    | "requireMinimumReasonCharacterCountAfterColonOrZeroForOptional"
    | "caseSensitivityMode"
  >,
): boolean {
  if (!markdownContent) return false;

  const rawLines = markdownContent.replace(/\r\n/g, "\n").split("\n");
  const inFence = computeFencedCodeLineMask(rawLines);

  // Length-preserving redaction, so an offset in `scannable` is an offset in
  // the original and the line lookup below stays a plain prefix-sum.
  const scannableLines = rawLines.map((line, index) =>
    inFence[index] ? " ".repeat(line.length) : blankInlineCodeSpansWithinSingleLine(line),
  );
  const scannable = scannableLines.join("\n");

  const commentRanges = computeHtmlCommentCharacterRanges(scannable);
  if (commentRanges.length === 0) return false;

  // Line start offsets, for mapping a match back to the line it landed on.
  const lineStartOffsets: number[] = [];
  let offset = 0;
  for (const line of scannableLines) {
    lineStartOffsets.push(offset);
    offset += line.length + 1; // +1 for the "\n" that `join` re-inserted
  }
  const lineIndexOfOffset = (position: number): number => {
    let low = 0;
    let high = lineStartOffsets.length - 1;
    while (low < high) {
      const mid = (low + high + 1) >> 1;
      if (lineStartOffsets[mid] <= position) low = mid;
      else high = mid - 1;
    }
    return low;
  };

  const markerRegex = new RegExp(
    buildEscapeHatchMarkerRegexForConfiguration({
      ...configuration,
      windowSemanticsMode: "FILE_WIDE",
    }).source,
    `${(configuration.caseSensitivityMode ?? "CASE_SENSITIVE") === "CASE_INSENSITIVE" ? "i" : ""}g`,
  );

  for (const match of scannable.matchAll(markerRegex)) {
    const position = match.index ?? -1;
    if (position < 0) continue;
    if (isIndentedCodeBlockLine(rawLines[lineIndexOfOffset(position)] ?? "")) continue;
    if (commentRanges.some(([start, end]) => position >= start && position < end)) return true;
  }
  return false;
}
