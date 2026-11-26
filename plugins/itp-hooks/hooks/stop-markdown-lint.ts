#!/usr/bin/env bun
/**
 * Stop hook: markdownlint + prettier for .md files
 *
 * Runs markdownlint-cli2 --fix and prettier --write on .md files
 * that have uncommitted changes (git diff). No PostToolUse gate needed —
 * git is the source of truth for what changed.
 *
 * Non-blocking: outputs additionalContext for Claude visibility.
 * Auto-fixes what it can, reports remaining issues.
 * Fail-open everywhere.
 *
 * A file that prettier would blow up by padding a wide table is left unchanged
 * and reported (Phase 0.75; thresholds below).
 */

import { existsSync, readFileSync } from "node:fs";
import { detectBrokenTables, hasTableErrors } from "./lib/markdown-table-detector.ts";

const MAX_DIAGNOSTIC_LINES = 20;

// --- Wide-table padding guard (Phase 0.75) ---
//
// Prettier aligns a table by padding EVERY cell to the widest cell of its
// column, so a table with a few very long cells turns into mostly spaces. With
// `--prose-wrap preserve` it always prints the aligned form (the compact form
// exists only under `--prose-wrap never`), and nothing bounds the result.
//
// Measured case: one file holding a single table of about 275 rows with a few
// long cells went from 161,149 to 1,322,925 bytes (8.2x, +1,161,776 bytes) in
// one run of this hook while 9 lines of content had changed. It later reached
// 1.69 MB, 83% of it padding; unpadded the same content is 318 KB, and prettier
// on that would produce 3.6 MB (11x).
//
// The rule: a file is left unchanged, and reported, when formatting would BOTH
//
//   - at least double it (OVERSIZE_GROWTH_RATIO): more than half of the
//     formatted file would be padding added by this one run, and
//   - add at least OVERSIZE_MIN_GROWTH_BYTES: small files double all the time
//     and harmlessly (a two-row table of 62 bytes becomes 92; a 1 KB note with
//     one 300-character cell becomes 4 KB), so the ratio alone must not decide.
//
// Both conditions are required. The ratio alone would withhold formatting from
// small notes; the byte count alone would withhold it from a large document
// that grows by a modest fraction. The measured case clears the ratio 4 times
// over and the byte floor 35 times over. Calibration on the other side: with
// every table in this repository's 1,034 tracked .md files stripped of its
// padding, formatting them back trips the rule for none. The largest growth is
// 27,508 bytes, at 1.37x; the largest ratio is 2.69x, at 17,421 bytes.
//
// `.prettierignore` remains the permanent, per-repository opt-out; this guard
// is the default for a repository that has not written one.
export const OVERSIZE_GROWTH_RATIO = 2;
export const OVERSIZE_MIN_GROWTH_BYTES = 32 * 1024;

function collectLines(r: ReturnType<typeof Bun.spawnSync>): string[] {
  return (r.stdout?.toString().trim() || "").split("\n").filter((l) => l.trim());
}

/** A GFM delimiter row (`|---|:--:|`), optionally indented or inside a blockquote. */
function isTableDelimiterRow(line: string): boolean {
  return /^[ \t>|:-]+$/.test(line) && line.includes("|") && line.includes("-");
}

/**
 * Upper bound, in bytes, on how much prettier's table alignment can add to `text`.
 *
 * It decides which files need the measured check at all: a file whose bound is
 * under OVERSIZE_MIN_GROWTH_BYTES cannot trip the rule, so it goes straight to
 * the ordinary `prettier --write` batch at no extra cost (this hook runs at
 * every stop, over every uncommitted .md).
 *
 * Deliberately not a parser, so it cannot disagree with prettier's. For each
 * table (the line above a delimiter row, down to the next blank line) with R
 * rows and at most C columns, an aligned row is the sum of the column widths
 * plus 3 bytes per column plus 1. Each column's widest cell sits in some row,
 * and the cells of one row cannot be longer than that row's line, so the sum of
 * the column widths is at most the sum of the C longest lines. Padding counts
 * display columns, which never exceed UTF-8 bytes. Hence growth is at most
 * R x (sum of the C longest lines + 3C + 1). Lines wrongly taken for table rows
 * only loosen the bound. Formatting outside tables (blank lines around blocks,
 * list markers) is not counted: across the same 1,034 files it never added
 * more than 18 bytes to a file without a table.
 */
