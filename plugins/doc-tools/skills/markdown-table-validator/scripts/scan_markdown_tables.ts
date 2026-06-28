#!/usr/bin/env bun
/**
 * scan_markdown_tables.ts — repo-wide GFM table structural validator + opt-in fixer.
 *
 * Detects the structural problems that demote a Markdown table to raw text on
 * GitHub / VS Code preview — unescaped `|` inside a cell (the #1 LLM-table bug),
 * header/separator column mismatch, indented (code-block) tables, and alignment
 * tokens pasted into a data row — plus the auto-fixable info nits (short rows,
 * missing blank lines).
 *
 * SSoT NOTE: the detection algorithm is intentionally a self-contained copy of
 * plugins/itp-hooks/hooks/lib/markdown-table-detector.ts. The hook lib can't be
 * imported here because skills install to ~/.claude/skills/ where that sibling
 * path doesn't exist. The two copies are pinned to parity by a shared fixture
 * corpus in each plugin's tests — keep them in sync when editing either.
 *
 * Usage:
 *   bun scan_markdown_tables.ts <file-or-glob>...        # report (exit 1 on errors)
 *   bun scan_markdown_tables.ts --fix <file-or-glob>...  # also escape over-count pipes
 *   bun scan_markdown_tables.ts --quiet ...              # suppress the per-file "clean" line
 *
 * Output: compiler-style `path:line: severity: message`. Exit 0 when no ERROR
 * remains (info nits don't fail the run), 1 otherwise.
 *
 * --fix heuristic (review the diff!): in a row with MORE cells than the header,
 * the genuine columns are assumed to be the FIRST N; every pipe beyond column N
 * is treated as literal and escaped as `\|`. This exactly fixes the common case
 * (regex/code in the last cell) but can guess wrong when a pipe was a genuinely
 * missing delimiter — always review before committing.
 */

import { Glob } from "bun";

// ────────────────────────────────────────────────────────────────────────
//  Detection core (mirror of itp-hooks/hooks/lib/markdown-table-detector.ts)
// ────────────────────────────────────────────────────────────────────────

type Severity = "error" | "info";
interface Issue {
  line: number;
  severity: Severity;
  code: string;
  message: string;
}

const DELIMITER_CELL_RX = /^\s*:?-+:?\s*$/;
const ALIGNMENT_COLON_CELL_RX = /^\s*(:-+|:-+:|-+:)\s*$/;

function splitRowIntoCells(rawLine: string): string[] {
  let s = rawLine.trim();
  if (s.startsWith("|")) s = s.slice(1);
  if (s.endsWith("|") && !s.endsWith("\\|")) s = s.slice(0, -1);
  return s.split(/(?<!\\)\|/);
}

function cellCount(rawLine: string): number {
  if (!rawLine.includes("|")) return 0;
  return splitRowIntoCells(rawLine).length;
}

function isDelimiterRow(rawLine: string): boolean {
  const t = rawLine.trim();
  if (!t.includes("|")) return false;
  const cells = splitRowIntoCells(t);
  if (cells.length === 0) return false;
  return cells.every((c) => DELIMITER_CELL_RX.test(c));
}

function isPotentialHeaderRow(rawLine: string): boolean {
  const t = rawLine.trim();
  if (t === "" || !t.includes("|")) return false;
  return !isDelimiterRow(rawLine);
}

function isIndentedAsCodeBlock(rawLine: string): boolean {
  return /^(?: {4,}|\t)/.test(rawLine);
}

