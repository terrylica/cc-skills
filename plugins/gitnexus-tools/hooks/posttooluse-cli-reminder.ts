#!/usr/bin/env bun
/**
 * PostToolUse hook: GitNexus CLI reminder
 *
 * On the first exploration tool use (Read|Glob|Grep|Bash|Task) in a repo
 * with a .gitnexus/ index, reminds Claude to use the GitNexus CLI instead
 * of MCP or manual grep-based exploration.
 *
 * Gates once per session per repo (via /tmp/.claude-gitnexus-cli-reminder/).
 * Only fires in repos that have .gitnexus/meta.json (indexed repos).
 *
 * Fail-open everywhere — every catch exits 0.
 */

import { writeFileSync, mkdirSync, existsSync } from "fs";
import { join } from "path";
import { execSync } from "child_process";
import { createHash } from "crypto";

// --- Types ---

interface HookInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    command?: string;
    pattern?: string;
    path?: string;
    prompt?: string;
    subagent_type?: string;
  };
  session_id?: string;
  cwd?: string;
}

// --- Constants ---

const GATE_DIR = "/tmp/.claude-gitnexus-cli-reminder";

// --- Utility ---

function blockWithReminder(reason: string): void {
  // ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
  // MUST use decision:block format — only "reason" field is visible to Claude
  console.log(JSON.stringify({ decision: "block", reason }));
}

function hashString(s: string): string {
  return createHash("md5").update(s).digest("hex").substring(0, 12);
}

// --- Main ---

async function main(): Promise<void> {
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

  // Determine working directory from tool input or cwd
  const cwd =
    input.cwd ||
    input.tool_input?.file_path?.substring(
      0,
      input.tool_input.file_path.lastIndexOf("/")
    ) ||
    input.tool_input?.path ||
    "";

  if (!cwd) {
    process.exit(0);
  }

  // Find git root
  let gitRoot: string;
  try {
    gitRoot = execSync("git rev-parse --show-toplevel", {
      cwd,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    process.exit(0);
  }

  // Only fire in repos with a GitNexus index
  const metaPath = join(gitRoot, ".gitnexus", "meta.json");
  if (!existsSync(metaPath)) {
    process.exit(0);
  }

  // Once-per-session gate
  const sessionId = input.session_id || "unknown";
  const repoHash = hashString(gitRoot);
  const gateFile = join(GATE_DIR, `${sessionId}-${repoHash}.reminded`);

  try {
    mkdirSync(GATE_DIR, { recursive: true });
  } catch {
    process.exit(0);
  }

  if (existsSync(gateFile)) {
    process.exit(0);
  }

  // Mark as reminded (regardless of outcome — only fire once)
  try {
    writeFileSync(gateFile, String(Math.floor(Date.now() / 1000)));
  } catch {
    // Non-fatal
  }

  const repoName = gitRoot.split("/").pop() || "this repo";

  blockWithReminder(
    `[GITNEXUS] This repo (${repoName}) has a GitNexus knowledge graph index. Use the CLI for code exploration — NOT MCP (no gitnexus MCP server exists):

  npx gitnexus@latest query "<concept>" --limit 5    # Explore execution flows
  npx gitnexus@latest context "<symbol>" --content    # 360° symbol view (callers, callees, source)
  npx gitnexus@latest impact "<symbol>" --depth 3     # Blast radius analysis
  npx gitnexus@latest status                          # Check index freshness

Skills: /gitnexus-tools:explore | /gitnexus-tools:impact | /gitnexus-tools:dead-code | /gitnexus-tools:reindex`
  );
}

main().catch(() => {
  process.exit(0);
});