export function tablePaddingGrowthUpperBound(text: string): number {
  const lines = text.split(/\r?\n/);
  let bound = 0;
  for (let i = 1; i < lines.length; i++) {
    if (!isTableDelimiterRow(lines[i])) continue;
    let end = i + 1;
    while (end < lines.length && lines[end].trim() !== "") end++;
    const rows = lines.slice(i - 1, end);
    const maxColumns = rows.reduce((max, row) => Math.max(max, row.split("|").length), 0);
    const longestFirst = rows.map((row) => Buffer.byteLength(row)).sort((a, b) => b - a);
    const widestColumnsSum = longestFirst
      .slice(0, Math.min(maxColumns, rows.length))
      .reduce((sum, width) => sum + width, 0);
    bound += rows.length * (widestColumnsSum + 3 * maxColumns + 1);
    i = end;
  }
  return bound;
}

/** True when formatting would both multiply the file and add enough bytes to matter. */
export function isOversizedFormat(originalBytes: number, formattedBytes: number): boolean {
  return (
    formattedBytes >= originalBytes * OVERSIZE_GROWTH_RATIO &&
    formattedBytes - originalBytes >= OVERSIZE_MIN_GROWTH_BYTES
  );
}

/**
 * Size in bytes of what `prettier --write` would leave in `file`, measured by
 * formatting to stdout with the same options; null when prettier fails or
 * times out. Nothing is written.
 */
function measureFormattedBytes(file: string): number | null {
  const r = Bun.spawnSync(["prettier", "--prose-wrap", "preserve", file], {
    stdout: "pipe",
    stderr: "pipe",
    timeout: 10000,
  });
  if (r.exitCode !== 0) return null;
  return r.stdout?.length ?? null;
}

