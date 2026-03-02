#!/usr/bin/env bun
/**
 * PostToolUse hook: Rust SOTA tools reminder
 *
 * On the first tool use (Read|Glob|Grep|Bash|Edit|Write) in a repo
 * with Cargo.toml at the git root, reminds Claude of available SOTA
 * Rust tools and skills.
 *
 * Gates once per session per repo (via /tmp/.claude-rust-sota-reminder/).
 * Fail-open everywhere — every catch exits 0.
 */

import { mkdirSync, existsSync, openSync, closeSync, constants } from "fs";
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
  };
  session_id?: string;
  cwd?: string;
}

// --- Constants ---

const GATE_DIR = "/tmp/.claude-rust-sota-reminder";

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

  // Build candidate directories to check for git root.
  // Priority: input.cwd (session working dir) > file_path dir > path > process.cwd()
  // Key insight: file_path may point to ~/.claude/skills/ cache (not a git repo),
  // so we MUST try multiple candidates, not just the first non-empty one.
  const candidates: string[] = [];
  if (input.cwd) candidates.push(input.cwd);
  if (input.tool_input?.file_path) {
    const dir = input.tool_input.file_path.substring(
      0,
      input.tool_input.file_path.lastIndexOf("/")
    );
    if (dir) candidates.push(dir);
  }
  if (input.tool_input?.path) candidates.push(input.tool_input.path);
  try {
    candidates.push(process.cwd());
  } catch {
    // process.cwd() can throw if dir was deleted
  }

  if (candidates.length === 0) {
    process.exit(0);
  }

  // Find git root — try each candidate until one succeeds
  let gitRoot: string | undefined;
  for (const dir of candidates) {
    try {
      gitRoot = execSync("git rev-parse --show-toplevel", {
        cwd: dir,
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      }).trim();
      break;
    } catch {
      continue;
    }
  }

  if (!gitRoot) {
    process.exit(0);
  }

  // Only fire in repos with Cargo.toml at the git root
  const cargoPath = join(gitRoot, "Cargo.toml");
  if (!existsSync(cargoPath)) {
    process.exit(0);
  }

  // Once-per-session gate (atomic: O_CREAT|O_EXCL prevents race conditions
  // when multiple tool calls fire in the same batch)
  const sessionId = input.session_id || "unknown";
  const repoHash = hashString(gitRoot);
  const gateFile = join(GATE_DIR, `${sessionId}-${repoHash}.reminded`);

  try {
    mkdirSync(GATE_DIR, { recursive: true });
  } catch {
    process.exit(0);
  }

  // Atomic create-if-not-exists — if the file already exists, O_EXCL throws
  try {
    const fd = openSync(
      gateFile,
      constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL
    );
    closeSync(fd);
  } catch {
    // File already exists (another hook instance won the race) — exit silently
    process.exit(0);
  }

  const repoName = gitRoot.split("/").pop() || "this repo";

  blockWithReminder(
    `[RUST-TOOLS] Rust project detected (${repoName}). SOTA tools available:

REFACTORING: ast-grep (AST-aware rewrite), cargo-semver-checks (API compat)
PERFORMANCE: samply (profiler), divan/Criterion (bench), cargo-pgo (PGO+BOLT), cargo-wizard (profile auto-config)
TESTING: cargo-nextest (3x faster), cargo-mutants (mutation), cargo-hack (feature powerset)
SIMD: macerator (type-generic, multiversioning on stable)
DEPENDENCIES: cargo-audit + cargo-deny + cargo-vet (security/license/supply-chain)

Skills: /rust-tools:rust-sota-arsenal | /rust-tools:rust-dependency-audit`
  );
}

main().catch(() => {
  process.exit(0);
});
