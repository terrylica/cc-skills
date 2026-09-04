/**
 * GFM paragraph unwrapper — the inverse of the hard-wrap defect, and the fix
 * the hard-wrap guard tells you to apply.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why this exists
 * ════════════════════════════════════════════════════════════════════════
 *
 * GitHub Flavored Markdown renders every newline inside a paragraph as an HTML
 * `<br>` on issues, PRs, comments and releases. Prose hard-wrapped at ~100
 * columns therefore renders as a column of short mid-sentence lines that
 * cannot reflow to the reader's window — unreadable on a phone, ragged on a
 * desktop. `hard-wrap-detector.ts` FINDS that defect. This module REPAIRS it.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  The one invariant
 * ════════════════════════════════════════════════════════════════════════
 *
 * This transformation may ONLY join lines. It must never add, delete or alter
 * a single non-whitespace character. `assertContentPreserved` proves that on
 * every call, and the unwrapper THROWS if it is ever violated — it does not
 * fall back to returning the input, because a silent no-op that looks like a
 * successful repair is exactly the failure this codebase keeps having.
 *
 * The check normalises away the two things unwrapping is allowed to change:
 * per-line blockquote markers (three `> ` lines become one) and whitespace.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  What is never joined
 * ════════════════════════════════════════════════════════════════════════
 *
 *   - fenced code (``` / ~~~) and its contents, verbatim
 *   - indented code blocks that are NOT a list item's continuation
 *   - table rows, headings, thematic breaks, setext underlines
 *   - link/footnote reference definitions, raw HTML block lines
 *   - YAML front matter
 *   - a line ending in two spaces or a backslash — an INTENTIONAL markdown
 *     hard break, which is the one case where the author meant the `<br>`
 *   - blank lines, which separate paragraphs and are preserved exactly
 *
 * List items ARE joined, but only with their own continuation lines: each item
 * keeps its marker and stays on its own line.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  CJK
 * ════════════════════════════════════════════════════════════════════════
 *
 * Joining two lines of Chinese with a space inserts a space that was never in
 * the text and that a reader sees. When the join point is CJK on both sides,
 * the lines are concatenated with no separator. This matters here specifically:
 * the operator corresponds with a Chinese-speaking collaborator and quotes his
 * words verbatim in GitHub issues, where an inserted space would corrupt a
 * quotation attributed to a named person.
 */

import { computeFencedCodeLineMask } from "./markdown-fence-scanner.ts";
import {
  computeListContinuationLineMask,
  isHeading,
  isHtmlBlockLine,
  isIndentedCodeBlock,
  isReferenceDefinition,
  isSetextUnderline,
  isTableRow,
  isThematicBreak,
  isYamlFrontMatterDelimiter,
} from "./hard-wrap-detector.ts";

/** Leading blockquote marker run: `>`, `> `, `> > `, with optional indent. */
const BLOCKQUOTE_PREFIX = /^(\s*(?:>[ \t]?)+)/;

/** A list item marker: `- `, `* `, `+ `, `1. `, `1) `, with optional indent. */
const LIST_MARKER = /^\s*(?:[-*+]|\d+[.)])\s+/;

/**
 * A hand-aligned block line: indented, with a run of 2+ spaces between text.
 *
 * These are columns the author lined up — mapping tables, before/after lists,
 * key/value pairs. CommonMark calls an indented-by-less-than-four block ordinary
 * paragraph text, so a naive unwrap joins ten aligned rows into one unreadable
 * line. That is correct markdown and wrong output.
 *
 * Ported verbatim in intent from `scripts/reflow-release-notes.ts`, which learned
 * it the expensive way on cc-skills v27.0.1: a commit body mapping eleven
 * redacted identifiers in a 2-space-indented table reflowed into a single
 * 500-character line. `reflow-release-notes.agreement.test.ts` pins the two
 * implementations together so this cannot drift back apart.
 *
 * Deliberately narrow. Indentation ALONE would match wrapped bullet
 * continuations, which must still fold back into their bullet; requiring an
 * internal run of 2+ spaces is what distinguishes a table from a sentence. The
 * cost of a false positive is one paragraph left wrapped; the cost of a false
 * negative is a destroyed table, so the asymmetry favours being slightly eager.
 */
