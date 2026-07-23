/**
 * Markdown table structural detector (SSoT) — pure, dependency-free.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Why this file exists (operator directive 2026-06-28)
 * ════════════════════════════════════════════════════════════════════════
 *
 * LLM-generated GitHub-Flavored-Markdown (GFM) tables routinely break
 * rendering on GitHub and in the VS Code preview. The cause is almost never
 * "misalignment" (GFM ignores whitespace between pipes) — it is STRUCTURAL:
 *
 *   1. An unescaped `|` inside a cell. GFM's table tokenizer treats an
 *      unescaped pipe as a column delimiter EVEN INSIDE a `` `code span` ``,
 *      so a regex/code cell like `` `/days \( | No expiration | Custom` ``
 *      silently inflates that row's cell count. When a row has MORE cells
 *      than the delimiter row, or the header/delimiter counts disagree, the
 *      whole block is demoted to a plain paragraph. The fix — escaping the
 *      pipe as `\|` — changes meaning and so canNOT be auto-applied safely;
 *      Prettier actively CORRUPTS such tables (it bakes in the wrong split,
 *      prettier#10164 / #11410). Hence: detect → remind → human/LLM escapes.
 *
 * This module is the single source of truth for that detection. It is pure
 * (string in, findings out — no I/O, no deps) so it can be shared by the
 * per-edit PostToolUse hook, the Stop-hook prettier gate, and unit tests.
 *
 * ── Severity model ──────────────────────────────────────────────────────
 *
 *   "error"   — table will NOT render, and the fix is NOT auto-fixable by
 *               prettier/markdownlint. The per-edit hook nags ONLY on these.
 *                 • column-overflow       (row has too many cells → unescaped |)
 *                 • header-mismatch       (header cols ≠ delimiter cols)
 *                 • indented-table        (≥4 leading spaces → parsed as code)
 *                 • alignment-colon-in-row(`:--:` token in a body row)
 *
 *   "info"    — already auto-fixed by the existing Stop-hook toolchain
 *               (prettier --write + markdownlint-cli2 --fix). The detector
 *               still reports them (the manual sweep skill shows everything),
 *               but the per-edit hook stays silent to keep signal high.
 *                 • short-row             (row has too few cells → GFM pads)
 *                 • missing-blank-line    (no blank line before/after table)
 *
 * Fenced code blocks (``` / ~~~) are skipped wholesale, so an example of a
 * broken table shown INSIDE a code fence (common in our own CLAUDE.md docs)
 * never trips the detector.
 */

import { computeFencedCodeLineMask } from "./markdown-fence-scanner.ts";

export type TableIssueSeverity = "error" | "info";

export type TableIssueCode =
  | "column-overflow"
  | "header-mismatch"
  | "indented-table"
  | "alignment-colon-in-row"
  | "short-row"
  | "missing-blank-line";

export interface TableIssue {
  /** 1-based line number of the offending row. */
  readonly line: number;
  readonly severity: TableIssueSeverity;
  readonly code: TableIssueCode;
  readonly message: string;
  /** Observed cell count, when the issue is about cell counts. */
  readonly cells?: number;
  /** Expected cell count (delimiter row column count), when relevant. */
  readonly expected?: number;
}

// ────────────────────────────────────────────────────────────────────────
//  Cell tokenization — the heart of GFM-accurate column counting
// ────────────────────────────────────────────────────────────────────────

/**
 * Split a table row into logical cells exactly the way GitHub's parser does:
 * on every `|` that is NOT backslash-escaped. The optional leading/trailing
 * outer pipes are stripped first. Backtick/code-span awareness is deliberately
 * absent — GFM requires `\|` even inside code spans within a table cell, so a
 * raw `|` between backticks IS a delimiter to the real parser. This is the
 * precise behavior that makes the "unescaped pipe in a code span" bug break a
 * table, and matching it is what lets us catch the bug.
 */
