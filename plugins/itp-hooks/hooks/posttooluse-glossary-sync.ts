#!/usr/bin/env bun
/**
 * PostToolUse hook: Auto-sync GLOSSARY.md to Vale vocabulary files.
 * Triggers when ~/.claude/docs/GLOSSARY.md is edited.
 *
 * Pattern: Follows lifecycle-reference.md TypeScript template.
 * Trigger: After Edit or Write on GLOSSARY.md.
 * Output: { decision: "block", reason: "..." } for Claude visibility.
 */

import { existsSync } from "node:fs";
import { join } from "node:path";
import { $ } from "bun";

// ============================================================================
// CONFIGURATION
// ============================================================================

const HOME = process.env.HOME || "";
const GLOSSARY_PATH = join(HOME, ".claude/docs/GLOSSARY.md");
const SYNC_SCRIPT = join(HOME, ".claude/tools/bin/glossary-sync.ts");

// ============================================================================
// TYPES
// ============================================================================

interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    [key: string]: unknown;
  };
}

interface HookResult {
  exitCode: number;
  stdout?: string;
  stderr?: string;
}

// ============================================================================
// HELPERS
// ============================================================================

async function parseStdin(): Promise<PostToolUseInput | null> {
  try {
    const stdin = await Bun.stdin.text();
    if (!stdin.trim()) return null;
    return JSON.parse(stdin) as PostToolUseInput;
  } catch {
    return null;
  }
}

function createVisibilityOutput(reason: string): string {
  return JSON.stringify({
    decision: "block",
    reason: reason,
  });
}

// ============================================================================
// MAIN LOGIC
// ============================================================================

async function runHook(): Promise<HookResult> {
  const input = await parseStdin();
  if (!input) {
    return { exitCode: 0 };
  }

  const { tool_name, tool_input } = input;
  const filePath = tool_input?.file_path || "";

  // Only trigger on Edit/Write
  if (tool_name !== "Edit" && tool_name !== "Write") {
    return { exitCode: 0 };
  }

  // Only trigger on GLOSSARY.md
  if (!filePath.endsWith("GLOSSARY.md")) {
    return { exitCode: 0 };
  }

  // Ensure it's the global glossary, not a project-specific one
  if (!filePath.includes(".claude/docs/GLOSSARY.md")) {
    return { exitCode: 0 };
  }

  // Check if sync script exists
  if (!existsSync(SYNC_SCRIPT)) {
    return {
      exitCode: 0,
      stderr: `[glossary-sync] Sync script not found: ${SYNC_SCRIPT}`,
    };
  }

  // Run sync script
  try {
    const result = await $`bun ${SYNC_SCRIPT}`.quiet().nothrow();
    const output = result.stdout.toString();

    const reason = `[GLOSSARY-SYNC] Synced GLOSSARY.md to Vale vocabulary files.

${output}

Vale will now enforce the updated terminology rules across all CLAUDE.md files.`;

    return {
      exitCode: 0,
      stdout: createVisibilityOutput(reason),
    };
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return {
      exitCode: 0,
      stderr: `[glossary-sync] Sync failed: ${msg}`,
    };
  }
}

// ============================================================================
// ENTRY POINT
// ============================================================================

async function main(): Promise<never> {
  let result: HookResult;

  try {
    result = await runHook();
  } catch (err: unknown) {
    console.error("[glossary-sync] Unexpected error:");
    if (err instanceof Error) {
      console.error(`  Message: ${err.message}`);
    }
    return process.exit(0);
  }

  if (result.stderr) console.error(result.stderr);
  if (result.stdout) console.log(result.stdout);
  return process.exit(result.exitCode);
}

void main();
