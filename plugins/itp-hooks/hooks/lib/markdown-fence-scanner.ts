/**
 * Markdown fenced-code scanner (SSoT) — pure, dependency-free.
 *
 * A single home for "which lines of a markdown/text document are inside a
 * fenced code block (``` or ~~~)". Any content-scanning hook that must NOT
 * treat fenced example text as real markdown (broken tables shown in a doc,
 * an email body pasted into a code fence, …) computes its skip-mask here
 * instead of re-implementing the fence state machine.
 *
 * Extracted 2026-07-22 from `markdown-table-detector.ts`, whose private copy
 * was byte-identical to the copy in `gmail-body-detector.ts`. Both now consume
 * this module. Consumers: markdown-table-detector, gmail-body-detector,
 * escape-hatch-marker-detection, and (with `blockquotes: true`, so they agree
 * on what a quoted fence is) hard-wrap-detector and gfm-unwrap.
 *
 * CommonMark note: a fence marker is 3+ backticks/tildes indented < 4 spaces;
 * a closing fence must use the same character and be at least as long as the
 * opener. Info strings after the opener are ignored (they never close a fence).
 */

/**
 * Parse a line's leading fence marker. Returns the fence `char` (`` ` `` or
 * `~`) and its run `len`, or `null` when the line does not open/close a fence.
 * Indented ≥ 4 spaces → not a fence (that is an indented code block).
 */
export function fenceMarkerOf(rawLine: string): { char: string; len: number } | null {
  const m = rawLine.match(/^( {0,3})(`{3,}|~{3,})/);
  if (!m) return null;
  return { char: m[2][0], len: m[2].length };
}

/** One GFM block quote marker: 0-3 spaces, `>`, and one optional space. */
const BLOCKQUOTE_MARKER = /^ {0,3}>[ \t]?/;

/**
 * Strip up to `maxDepth` leading block quote markers. Returns how many were
 * stripped and the quoted content that remains.
 */
function stripBlockquoteMarkers(rawLine: string, maxDepth: number): { depth: number; content: string } {
  let depth = 0;
  let content = rawLine;
  for (let marker = BLOCKQUOTE_MARKER.exec(content); marker && depth < maxDepth; marker = BLOCKQUOTE_MARKER.exec(content)) {
    content = content.slice(marker[0].length);
    depth++;
  }
  return { depth, content };
}

export interface FenceMaskOptions {
  /**
   * Track fences inside block quotes (GFM: a quote's content is parsed as
   * blocks in its own right, so `> ```` opens a fence). A fence belongs to the
   * quote depth it opened at; a line with fewer markers ends that quote, and
   * ending the quote closes the fence. Off by default, which keeps every other
   * consumer's mask byte-identical.
   */
  readonly blockquotes?: boolean;
}

/**
 * Given a document's lines, return a boolean mask where `mask[i]` is true when
 * line `i` is inside (or is the opening/closing fence line of) a fenced code
 * block. Pure; never throws on normal input.
 *
 * Semantics (must stay identical for all consumers):
 *   - The opening fence line and the closing fence line are BOTH masked true.
 *   - A closing fence must match the opener's character and be ≥ its length;
 *     otherwise the line is treated as ordinary content inside the block.
 *   - An unterminated fence masks every line to end-of-document (with
 *     `blockquotes`, to the end of the quote it opened in).
 */
export function computeFencedCodeLineMask(lines: readonly string[], opts: FenceMaskOptions = {}): boolean[] {
  const maxDepth = opts.blockquotes === true ? Number.POSITIVE_INFINITY : 0;
  const inFence: boolean[] = Array.from({ length: lines.length }, () => false);
  let openFence: { char: string; len: number; depth: number } | null = null;
  for (let i = 0; i < lines.length; i++) {
    // Inside an open fence strip only ITS quote's markers: a deeper `>` is code.
    let quoted = stripBlockquoteMarkers(lines[i], openFence ? openFence.depth : maxDepth);
    if (openFence && quoted.depth < openFence.depth) {
      // The quote holding the fence ended, and that closes the fence (GFM).
      openFence = null;
      quoted = stripBlockquoteMarkers(lines[i], maxDepth);
    }
    const fence = fenceMarkerOf(quoted.content);
    if (fence) {
      if (!openFence) {
        openFence = { ...fence, depth: quoted.depth };
        inFence[i] = true; // the opening fence line itself
        continue;
      }
      if (fence.char === openFence.char && fence.len >= openFence.len) {
        inFence[i] = true; // the closing fence line itself
        openFence = null;
        continue;
      }
    }
    inFence[i] = openFence !== null;
  }
  return inFence;
}