function fenceMarkerOf(rawLine: string): { char: string; len: number } | null {
  const m = rawLine.match(/^( {0,3})(`{3,}|~{3,})/);
  if (!m) return null;
  return { char: m[2][0], len: m[2].length };
}

function computeFenceMask(lines: string[]): boolean[] {
  const inFence: boolean[] = Array.from({ length: lines.length }, () => false);
  let openFence: { char: string; len: number } | null = null;
  for (let i = 0; i < lines.length; i++) {
    const fence = fenceMarkerOf(lines[i]);
    if (fence) {
      if (!openFence) {
        openFence = fence;
        inFence[i] = true;
        continue;
      }
      if (fence.char === openFence.char && fence.len >= openFence.len) {
        inFence[i] = true;
        openFence = null;
        continue;
      }
    }
    inFence[i] = openFence !== null;
  }
  return inFence;
}

function detectBrokenTables(content: string): Issue[] {
  const lines = content.split(/\r?\n/);
  const inFence = computeFenceMask(lines);
  const issues: Issue[] = [];

  let i = 0;
  while (i < lines.length) {
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

    if (isIndentedAsCodeBlock(lines[headerIdx]) || isIndentedAsCodeBlock(lines[delimIdx])) {
      issues.push({
        line: headerIdx + 1,
        severity: "error",
        code: "indented-table",
        message: "table is indented ≥4 spaces and will be parsed as a code block (won't render).",
      });
    }
    if (headerCols !== delimCols) {
      issues.push({
        line: delimIdx + 1,
        severity: "error",
        code: "header-mismatch",
        message: `separator row has ${delimCols} column(s) but the header has ${headerCols} — they must match or the table will not render (escape literal pipes as \\|).`,
      });
    }
    if (headerIdx > 0 && !inFence[headerIdx - 1] && lines[headerIdx - 1].trim() !== "") {
      issues.push({
        line: headerIdx + 1,
        severity: "info",
        code: "missing-blank-line",
        message: "no blank line before the table (formatter auto-fixes).",
      });
    }

    let j = delimIdx + 1;
    while (j < lines.length && !inFence[j] && lines[j].trim() !== "" && cellCount(lines[j]) > 0) {
      const bodyCols = cellCount(lines[j]);
      if (bodyCols > delimCols) {
        issues.push({
          line: j + 1,
          severity: "error",
          code: "column-overflow",
          message: `row has ${bodyCols} cells but the table has ${delimCols} column(s) — almost always an unescaped \`|\` in a cell (escape as \\|, even inside \`code spans\`).`,
        });
      } else if (bodyCols < delimCols) {
        issues.push({
          line: j + 1,
          severity: "info",
          code: "short-row",
          message: `row has ${bodyCols} cells but the table has ${delimCols} column(s); GFM pads (markdownlint --fix repairs).`,
        });
      }
      if (splitRowIntoCells(lines[j]).some((c) => ALIGNMENT_COLON_CELL_RX.test(c))) {
        issues.push({
          line: j + 1,
          severity: "error",
          code: "alignment-colon-in-row",
          message: "alignment token like `:--:` in a data row — colons belong only in the separator row.",
        });
      }
      j++;
    }
    if (j < lines.length && !inFence[j] && lines[j].trim() !== "") {
      issues.push({
        line: j + 1,
        severity: "info",
        code: "missing-blank-line",
        message: "no blank line after the table (formatter auto-fixes).",
      });
    }
    i = Math.max(j, delimIdx + 1);
  }
  return issues.toSorted((a, b) => a.line - b.line);
}

// ────────────────────────────────────────────────────────────────────────
//  --fix: escape over-count pipes in a single row (keep first N columns)
// ────────────────────────────────────────────────────────────────────────

/** Indices of unescaped `|` chars in `raw`. */
function unescapedPipeIndices(raw: string): number[] {
  const idx: number[] = [];
  for (let k = 0; k < raw.length; k++) {
    if (raw[k] === "|" && raw[k - 1] !== "\\") idx.push(k);
  }
  return idx;
}

/**
 * Escape the EXCESS pipes in an over-count row: keep the first `expectedCols`
 * columns (i.e. the first `expectedCols - 1` interior delimiters) and backslash
 * every interior pipe after that. Outer leading/trailing pipes are preserved.
 * Returns the rewritten line, or the original when nothing needs escaping.
 */