const ALIGNED_BLOCK_LINE = /^[ \t]+\S.*\S {2,}\S/;

/**
 * An INTENTIONAL markdown hard break: the author ended the line with two or
 * more spaces, or with a backslash. Joining these would change the rendering
 * the author asked for, so they terminate a joinable run.
 */
function hasIntentionalBreak(rawLine: string): boolean {
  return /(?: {2,}|\\)$/.test(rawLine.replace(/[\t\r]+$/, ""));
}

/**
 * Every code point this module treats as CJK, as a character-class body.
 *
 * ONE source string, used by both the join rule and the content-preservation
 * normaliser. If those two ever disagreed about what counts as CJK, the
 * invariant would either fire on correct Chinese joins or — far worse — stop
 * noticing a corrupted one.
 */
const CJK_CLASS = "\\u2e80-\\u9fff\\uf900-\\ufaff\\ufe30-\\ufe4f\\uff00-\\uff65\\u{20000}-\\u{3fffd}";

/** Exactly one CJK character. */
const CJK_CHAR = new RegExp(`^[${CJK_CLASS}]$`, "u");

/** A single space sitting between two CJK characters. */
const SPACE_BETWEEN_CJK = new RegExp(`(?<=[${CJK_CLASS}]) (?=[${CJK_CLASS}])`, "gu");

/** True when a character is CJK ideographic / kana / fullwidth punctuation. */
function isCjk(ch: string | undefined): boolean {
  return ch !== undefined && CJK_CHAR.test(ch);
}

/**
 * Join a wrapped continuation onto an accumulating line.
 *
 * A space between two CJK characters is visible to the reader and is not in
 * the source, so it is omitted there. Everywhere else a single space is the
 * correct join, because the newline it replaces was itself whitespace.
 */
function joinWrapped(accumulated: string, continuation: string): string {
  const left = accumulated.replace(/\s+$/, "");
  const right = continuation.replace(/^\s+/, "");
  if (left === "") return right;
  if (right === "") return left;
  const lastOfLeft = [...left].pop();
  const firstOfRight = [...right][0];
  const separator = isCjk(lastOfLeft) && isCjk(firstOfRight) ? "" : " ";
  return left + separator + right;
}

/**
 * A line whose break is STRUCTURAL — it must be emitted verbatim on its own
 * line and can neither absorb the next line nor be absorbed by the previous.
 *
 * `isListContinuation` suppresses the indented-code test, because four spaces
 * inside a list item is that item's continuation paragraph, not a code block.
 */
function isStructuralLine(rawLine: string, isListContinuation: boolean): boolean {
  if (isTableRow(rawLine)) return true;
  if (isHeading(rawLine)) return true;
  if (isThematicBreak(rawLine)) return true;
  if (isSetextUnderline(rawLine)) return true;
  if (isReferenceDefinition(rawLine)) return true;
  if (isHtmlBlockLine(rawLine)) return true;
  if (!isListContinuation && isIndentedCodeBlock(rawLine)) return true;
  // Checked AFTER a list marker would match, so an aligned-looking bullet still
  // behaves as a bullet; only non-list aligned rows are preserved verbatim.
  if (ALIGNED_BLOCK_LINE.test(rawLine) && !LIST_MARKER.test(rawLine)) return true;
  return false;
}

/** How many `>` markers a line's leading blockquote prefix carries. */
function quoteDepth(prefix: string): number {
  return prefix.match(/>/g)?.length ?? 0;
}

/**
 * Normalise a body so that two texts differing ONLY by where paragraphs were
 * wrapped compare equal.
 *
 * Three normalisations, each corresponding to exactly one thing unwrapping is
 * permitted to change, and nothing else:
 *
 *   1. leading blockquote markers — three `> ` lines legitimately become one;
 *   2. whitespace runs — the newline being removed was itself whitespace;
 *   3. a space BETWEEN TWO CJK CHARACTERS — because `joinWrapped` deliberately
 *      concatenates Chinese without a separator, while a newline collapses to
 *      a space under (2). Without this the invariant fires on every correct
 *      Chinese join. It is deliberately narrow: a space between a CJK
 *      character and a Latin one still counts, so `HSA PHSP` losing its space
 *      is still a corruption and is still caught.
 *
 * What survives is the actual content, so any remaining difference is real.
 */
