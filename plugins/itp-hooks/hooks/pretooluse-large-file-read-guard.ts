#!/usr/bin/env bun
/**
 * PreToolUse guard: warns Claude when reading large files without offset/limit.
 *
 * When Claude uses the Read tool on a file with >2000 lines and doesn't specify
 * offset or limit, this hook injects additionalContext warning Claude to read
 * in chunks. Does NOT block the read — educational only.
 *
 * Inspired by: https://www.youtube.com/watch?v=... (Claude Code Setup tips)
 */

import {
  parseStdinOrAllow,
  allow,
  trackHookError,
} from "./pretooluse-helpers.ts";

const HOOK_NAME = "pretooluse-large-file-read-guard";
const LINE_THRESHOLD = 2000;

async function main(): Promise<void> {
  const input = await parseStdinOrAllow(HOOK_NAME);
  if (!input) return;

  const { tool_name, tool_input = {} } = input;

  // Only applies to Read tool
  if (tool_name !== "Read") {
    allow();
    return;
  }

  const filePath = tool_input.file_path as string | undefined;
  const limit = tool_input.limit as number | undefined;
  const offset = tool_input.offset as number | undefined;

  // If limit or offset is already specified, Claude is reading in chunks — allow
  if (limit != null || offset != null) {
    allow();
    return;
  }

  // No file path — let Read tool handle the error
  if (!filePath) {
    allow();
    return;
  }

  // Check if file exists and count lines
  try {
    const file = Bun.file(filePath);
    const exists = await file.exists();
    if (!exists) {
      allow();
      return;
    }

    // Skip binary files (check first 512 bytes for null bytes)
    const slice = file.slice(0, 512);
    const sample = new Uint8Array(await slice.arrayBuffer());
    if (sample.includes(0)) {
      allow();
      return;
    }

    // Count lines efficiently using Bun.spawn (wc -l)
    const proc = Bun.spawn(["wc", "-l"], {
      stdin: Bun.file(filePath),
      stdout: "pipe",
      stderr: "ignore",
    });
    const wcOutput = await new Response(proc.stdout).text();
    const exitCode = await proc.exited;
    if (exitCode !== 0) {
      allow();
      return;
    }

    const lineCount = parseInt(wcOutput.trim(), 10);
    if (Number.isNaN(lineCount) || lineCount <= LINE_THRESHOLD) {
      allow();
      return;
    }

    // File exceeds threshold — inject warning context (allow, don't block)
    console.log(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          additionalContext: `WARNING: This file has ${lineCount} lines which exceeds the ${LINE_THRESHOLD}-line default. Use offset and limit parameters to read in chunks.`,
        },
      }),
    );
  } catch (err) {
    // Fail-open: any error (permissions, broken symlink, etc.) → allow
    trackHookError(
      HOOK_NAME,
      err instanceof Error ? err.message : String(err),
    );
    allow();
  }
}

main().catch((err) => {
  trackHookError(
    HOOK_NAME,
    err instanceof Error ? err.message : String(err),
  );
  allow();
});