export function splitRowIntoCells(rawLine: string): string[] {
  let s = rawLine.trim();
  // Strip ONE unescaped leading pipe.
  if (s.startsWith("|")) s = s.slice(1);
  // Strip ONE unescaped trailing pipe (but not an escaped `\|`).
  if (s.endsWith("|") && !s.endsWith("\\|")) s = s.slice(0, -1);
  // Split on pipes not preceded by a backslash.
  return s.split(/(?<!\\)\|/);
}

/** Count the logical cells in a row (0 when the line contains no pipe). */
function cellCount(rawLine: string): number {
  if (!rawLine.includes("|")) return 0;
  return splitRowIntoCells(rawLine).length;
}

/** A single delimiter cell looks like `---`, `:--`, `--:`, or `:-:`. */
const DELIMITER_CELL_RX = /^\s*:?-+:?\s*$/;

/** A delimiter cell that carries an alignment colon (`:--`, `--:`, `:-:`). */
const ALIGNMENT_COLON_CELL_RX = /^\s*(:-+|:-+:|-+:)\s*$/;

/**
 * True when the line is a GFM table delimiter row: it contains at least one
 * pipe (so a bare `---` thematic-break / setext-underline is NOT mistaken for
 * a delimiter) and every cell is a dash run with optional alignment colons.
 */
export function isDelimiterRow(rawLine: string): boolean {
  const t = rawLine.trim();
  if (!t.includes("|")) return false;
  const cells = splitRowIntoCells(t);
  if (cells.length === 0) return false;
  return cells.every((c) => DELIMITER_CELL_RX.test(c));
}

/** A line that could be the header above a delimiter row. */
function isPotentialHeaderRow(rawLine: string): boolean {
  const t = rawLine.trim();
  if (t === "" || !t.includes("|")) return false;
  return !isDelimiterRow(rawLine);
}

/** ≥4 leading spaces (or a leading tab) → CommonMark indented code block. */
function isIndentedAsCodeBlock(rawLine: string): boolean {
  return /^(?: {4,}|\t)/.test(rawLine);
}

// ────────────────────────────────────────────────────────────────────────
//  Public API — detection
// ────────────────────────────────────────────────────────────────────────

/**
 * Scan markdown content and return every structural table issue found,
 * ordered by line number. Pure: no I/O, never throws on normal input.
 */