export function normalizeForContentComparison(text: string): string {
  return text
    .replace(/\r\n/g, "\n")
    .split("\n")
    .map((line) => line.replace(BLOCKQUOTE_PREFIX, ""))
    .join("\n")
    .replace(/\s+/g, " ")
    .replace(SPACE_BETWEEN_CJK, "")
    .trim();
}

/**
 * Throw when unwrapping changed anything other than line breaks.
 *
 * Deliberately a throw and not a boolean the caller may ignore. This function
 * is the only thing standing between "reflow a published document" and
 * "silently rewrite a quotation attributed to a real person".
 */
export function assertContentPreserved(before: string, after: string): void {
  const a = normalizeForContentComparison(before);
  const b = normalizeForContentComparison(after);
  if (a === b) return;

  // Locate the first divergence so the failure is diagnosable, not just loud.
  const limit = Math.min(a.length, b.length);
  let i = 0;
  while (i < limit && a[i] === b[i]) i++;
  const context = 60;
  const from = Math.max(0, i - context);
  throw new Error(
    [
      "gfm-unwrap: CONTENT CHANGED — refusing to return a corrupted body.",
      `First divergence at normalised offset ${i}.`,
      `  before: …${a.slice(from, i + context)}…`,
      `  after:  …${b.slice(from, i + context)}…`,
    ].join("\n"),
  );
}

export interface UnwrapResult {
  /** The unwrapped text. */
  readonly text: string;
  /** How many source line breaks were removed (0 means nothing was wrapped). */
  readonly joinsPerformed: number;
}

/** The scan's raw output, before the content-preservation invariant runs. */
interface ScanResult {
  readonly out: string[];
  readonly joinsPerformed: number;
  /**
   * `mask[i]` is true when the line break AFTER source line `i` was removed —
   * i.e. line `i + 1` was absorbed into the same joined unit.
   */
  readonly joinedWithNextLineMask: boolean[];
}

/** Everything the line-scanner needs to decide whether a line can be absorbed. */
interface ScanContext {
  readonly lines: readonly string[];
  readonly inFence: readonly boolean[];
  readonly isListContinuation: readonly boolean[];
}

/**
 * True when `lines[index]` may be absorbed into a run opened at quote depth
 * `openDepth`. Extracted so the unwrap loop stays a single flat cursor walk.
 */
function canAbsorb(ctx: ScanContext, index: number, openDepth: number): boolean {
  const next = ctx.lines[index];
  if (ctx.inFence[index] || next.trim() === "") return false;

  const nextQuote = BLOCKQUOTE_PREFIX.exec(next)?.[1] ?? "";
  if (quoteDepth(nextQuote) !== openDepth) return false;

  const nextContent = nextQuote === "" ? next : next.replace(BLOCKQUOTE_PREFIX, "");
  if (nextContent.trim() === "") return false;
  if (isStructuralLine(nextContent, ctx.isListContinuation[index])) return false;
  // A new list item opens a new unit; its own continuation lines do not.
  if (LIST_MARKER.test(nextContent)) return false;
  return true;
}

/**
 * The single cursor walk that decides every join. `unwrapGfmParagraphsDetailed`
 * and `computeJoinedWithNextLineMask` both run THIS function and nothing else,
 * so "which breaks the joiner removes" can never drift from "what the joiner
 * writes". A second predicate that merely tried to predict this walk is exactly
 * the disagreement issue #106 finding 3 is about.
 */
