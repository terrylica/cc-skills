/**
 * Hard-wrap detector (generic, reusable) — pure, dependency-free.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  What hard-wrap detection is, and why it matters
 * ════════════════════════════════════════════════════════════════════════
 *
 * A hard-wrap occurs when prose text is wrapped at a fixed column (e.g., 80
 * or 100 characters) with manual line breaks, then placed in a context that
 * renders those line breaks as `<br>` tags. The result: readers see a column
 * of short mid-sentence lines instead of paragraphs that reflow to their
 * window width.
 *
 * This detector identifies such wraps in two main use cases:
 *
 *   1. GMAIL DRAFTS — the gmail CLI turns every authored newline into an HTML
 *      `<br>` (gmail-drafts.ts `toHtmlBody`) and does not render markdown.
 *      A paragraph wrapped at ~72/80/100 chars becomes "the chopped look"
 *      (columns of short lines instead of flowing prose).
 *
 *   2. GITHUB MARKDOWN — GFM (GitHub Flavored Markdown) renders on any markdown
 *      field (release notes, issue body, PR body, PR/issue comments). A
 *      `\n` at the end of a line becomes an `<br>` visible in the rendered view.
 *      Prose wrapped at ~100 cols becomes columns of short mid-sentence lines.
 *
 * The rule is the same in both: author each paragraph as ONE unbroken line,
 * and let the renderer (email client, web browser) reflow it to the reader's
 * window. Intended breaks (list items, headings, code blocks, blockquotes)
 * are structural and are deliberately NOT flagged.
 *
 * Pure (string in, findings out — no I/O). Fence scanning is delegated to the
 * shared markdown-fence-scanner; shell-command arg extraction to the shared
 * shell-arg-extractor. File reads happen in the consumer hooks.
 */

import { computeFencedCodeLineMask } from "./markdown-fence-scanner.ts";

// ════════════════════════════════════════════════════════════════════════
//  Hard-wrap detection
// ════════════════════════════════════════════════════════════════════════

export interface WrapIssue {
  /** 1-based line number of the line that breaks mid-sentence (line A). */
  readonly line: number;
  /** Trimmed visible width of line A (how wide the wrap point is). */
  readonly width: number;
  /** Short preview of the continuation line B (for the reminder). */
  readonly nextPreview: string;
}

export interface DetectOptions {
  /**
   * Minimum trimmed width for line A to be considered a suspicious wrap point.
   * Below this, a line that "ends open" is treated as a deliberately short line
   * (salutation, sign-off) rather than a machine wrap. Default 50.
   */
  readonly minWrapWidth?: number;
}

const DEFAULT_MIN_WRAP_WIDTH = 50;

/**
 * A markdown table row: trimmed line starts with a pipe.
 * Exported for reuse in literal-markdown detection.
 */
export function isTableRow(rawLine: string): boolean {
  return /^\s*\|/.test(rawLine);
}

/** An ATX heading (`# …` … `###### …`). */
export function isHeading(rawLine: string): boolean {
  return /^ {0,3}#{1,6}\s/.test(rawLine);
}

/** A thematic break (`---`, `***`, `___`, optionally spaced). */
export function isThematicBreak(rawLine: string): boolean {
  const t = rawLine.trim();
  return /^(?:-\s*){3,}$/.test(t) || /^(?:\*\s*){3,}$/.test(t) || /^(?:_\s*){3,}$/.test(t);
}

/** A YAML front matter fence line (`---`). */
export function isYamlFrontMatterDelimiter(rawLine: string): boolean {
  const t = rawLine.trim();
  return t === "---";
}

/**
 * An indented code block: four spaces or a tab. Its line breaks are the code's
 * own, and its lines routinely end without punctuation.
 */
export function isIndentedCodeBlock(rawLine: string): boolean {
  return /^(?: {4,}|\t)\S/.test(rawLine);
}

/**
 * A setext heading underline (`===` or `---` under the heading text). The line
 * ABOVE one of these is a heading, not wrapped prose.
 */
export function isSetextUnderline(rawLine: string): boolean {
  return /^\s{0,3}(?:=+|-+)\s*$/.test(rawLine) && rawLine.trim().length > 0;
}

/**
 * A link reference definition (`[label]: url`) or footnote definition
 * (`[^1]: text`). These stack one per line and end in a URL, so every line
 * looks like an open-ended prose wrap.
 */
export function isReferenceDefinition(rawLine: string): boolean {
  return /^\s{0,3}\[[^\]]+\]:\s/.test(rawLine);
}

/** An HTML block line (`<details>`, `<summary>`, `<br />`, a closing tag…). */
export function isHtmlBlockLine(rawLine: string): boolean {
  return /^\s{0,3}<\/?[A-Za-z!]/.test(rawLine);
}

/**
 * True when `line`, after stripping leading whitespace, begins a NEW structural
 * block element — so a break before it is intentional, not a prose wrap.
 */