export function detectBrokenTables(content: string): TableIssue[] {
  const lines = content.split(/\r?\n/);
  const issues: TableIssue[] = [];

  // First pass: mark which lines are inside a fenced code block (skipped).
  const inFence = computeFencedCodeLineMask(lines);

  let i = 0;
  while (i < lines.length) {
    // A table is a header row immediately followed by a delimiter row.
    const headerIdx = i;
    const delimIdx = i + 1;
    if (
      inFence[headerIdx] ||
      delimIdx >= lines.length ||
      inFence[delimIdx] ||
      !isPotentialHeaderRow(lines[headerIdx]) ||
      !isDelimiterRow(lines[delimIdx])
    ) {
      i++;
      continue;
    }

    const delimCols = cellCount(lines[delimIdx]);
    const headerCols = cellCount(lines[headerIdx]);

    // (1) Indented table → parsed as a code block, won't render at all.
    if (isIndentedAsCodeBlock(lines[headerIdx]) || isIndentedAsCodeBlock(lines[delimIdx])) {
      issues.push({
        line: headerIdx + 1,
        severity: "error",
        code: "indented-table",
        message:
          "table is indented ≥4 spaces and will be parsed as a code block (won't render). Remove the leading indentation.",
      });
    }

    // (2) Header/delimiter column-count mismatch → whole table won't render.
    if (headerCols !== delimCols) {
      issues.push({
        line: delimIdx + 1,
        severity: "error",
        code: "header-mismatch",
        message: `separator row has ${delimCols} column(s) but the header has ${headerCols} — GFM requires them to match or the table will not render. Likely an unescaped \`|\` in the header or a mis-padded separator; escape literal pipes as \\| (required even inside \`code spans\`).`,
        cells: delimCols,
        expected: headerCols,
      });
    }

    // (3) Missing blank line before the header (unless start-of-doc).
    if (headerIdx > 0 && !inFence[headerIdx - 1] && lines[headerIdx - 1].trim() !== "") {
      issues.push({
        line: headerIdx + 1,
        severity: "info",
        code: "missing-blank-line",
        message:
          "no blank line before the table (auto-fixed by the Stop-hook formatter; harmless).",
      });
    }

    // Walk the body rows until a blank line / non-row / fence boundary.
    let j = delimIdx + 1;
    while (j < lines.length && !inFence[j] && lines[j].trim() !== "" && cellCount(lines[j]) > 0) {
      const bodyCols = cellCount(lines[j]);
      const bodyCells = splitRowIntoCells(lines[j]);

      if (bodyCols > delimCols) {
        issues.push({
          line: j + 1,
          severity: "error",
          code: "column-overflow",
          message: `row has ${bodyCols} cells but the table has ${delimCols} column(s) — almost always an unescaped \`|\` inside a cell. Escape literal pipes as \\| (GFM requires this even inside \`code spans\`), or wrap the cell content in backticks AND escape the pipes.`,
          cells: bodyCols,
          expected: delimCols,
        });
      } else if (bodyCols < delimCols) {
        issues.push({
          line: j + 1,
          severity: "info",
          code: "short-row",
          message: `row has ${bodyCols} cells but the table has ${delimCols} column(s); GFM pads the missing cell(s) (markdownlint --fix repairs this).`,
          cells: bodyCols,
          expected: delimCols,
        });
      }

      // (4) A body cell that is itself an alignment token (`:--:`) signals a
      // misplaced/duplicate separator row pasted into the body.
      if (bodyCells.some((c) => ALIGNMENT_COLON_CELL_RX.test(c))) {
        issues.push({
          line: j + 1,
          severity: "error",
          code: "alignment-colon-in-row",
          message:
            "a data row contains an alignment token like `:--:` — alignment colons belong ONLY in the separator row. This row is likely a duplicated/misplaced separator.",
        });
      }
      j++;
    }

    // (5) Missing blank line after the table (unless end-of-doc).
    if (j < lines.length && !inFence[j] && lines[j].trim() !== "") {
      issues.push({
        line: j + 1,
        severity: "info",
        code: "missing-blank-line",
        message:
          "no blank line after the table (auto-fixed by the Stop-hook formatter; harmless).",
      });
    }

    // Resume scanning after this table block.
    i = Math.max(j, delimIdx + 1);
  }

  return issues.toSorted((a, b) => a.line - b.line);
}

/** True when any issue is an "error" (the non-auto-fixable, won't-render kind). */
export function hasTableErrors(issues: readonly TableIssue[]): boolean {
  return issues.some((it) => it.severity === "error");
}

// ────────────────────────────────────────────────────────────────────────
//  Public API — reminder text builder (shared by hook + sweep skill)
// ────────────────────────────────────────────────────────────────────────

/**
 * Build the Claude-visible reminder for a file's table issues. Lists errors
 * first (the actionable, won't-render class), then a one-line note for any
 * info-class issues (which the Stop-hook formatter auto-fixes).
 */
export function buildTableReminder(filePath: string, issues: readonly TableIssue[]): string {
  const errors = issues.filter((it) => it.severity === "error");
  const infos = issues.filter((it) => it.severity === "info");
  const shortPath = filePath.split("/").slice(-2).join("/") || filePath;

  const lines: string[] = [
    `[MD-TABLE-GUARD] Broken table structure in ${shortPath} — will render as raw text on GitHub / VS Code preview:`,
    "",
  ];
  for (const e of errors) {
    lines.push(`  L${e.line}: ${e.message}`);
  }
  if (infos.length > 0) {
    lines.push("");
    lines.push(
      `  (${infos.length} formatting nit(s) on L${infos.map((it) => it.line).join(", L")} are auto-fixed at session exit — no action needed.)`,
    );
  }
  lines.push("");
  lines.push(
    "Fix the pipes/structure above; alignment is then handled automatically. Suppress this file: add a comment containing MD-TABLE-OK.",
  );
  return lines.join("\n");
}