function scanAndJoinGfmParagraphs(body: string): ScanResult {
  const source = body.replace(/\r\n/g, "\n");
  const lines = source.split("\n");
  const inFence = computeFencedCodeLineMask(lines);
  const isListContinuation = computeListContinuationLineMask(lines);
  const ctx: ScanContext = { lines, inFence, isListContinuation };

  // YAML front matter is a data block; its line breaks are significant.
  let frontMatterEndsAt = -1;
  if (lines.length > 0 && isYamlFrontMatterDelimiter(lines[0])) {
    let probe = 1;
    while (probe < lines.length && frontMatterEndsAt === -1) {
      if (isYamlFrontMatterDelimiter(lines[probe])) frontMatterEndsAt = probe;
      probe++;
    }
  }

  const out: string[] = [];
  const joinedWithNextLineMask: boolean[] = Array.from({ length: lines.length }, () => false);
  let joinsPerformed = 0;
  let cursor = 0;

  while (cursor < lines.length) {
    const line = lines[cursor];

    // Emit verbatim: front matter, fenced code, blank lines, structural lines.
    if (
      cursor <= frontMatterEndsAt ||
      inFence[cursor] ||
      line.trim() === "" ||
      isStructuralLine(line, isListContinuation[cursor])
    ) {
      out.push(line);
      cursor++;
      continue;
    }

    // A joinable unit begins here. The blockquote marker run is stripped from
    // every line of the run and re-applied once to the joined result.
    const quotePrefix = BLOCKQUOTE_PREFIX.exec(line)?.[1] ?? "";
    const openDepth = quoteDepth(quotePrefix);
    let accumulated = quotePrefix === "" ? line : line.replace(BLOCKQUOTE_PREFIX, "");

    // A bare `>` line has no content and separates paragraphs inside a quote.
    let scan = accumulated.trim() === "" || hasIntentionalBreak(line) ? -1 : cursor + 1;

    while (scan >= 0 && scan < lines.length && canAbsorb(ctx, scan, openDepth)) {
      const absorbed = lines[scan];
      const content = quotePrefix === "" ? absorbed : absorbed.replace(BLOCKQUOTE_PREFIX, "");
      accumulated = joinWrapped(accumulated, content);
      // The break BETWEEN `scan - 1` and `scan` is the one being removed.
      joinedWithNextLineMask[scan - 1] = true;
      joinsPerformed++;
      cursor = scan;
      scan = hasIntentionalBreak(absorbed) ? -1 : scan + 1;
    }

    out.push(quotePrefix + accumulated);
    cursor++;
  }

  return { out, joinsPerformed, joinedWithNextLineMask };
}

/**
 * Unwrap every hard-wrapped paragraph, list item and blockquote in a GFM body.
 *
 * Pure. Throws only via `assertContentPreserved`, and only when the result
 * would otherwise have been wrong.
 */
export function unwrapGfmParagraphsDetailed(body: string): UnwrapResult {
  const source = body.replace(/\r\n/g, "\n");
  const { out, joinsPerformed } = scanAndJoinGfmParagraphs(source);
  const text = out.join("\n");
  assertContentPreserved(source, text);
  return { text, joinsPerformed };
}

/**
 * Which line breaks this joiner would actually remove: `mask[i]` is true when
 * the break after 0-based source line `i` would be joined away.
 *
 * The detector and the joiner disagree by construction — the detector asks "does
 * this line break mid-sentence", the joiner asks "may I safely join it", and the
 * joiner knows about hand-aligned indented blocks the detector reads as prose
 * (issue #106 finding 3). Consumers use this mask to report only the wraps the
 * joiner would fix, PER WRAP: a file-level "did the joiner make zero joins"
 * test is a no-op on real corpora, because a file almost always contains at
 * least one joinable paragraph alongside its aligned block.
 *
 * Cannot throw: it runs the same scan but skips `assertContentPreserved`, which
 * is a property of the WRITTEN result and irrelevant to a read-only question.
 * A caller that only wants to know which breaks are joinable must never be able
 * to take a content-preservation exception for its trouble.
 */
export function computeJoinedWithNextLineMask(body: string): boolean[] {
  return scanAndJoinGfmParagraphs(body).joinedWithNextLineMask;
}

/** Convenience wrapper returning just the unwrapped text. */
export function unwrapGfmParagraphs(body: string): string {
  return unwrapGfmParagraphsDetailed(body).text;
}