function beginsNewStructuralElement(line: string): boolean {
  const t = line.replace(/^\s+/, "");
  if (t === "") return false;
  if (/^[-*+]\s/.test(t)) return true; // unordered list item
  if (/^\d+[.)]\s/.test(t)) return true; // ordered list item
  if (/^#{1,6}\s/.test(t)) return true; // heading
  if (t.startsWith(">")) return true; // blockquote
  if (t.startsWith("|")) return true; // table row
  if (isThematicBreak(line)) return true; // horizontal rule
  if (isSetextUnderline(line)) return true; // the line above is a heading
  if (isReferenceDefinition(line)) return true; // link / footnote definition
  if (isHtmlBlockLine(line)) return true; // raw HTML block
  if (isIndentedCodeBlock(line)) return true; // indented code
  return false;
}

/**
 * Sentence terminators. Includes CJK punctuation: a Chinese paragraph ends on
 * `。`, not `.`, and the operator's corpora are Chinese. Omitting these made
 * every correctly-formed Chinese sentence look like an open-ended wrap.
 */
const CLAUSE_TERMINATORS = ".!?:;。！？；：、）」』】";

/** Line A "ends open" when its last non-space char is not a clause terminator. */
function endsOpen(trimmedEnd: string): boolean {
  if (trimmedEnd === "") return false;
  const last = trimmedEnd[trimmedEnd.length - 1];
  return !CLAUSE_TERMINATORS.includes(last);
}

/**
 * Display columns, not code points. A wrap is a decision about how wide a line
 * LOOKS, and an East Asian character occupies two terminal columns while
 * counting as one `.length`. Measuring `.length` made a Chinese paragraph
 * wrapped at 72 columns read as 36 — under `minWrapWidth`, therefore invisible.
 */
export function displayWidth(text: string): number {
  let width = 0;
  for (const ch of text) {
    const cp = ch.codePointAt(0) ?? 0;
    width += isFullWidthCodePoint(cp) ? 2 : 1;
  }
  return width;
}

/** East Asian Wide / Fullwidth ranges, per Unicode TR11. */
function isFullWidthCodePoint(cp: number): boolean {
  return (
    cp >= 0x1100 &&
    (cp <= 0x115f || // Hangul Jamo
      cp === 0x2329 ||
      cp === 0x232a ||
      (cp >= 0x2e80 && cp <= 0xa4cf && cp !== 0x303f) || // CJK Radicals … Yi
      (cp >= 0xa960 && cp <= 0xa97f) ||
      (cp >= 0xac00 && cp <= 0xd7a3) || // Hangul Syllables
      (cp >= 0xf900 && cp <= 0xfaff) || // CJK Compatibility Ideographs
      (cp >= 0xfe10 && cp <= 0xfe19) ||
      (cp >= 0xfe30 && cp <= 0xfe6f) ||
      (cp >= 0xff00 && cp <= 0xff60) || // Fullwidth forms
      (cp >= 0xffe0 && cp <= 0xffe6) ||
      (cp >= 0x1f300 && cp <= 0x1f64f) || // emoji
      (cp >= 0x1f900 && cp <= 0x1f9ff) ||
      (cp >= 0x20000 && cp <= 0x3fffd))
  );
}

/** A short, single-line preview (whitespace-collapsed, capped). */
function preview(line: string, max = 60): string {
  const collapsed = line.replace(/\s+/g, " ").trim();
  return collapsed.length > max ? collapsed.slice(0, max - 1) + "…" : collapsed;
}

/**
 * Scan a text body and return every hard-wrap (mid-sentence line break in a
 * prose paragraph), ordered by line number. Pure; never throws on normal input.
 */
export function detectHardWraps(body: string, opts: DetectOptions = {}): WrapIssue[] {
  const minWrapWidth = opts.minWrapWidth ?? DEFAULT_MIN_WRAP_WIDTH;
  const lines = body.replace(/\r\n/g, "\n").split("\n");
  const inFence = computeFencedCodeLineMask(lines);

  // Compute YAML front matter bounds (blocks 01-bounded range).
  // Front matter is `---` [content lines] `---`, only at start of file.
  let inYamlFrontMatter = false;
  let yamlFrontMatterEndsAt = -1;
  if (lines.length > 0 && isYamlFrontMatterDelimiter(lines[0])) {
    inYamlFrontMatter = true;
    for (let i = 1; i < lines.length; i++) {
      if (isYamlFrontMatterDelimiter(lines[i])) {
        yamlFrontMatterEndsAt = i;
        break;
      }
    }
  }

  const issues: WrapIssue[] = [];

  for (let i = 0; i < lines.length - 1; i++) {
    // Skip lines inside YAML front matter.
    if (i <= yamlFrontMatterEndsAt) continue;

    const a = lines[i];
    const b = lines[i + 1];
    if (inFence[i] || inFence[i + 1]) continue;
    const aTrimEnd = a.replace(/\s+$/, "");
    if (aTrimEnd === "" || b.trim() === "") continue; // blank ends the block

    // Line A is itself a construct whose break is structural, not a prose wrap.
    if (isTableRow(a) || isHeading(a) || isThematicBreak(a)) continue;
    if (isSetextUnderline(a) || isReferenceDefinition(a)) continue;
    if (isHtmlBlockLine(a) || isIndentedCodeBlock(a)) continue;

    if (!endsOpen(aTrimEnd)) continue;
    const width = displayWidth(aTrimEnd.trim());
    if (width < minWrapWidth) continue;
    if (beginsNewStructuralElement(b)) continue;

    issues.push({ line: i + 1, width, nextPreview: preview(b) });
  }
  return issues;
}
