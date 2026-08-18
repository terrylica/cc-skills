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
  return false;
}

/** Line A "ends open" when its last non-space char is not a clause terminator. */
function endsOpen(trimmedEnd: string): boolean {
  if (trimmedEnd === "") return false;
  const last = trimmedEnd[trimmedEnd.length - 1];
  return !".!?:;".includes(last);
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

    if (isTableRow(a) || isHeading(a) || isThematicBreak(a)) continue;
    if (!endsOpen(aTrimEnd)) continue;
    if (aTrimEnd.trim().length < minWrapWidth) continue;
    if (beginsNewStructuralElement(b)) continue;

    issues.push({ line: i + 1, width: aTrimEnd.trim().length, nextPreview: preview(b) });
  }
  return issues;
}
