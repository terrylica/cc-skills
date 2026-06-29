# Detection algorithm & rationale

## Why this exists

LLM-generated GFM tables routinely render as raw text on GitHub / VS Code
preview. The cause is **structural**, not cosmetic — GFM ignores the whitespace
between pipes, so a ragged, unaligned table renders identically to a perfectly
padded one. What actually breaks rendering:

1. **Unescaped `|` inside a cell** (the dominant cause). GFM's table tokenizer
   counts every unescaped `|` as a column delimiter — **even inside a
   `` `code span` ``**. A cell like `` `/days \( | No expiration | Custom` ``
   therefore reports far more columns than the header declares, and GitHub
   demotes the whole block to a paragraph. The fix is to escape each literal
   pipe as `\|` (or `&#124;`). Because escaping _changes meaning_, no formatter
   applies it automatically; Prettier in fact mis-parses such a cell and bakes
   the wrong column split into its output (prettier#10164, prettier#11410).
2. **Header/separator column-count mismatch.** GFM requires the header row and
   the delimiter row to have the same number of cells; otherwise the table is
   not recognized at all.
3. **Indentation ≥4 spaces.** CommonMark parses a 4-space-indented block as a
   code block, so the "table" never becomes a `<table>`.
4. **Alignment colons in a data row.** `:--:` style tokens belong only in the
   separator row; finding one in the body signals a duplicated/misplaced
   separator.

Short rows (too few cells) and missing blank lines around a table are
**auto-fixable** by `prettier` / `markdownlint-cli2 --fix`, so they are reported
as `info` only.

## Algorithm

1. **Mask fenced code blocks.** Track ` ``` ` / `~~~` fences (indented <4 spaces)
   and skip every line inside them, so an example broken table shown inside a
   doc's code fence is never flagged.
2. **Find table blocks.** A table is a _header row_ (a non-fenced line with an
   unescaped `|` that is not itself a delimiter) immediately followed by a
   _delimiter row_.
3. **Delimiter row test.** The line contains at least one `|` (so a bare `---`
   thematic break / setext underline is not mistaken for a delimiter) and every
   cell matches `^\s*:?-+:?\s*$`.
4. **Cell counting (GFM-accurate).** Trim the row, strip one unescaped outer
   pipe on each side, then split on `/(?<!\\)\|/` — every pipe **not** preceded
   by a backslash. No backtick/code-span special-casing: GFM requires `\|` even
   inside code spans, so a raw `|` between backticks _is_ a delimiter, which is
   exactly the bug we catch.
5. **Compare counts.** Header≠delimiter → `header-mismatch`; a body row with
   more cells than the delimiter → `column-overflow`; fewer → `short-row` (info).
6. **Extra checks.** ≥4-space indent → `indented-table`; a body cell matching
   `^\s*(:-+|:-+:|-+:)\s*$` → `alignment-colon-in-row`; non-blank line
   immediately before/after the table → `missing-blank-line` (info).

## `--fix` heuristic

For a `column-overflow` row, keep the first `expectedCols − 1` interior pipes as
real delimiters and backslash-escape every interior pipe after that (outer
leading/trailing pipes preserved, edits applied right-to-left to keep indices
valid). This assumes the literal pipes live in the **last** column — true for the
common "regex/code in the final cell" case — but it can guess wrong when a pipe
was a genuinely missing delimiter, so the diff must be reviewed.

## SSoT / parity

The detection core here is a self-contained copy of
`plugins/itp-hooks/hooks/lib/markdown-table-detector.ts` (skills install to
`~/.claude/skills/` where that sibling path is unavailable). The two copies are
pinned to parity by a shared fixture corpus in each plugin's tests; keep them in
sync when editing either.
