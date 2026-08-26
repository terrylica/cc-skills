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

try {
  main();
} catch {
  // Fail-open — Stop hook must never block session end
  console.log(JSON.stringify({}));
}
