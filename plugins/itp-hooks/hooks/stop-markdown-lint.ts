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
 */

import { existsSync, readFileSync } from "node:fs";
import { detectBrokenTables, hasTableErrors } from "./lib/markdown-table-detector.ts";

const MAX_DIAGNOSTIC_LINES = 20;

function collectLines(r: ReturnType<typeof Bun.spawnSync>): string[] {
  return (r.stdout?.toString().trim() || "").split("\n").filter((l) => l.trim());
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

  // --- Phase 1: prettier --write (auto-fix formatting) ---
  const hasPrettier =
    Bun.spawnSync(["which", "prettier"], { stdout: "pipe", stderr: "pipe" }).exitCode === 0;

  if (hasPrettier && cleanFiles.length > 0) {
    const prettierResult = Bun.spawnSync(
      ["prettier", "--write", "--prose-wrap", "preserve", ...cleanFiles],
      { stdout: "pipe", stderr: "pipe", timeout: 10000 },
    );

    if (prettierResult.exitCode === 0) {
      messages.push(`prettier: auto-formatted ${cleanFiles.length} file(s)`);
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

  if (hasMarkdownlint && cleanFiles.length > 0) {
    // First pass: auto-fix
    Bun.spawnSync(["markdownlint-cli2", "--fix", ...cleanFiles], {
      stdout: "pipe",
      stderr: "pipe",
      timeout: 10000,
    });

    // Second pass: report remaining issues
    const lintResult = Bun.spawnSync(["markdownlint-cli2", ...cleanFiles], {
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

try {
  main();
} catch {
  // Fail-open — Stop hook must never block session end
  console.log(JSON.stringify({}));
}