function escapeExcessPipesInRow(raw: string, expectedCols: number): string {
  const pipes = unescapedPipeIndices(raw);
  if (pipes.length === 0) return raw;

  const trimmedStart = raw.length - raw.trimStart().length;
  const trimmedEndIdx = raw.trimEnd().length - 1;
  const hasLeadingOuter = pipes[0] === trimmedStart;
  const hasTrailingOuter = pipes[pipes.length - 1] === trimmedEndIdx;

  const interior = pipes.filter(
    (p) => !(hasLeadingOuter && p === pipes[0]) && !(hasTrailingOuter && p === pipes[pipes.length - 1]),
  );
  // Keep the first (expectedCols - 1) interior delimiters; escape the rest.
  const keep = Math.max(0, expectedCols - 1);
  const toEscape = interior.slice(keep);
  if (toEscape.length === 0) return raw;

  // Insert backslashes right-to-left so earlier indices stay valid.
  let out = raw;
  for (const pos of toEscape.toSorted((a, b) => b - a)) {
    out = `${out.slice(0, pos)}\\${out.slice(pos)}`;
  }
  return out;
}

function applyFixes(content: string): { fixed: string; count: number } {
  const lines = content.split(/\r?\n/);
  const inFence = computeFenceMask(lines);
  let count = 0;
  let i = 0;
  while (i < lines.length) {
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
    let j = delimIdx + 1;
    while (j < lines.length && !inFence[j] && lines[j].trim() !== "" && cellCount(lines[j]) > 0) {
      if (cellCount(lines[j]) > delimCols) {
        const fixed = escapeExcessPipesInRow(lines[j], delimCols);
        if (fixed !== lines[j]) {
          lines[j] = fixed;
          count++;
        }
      }
      j++;
    }
    i = Math.max(j, delimIdx + 1);
  }
  return { fixed: lines.join("\n"), count };
}

// ────────────────────────────────────────────────────────────────────────
//  CLI
// ────────────────────────────────────────────────────────────────────────

async function expandArgsToFiles(patterns: string[]): Promise<string[]> {
  const files = new Set<string>();
  for (const pattern of patterns) {
    if (pattern.includes("*")) {
      const glob = new Glob(pattern);
      for await (const f of glob.scan(".")) files.add(f);
    } else {
      files.add(pattern);
    }
  }
  return [...files].filter((f) => /\.(?:md|markdown)$/i.test(f));
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  const fix = argv.includes("--fix");
  const quiet = argv.includes("--quiet");
  const patterns = argv.filter((a) => !a.startsWith("--"));

  if (patterns.length === 0) {
    console.error("usage: scan_markdown_tables.ts [--fix] [--quiet] <file-or-glob>...");
    process.exit(2);
  }

  const files = await expandArgsToFiles(patterns);
  if (files.length === 0) {
    console.error("No .md/.markdown files matched.");
    process.exit(2);
  }

  let totalErrors = 0;
  let totalFixed = 0;

  for (const file of files) {
    let content: string;
    try {
      content = await Bun.file(file).text();
    } catch {
      console.error(`${file}: error: cannot read file`);
      totalErrors++;
      continue;
    }

    if (fix) {
      const { fixed, count } = applyFixes(content);
      if (count > 0) {
        await Bun.write(file, fixed);
        content = fixed;
        totalFixed += count;
        console.log(`${file}: fixed ${count} over-count row(s) by escaping excess pipes (review the diff).`);
      }
    }

    const issues = detectBrokenTables(content);
    for (const it of issues) {
      console.log(`${file}:${it.line}: ${it.severity}: ${it.message} [${it.code}]`);
      if (it.severity === "error") totalErrors++;
    }
    if (!quiet && issues.length === 0) {
      console.log(`${file}: ok`);
    }
  }

  if (fix && totalFixed > 0) {
    console.log(`\n${totalFixed} row(s) auto-escaped. Review, then run prettier to re-align.`);
  }
  if (totalErrors > 0) {
    console.log(`\n${totalErrors} error(s) remain — escape literal pipes as \\| (works even inside \`code spans\`).`);
  }
  process.exit(totalErrors > 0 ? 1 : 0);
}

void main();
