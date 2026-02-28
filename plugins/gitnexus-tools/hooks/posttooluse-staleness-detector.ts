#!/usr/bin/env bun
/**
 * PostToolUse hook: GitNexus staleness detector
 *
 * After every Write|Edit of a code file, checks if the GitNexus index
 * is stale (5+ commits behind). Warns once per session per repo.
 *
 * Fail-open everywhere — every catch exits 0.
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { join } from "path";
import { execSync } from "child_process";
import { createHash } from "crypto";

// --- Types ---

interface HookInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
  };
  session_id?: string;
}

// --- Constants ---

const CODE_EXTENSIONS = new Set([
  ".rs", ".py", ".ts", ".tsx", ".js", ".jsx",
  ".go", ".java", ".c", ".cpp", ".h", ".hpp",
  ".rb", ".swift", ".kt", ".sh", ".bash",
  ".mjs", ".cjs", ".vue", ".svelte",
]);

const STALENESS_DIR = "/tmp/.claude-gitnexus-staleness";
const COMMIT_THRESHOLD = 5;

// --- Utility ---

function blockWithReminder(reason: string): void {
  // ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
  // MUST use decision:block format — only "reason" field is visible to Claude
  console.log(JSON.stringify({ decision: "block", reason }));
}

function getFileExtension(filePath: string): string {
  const lastDot = filePath.lastIndexOf(".");
  if (lastDot === -1) return "";
  return filePath.substring(lastDot);
}

function hashString(s: string): string {
  return createHash("md5").update(s).digest("hex").substring(0, 12);
}

// --- Main ---

async function main(): Promise<void> {
  // Read JSON from stdin
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let input: HookInput;
  try {
    input = JSON.parse(inputText);
  } catch {
    process.exit(0);
  }

  const filePath = input.tool_input?.file_path;
  if (!filePath) {
    process.exit(0);
  }

  // Skip non-code files
  const ext = getFileExtension(filePath);
  if (!CODE_EXTENSIONS.has(ext)) {
    process.exit(0);
  }

  // Find git root
  let gitRoot: string;
  try {
    gitRoot = execSync("git rev-parse --show-toplevel", {
      cwd: filePath.substring(0, filePath.lastIndexOf("/")),
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    process.exit(0);
  }

  // Check .gitnexus/meta.json exists (non-indexed repos → skip)
  const metaPath = join(gitRoot, ".gitnexus", "meta.json");
  if (!existsSync(metaPath)) {
    process.exit(0);
  }

  // Once-per-session gate
  const sessionId = input.session_id || "unknown";
  const repoHash = hashString(gitRoot);
  const gateFile = join(STALENESS_DIR, `${sessionId}-${repoHash}.checked`);

  try {
    mkdirSync(STALENESS_DIR, { recursive: true });
  } catch {
    process.exit(0);
  }

  if (existsSync(gateFile)) {
    process.exit(0);
  }

  // Read meta.json → get lastCommit
  let lastCommit: string;
  try {
    const meta = JSON.parse(readFileSync(metaPath, "utf-8"));
    lastCommit = meta.lastCommit;
    if (!lastCommit) {
      process.exit(0);
    }
  } catch {
    process.exit(0);
  }

  // Compare with current HEAD
  let headCommit: string;
  try {
    headCommit = execSync("git rev-parse HEAD", {
      cwd: gitRoot,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    process.exit(0);
  }

  // Mark as checked (regardless of result — only warn once)
  try {
    writeFileSync(gateFile, String(Math.floor(Date.now() / 1000)));
  } catch {
    // Non-fatal
  }

  if (lastCommit === headCommit) {
    process.exit(0);
  }

  // Count commits behind
  let commitsBehind: number;
  try {
    const count = execSync(`git rev-list --count ${lastCommit}..HEAD`, {
      cwd: gitRoot,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    commitsBehind = parseInt(count, 10);
  } catch {
    process.exit(0);
  }

  if (commitsBehind < COMMIT_THRESHOLD) {
    process.exit(0);
  }

  blockWithReminder(
    `[GITNEXUS] Index is stale (${commitsBehind} commits behind). Run \`npx gitnexus@latest analyze\` to refresh, or use /gitnexus-tools:reindex.`
  );
}

main().catch(() => {
  process.exit(0);
});
