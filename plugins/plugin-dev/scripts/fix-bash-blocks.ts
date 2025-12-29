#!/usr/bin/env bun
/**
 * fix-bash-blocks.ts - Automated heredoc wrapper application
 *
 * Adds heredoc wrappers to bash code blocks that need them for zsh compatibility.
 * Generates context-aware EOF markers based on block content.
 *
 * Usage:
 *   bun run scripts/fix-bash-blocks.ts <path>        # Fix files in path
 *   bun run scripts/fix-bash-blocks.ts <path> --dry  # Preview changes only
 *
 * ADR: /docs/adr/2025-12-06-shell-command-portability-zsh.md
 */

import { existsSync, readFileSync, writeFileSync, readdirSync, statSync } from "fs";
import { join, resolve, basename } from "path";
import { Glob } from "bun";
import { green, yellow, cyan, dim, red } from "ansis";

import {
  hasBashSpecificSyntax,
  hasHeredocWrapper,
  isDocExample,
  BASH_CODE_BLOCK,
} from "./lib/patterns.js";
import { EOF_MARKER_PATTERNS, DEFAULT_EOF_SUFFIX, SKIP_DIRECTORIES, FILE_ENCODING } from "./lib/constants.js";
import { logError, fatalError } from "./lib/output.js";

// ============================================================================
// EOF Marker Generation
// ============================================================================

/**
 * Generate descriptive EOF marker based on content
 */
function generateEofMarker(block: string, filepath: string): string {
  const blockLower = block.toLowerCase();

  // Try to infer purpose from content
  for (const [keyword, marker] of Object.entries(EOF_MARKER_PATTERNS)) {
    if (blockLower.includes(keyword)) {
      return marker;
    }
  }

  // Fall back to file-based marker
  const stem = basename(filepath, ".md")
    .toUpperCase()
    .replace(/-/g, "_")
    .replace(/[^A-Z0-9_]/g, "");

  return `${stem}${DEFAULT_EOF_SUFFIX}`;
}

/**
 * Wrap bash block with heredoc
 */
function wrapBlock(block: string, eofMarker: string): string {
  // Ensure block ends with newline
  const normalizedBlock = block.endsWith("\n") ? block : block + "\n";
  return `/usr/bin/env bash << '${eofMarker}'\n${normalizedBlock}${eofMarker}\n`;
}

// ============================================================================
// File Processing
// ============================================================================

/**
 * Fix bash blocks in a single file
 * Returns number of blocks fixed
 */
function fixFile(filepath: string, dryRun: boolean): number {
  let fixes = 0;
  const eofCounter: Record<string, number> = {};

  try {
    let content = readFileSync(filepath, FILE_ENCODING);
    const originalContent = content;

    // Replace bash blocks that need wrapping
    content = content.replace(
      /(```bash\n)([\s\S]*?)(```)/g,
      (match, prefix, block, suffix) => {
        // Skip if already wrapped or is a doc example
        if (hasHeredocWrapper(block)) {
          return match;
        }

        if (isDocExample(block)) {
          return match;
        }

        // Check if block needs wrapping
        if (!hasBashSpecificSyntax(block)) {
          return match;
        }

        // Generate unique EOF marker
        let marker = generateEofMarker(block, filepath);
        eofCounter[marker] = (eofCounter[marker] || 0) + 1;
        if (eofCounter[marker] > 1) {
          marker = `${marker}_${eofCounter[marker]}`;
        }

        fixes++;
        return `${prefix}${wrapBlock(block, marker)}${suffix}`;
      }
    );

    if (fixes > 0) {
      if (dryRun) {
        console.log(`${yellow("Would fix")} ${fixes} block(s) in ${filepath}`);
      } else {
        writeFileSync(filepath, content, FILE_ENCODING);
        console.log(`${green("Fixed")} ${fixes} block(s) in ${filepath}`);
      }
    }
  } catch (err) {
    logError(`reading ${filepath}`, err);
  }

  return fixes;
}

// ============================================================================
// Directory Walking
// ============================================================================

/**
 * Walk directory and fix all markdown files
 */
async function fixDirectory(dirPath: string, dryRun: boolean): Promise<number> {
  let totalFixes = 0;

  const glob = new Glob("**/*.md");

  for await (const file of glob.scan({ cwd: dirPath, absolute: true })) {
    // Skip excluded directories
    const parts = file.split("/");
    const shouldSkip = parts.some((p) => SKIP_DIRECTORIES.has(p));
    if (shouldSkip) continue;

    totalFixes += fixFile(file, dryRun);
  }

  return totalFixes;
}

// ============================================================================
// Entry Point
// ============================================================================

async function main(): Promise<void> {
  const args = Bun.argv.slice(2);
  const dryRun = args.includes("--dry") || args.includes("-n");
  const help = args.includes("--help") || args.includes("-h");
  const pathArg = args.find((a) => !a.startsWith("-"));

  if (help || !pathArg) {
    console.log(`
Usage: bun run fix-bash-blocks.ts <path> [options]

Arguments:
  path              File or directory to process

Options:
  --dry, -n         Preview changes without writing
  -h, --help        Show this help message

What it does:
  Wraps bash code blocks containing bash-specific syntax with heredoc wrappers
  for zsh compatibility. Claude Code runs bash through zsh on macOS.

Patterns requiring wrapper:
  - $() command substitution
  - [[ ]] bash conditionals
  - declare, local, function keywords
  - \${...} variable expansion

Example wrapper:
  \`\`\`bash
  /usr/bin/env bash << 'SETUP_EOF'
  TOKEN=\$(gh auth token)
  echo "\$TOKEN"
  SETUP_EOF
  \`\`\`
`);
    process.exit(help ? 0 : 2);
  }

  const targetPath = resolve(pathArg);

  if (!existsSync(targetPath)) {
    fatalError("path resolution", new Error(`Path not found: ${targetPath}`));
  }

  let totalFixes = 0;
  const stat = statSync(targetPath);

  if (stat.isFile()) {
    if (!targetPath.endsWith(".md")) {
      console.log(yellow("Warning: File is not a markdown file"));
    }
    totalFixes = fixFile(targetPath, dryRun);
  } else if (stat.isDirectory()) {
    totalFixes = await fixDirectory(targetPath, dryRun);
  } else {
    fatalError("path resolution", new Error(`Invalid path type: ${targetPath}`));
  }

  // Summary
  console.log();
  if (totalFixes === 0) {
    console.log(green("No bash blocks needed fixing."));
  } else {
    const action = dryRun ? "Would fix" : "Fixed";
    console.log(`${cyan(action)} ${totalFixes} total bash block(s)`);
  }

  if (dryRun && totalFixes > 0) {
    console.log(dim("\nRun without --dry to apply changes."));
  }

  process.exit(0);
}

main().catch((err) => {
  fatalError("main execution", err);
});