function main(): void {
  // Find .md files with uncommitted changes (staged + unstaged)
  const gitResult = Bun.spawnSync(
    ["git", "diff", "--name-only", "--diff-filter=ACMR", "HEAD", "--", "*.md"],
    { stdout: "pipe", stderr: "pipe", timeout: 5000 },
  );

  // Also check staged-only (for new files not yet committed)
  const gitStagedResult = Bun.spawnSync(
    ["git", "diff", "--name-only", "--cached", "--diff-filter=ACMR", "--", "*.md"],
    { stdout: "pipe", stderr: "pipe", timeout: 5000 },
  );

  // Also check untracked .md files
  const gitUntrackedResult = Bun.spawnSync(
    ["git", "ls-files", "--others", "--exclude-standard", "--", "*.md"],
    { stdout: "pipe", stderr: "pipe", timeout: 5000 },
  );

  const allFiles = [
    ...collectLines(gitResult),
    ...collectLines(gitStagedResult),
    ...collectLines(gitUntrackedResult),
  ];

  // Deduplicate and filter to existing files
  const editedFiles = [...new Set(allFiles)].filter((f) => existsSync(f));

  if (editedFiles.length === 0) {
    console.log(JSON.stringify({}));
    return;
  }

  const messages: string[] = [];

  // --- Phase 0: gate out structurally-broken tables ---
  // Prettier reparses tables and would BAKE IN the wrong column split when a
  // cell has an unescaped `|` (prettier#10164 / #11410) — turning a fixable
  // table into a corrupted one. So NEVER auto-format a file with a
  // render-breaking table error; report it for a pipe-escape fix instead, and
  // only format the structurally-clean files.
  const cleanFiles: string[] = [];
  for (const f of editedFiles) {
    let tableErrors = false;
    let errorLineLabels = "";
    try {
      const issues = detectBrokenTables(readFileSync(f, "utf8"));
      tableErrors = hasTableErrors(issues);
      errorLineLabels = issues
        .filter((it) => it.severity === "error")
        .map((it) => `L${it.line}`)
        .join(", ");
    } catch {
      // Unreadable → treat as clean (fail-open; the formatter will cope/skip).
    }
    if (tableErrors) {
      messages.push(
        `${f}: SKIPPED auto-format — broken table at ${errorLineLabels}. Fix the structure first (escape literal pipes as \\|, even inside \`code spans\`); prettier is gated off this file so it can't bake in the wrong column split.`,
      );
    } else {
      cleanFiles.push(f);
    }
  }

  const hasPrettier =
    Bun.spawnSync(["which", "prettier"], { stdout: "pipe", stderr: "pipe" }).exitCode === 0;

  // --- Phase 0.5: honour the repo's .prettierignore for BOTH formatters ---
  //
  // Phase 1 reads `.prettierignore` for free because prettier does it. Phase 2
  // did NOT: markdownlint-cli2 has no --ignore-path, it honours only its own
  // config, and most repos carry none — so a repo that declared "this content
  // is archival evidence, never format it" was obeyed by one formatter and
  // silently overruled by the other.
  //
  // That asymmetry corrupted a real archive. A repo whose `.prettierignore`
  // excluded a generated-content directory had prettier duly skip it, and then
  // markdownlint-cli2 --fix rewrote 97 freshly-generated, still-untracked files
  // AFTER the generating pipeline had hashed them into a checksum manifest.
  // Not cosmetically: 139 content mutations across 29 files, including MD029
  // ordered-list renumbering that destroyed OCR'd numerals (`- 10790.` was
  // rewritten to `- 1.`). Adding the ignore file had closed exactly half the
  // hole; this closes the other half.
  //
  // Note for anyone reproducing this: markdownlint's fixer is not stable across
  // patch releases. Of the 53 files reconstructible byte-exactly, cli2 0.23.0
  // reproduced all 53, 0.23.2 reproduced 51, and 0.22.x missed a different one.
  //
  // Filtering the FILE LIST rather than passing a flag is deliberate — it is
  // tool-agnostic, so any formatter added to this hook later inherits it.
  // `prettier --file-info` is used as the oracle so both phases agree on what
  // "ignored" means by construction, rather than by a hand-rolled matcher.
  let formatFiles = cleanFiles;
  if (cleanFiles.length > 0) {
    const rootResult = Bun.spawnSync(["git", "rev-parse", "--show-toplevel"], {
      stdout: "pipe",
      stderr: "pipe",
      timeout: 5000,
    });
    const repoRoot = rootResult.stdout?.toString().trim() || "";
    const ignorePath = repoRoot ? `${repoRoot}/.prettierignore` : "";

    if (ignorePath && existsSync(ignorePath) && hasPrettier) {
      const kept: string[] = [];
      let skipped = 0;
      for (const f of cleanFiles) {
        const info = Bun.spawnSync(
          ["prettier", "--file-info", f, "--ignore-path", ignorePath],
          { stdout: "pipe", stderr: "pipe", timeout: 5000 },
        );
        let ignored = false;
        try {
          ignored = JSON.parse(info.stdout?.toString() || "{}").ignored === true;
        } catch {
          ignored = false; // unparseable -> format it, matching prior behaviour
        }
        if (ignored) skipped++;
        else kept.push(f);
      }
      formatFiles = kept;
      if (skipped > 0) {
        messages.push(
          `ignore: skipped ${skipped} file(s) per .prettierignore — applies to markdownlint too, not just prettier`,
        );
      }
    }
  }

  // --- Phase 0.75: leave alone a file that formatting would blow up ---
  // Only a file whose tables COULD add OVERSIZE_MIN_GROWTH_BYTES is measured
  // (one extra prettier run, to a buffer). A file withheld here is withheld
  // from markdownlint --fix too, so it is left exactly as it was.
  if (hasPrettier && formatFiles.length > 0) {
    const kept: string[] = [];
    for (const f of formatFiles) {
      let original: Buffer;
      try {
        original = readFileSync(f);
      } catch {
        kept.push(f); // unreadable -> prior behaviour (prettier reports it)
        continue;
      }
      if (tablePaddingGrowthUpperBound(original.toString("utf8")) < OVERSIZE_MIN_GROWTH_BYTES) {
        kept.push(f);
        continue;
      }
      const formattedBytes = measureFormattedBytes(f);
      if (formattedBytes === null) {
        messages.push(
          `${f}: SKIPPED auto-format — it has a wide table and prettier could not format it to a buffer to measure the result, so the file is left unchanged. To exempt it permanently, list it in .prettierignore.`,
        );
      } else if (isOversizedFormat(original.length, formattedBytes)) {
        messages.push(
          `${f}: SKIPPED auto-format — prettier would grow it from ${original.length} to ${formattedBytes} bytes (${(formattedBytes / original.length).toFixed(1)}x) by padding every table cell to its column's widest. The file is left unchanged (markdownlint --fix withheld too). To exempt it permanently, list it in .prettierignore; to accept the padding, run prettier on it by hand.`,
        );
      } else {
        kept.push(f);
      }
    }
    formatFiles = kept;
  }

  // --- Phase 1: prettier --write (auto-fix formatting) ---
  if (hasPrettier && formatFiles.length > 0) {
    const prettierResult = Bun.spawnSync(
      ["prettier", "--write", "--prose-wrap", "preserve", ...formatFiles],
      { stdout: "pipe", stderr: "pipe", timeout: 10000 },
    );

    if (prettierResult.exitCode === 0) {
      messages.push(`prettier: auto-formatted ${formatFiles.length} file(s)`);
    } else {
      const stderr = prettierResult.stderr?.toString().trim() || "";
      if (stderr) {
        messages.push(`prettier: warnings\n${truncate(stderr)}`);
      }
    }
  }

  // --- Phase 2: markdownlint-cli2 --fix (auto-fix lint issues) ---
  const hasMarkdownlint =
    Bun.spawnSync(["which", "markdownlint-cli2"], { stdout: "pipe", stderr: "pipe" }).exitCode === 0;

  if (hasMarkdownlint && formatFiles.length > 0) {
    // First pass: auto-fix
    Bun.spawnSync(["markdownlint-cli2", "--fix", ...formatFiles], {
      stdout: "pipe",
      stderr: "pipe",
      timeout: 10000,
    });

    // Second pass: report remaining issues
    const lintResult = Bun.spawnSync(["markdownlint-cli2", ...formatFiles], {
      stdout: "pipe",
      stderr: "pipe",
      timeout: 10000,
    });

    if (lintResult.exitCode !== 0) {
      const stdout = lintResult.stdout?.toString().trim() || "";
      const stderr = lintResult.stderr?.toString().trim() || "";
      const output = stdout || stderr;

      if (output) {
        const lines = output.split("\n").filter((l) => l.trim());
        messages.push(
          `markdownlint: ${lines.length} issue(s) remaining after auto-fix\n${truncate(output)}`,
        );
      }
    } else {
      messages.push("markdownlint: all issues auto-fixed");
    }
  }

  // Note: no early-return when neither formatter is installed — a broken-table
  // skip notice (Phase 0) must still be surfaced even without prettier/markdownlint.
  if (messages.length === 0) {
    console.log(JSON.stringify({}));
    return;
  }

  const summary = `[MARKDOWN-LINT] Session exit — ${editedFiles.length} .md file(s) processed:\n\n${messages.join("\n\n")}`;
  console.log(JSON.stringify({ additionalContext: summary }));
}

function truncate(text: string): string {
  const lines = text.split("\n");
  if (lines.length > MAX_DIAGNOSTIC_LINES) {
    return (
      lines.slice(0, MAX_DIAGNOSTIC_LINES).join("\n") +
      `\n... (${lines.length} total, showing first ${MAX_DIAGNOSTIC_LINES})`
    );
  }
  return text;
}

// Run only as a script (the Stop orchestrator spawns this file); importing it
// for its helpers, as the tests do, must not format anything.
if (import.meta.main) {
  try {
    main();
  } catch {
    // Fail-open — Stop hook must never block session end
    console.log(JSON.stringify({}));
  }
}
