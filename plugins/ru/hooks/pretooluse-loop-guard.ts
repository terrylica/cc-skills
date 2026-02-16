#!/usr/bin/env bun
/**
 * PreToolUse hook: Guard loop control files from deletion.
 *
 * Prevents Claude from bypassing the Stop hook by directly running
 * Bash commands that delete .claude/loop-enabled or other loop files.
 *
 * Protected files and deletion patterns are configurable via
 * .claude/ru-config.json.
 *
 * ADR: /docs/adr/2025-12-20-ralph-rssi-eternal-loop.md
 * ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md (output format)
 */

import { basename } from "path";
import { loadConfig, type ProtectionConfig } from "./core/config-schema";
import { trackHookError } from "../../itp-hooks/hooks/lib/hook-error-tracker.ts";

// --- Types ---

interface HookInput {
  tool_name: string;
  tool_input: {
    command?: string;
  };
}

interface PreToolUseOutput {
  hookSpecificOutput: {
    hookEventName: "PreToolUse";
    permissionDecision: "allow" | "deny";
    permissionDecisionReason?: string;
  };
}

// --- Helper Functions ---

function getProtectionConfig(): ProtectionConfig {
  const projectDir = process.env.CLAUDE_PROJECT_DIR || "";
  const config = loadConfig(projectDir || undefined);
  return config.protection;
}

function allowCommand(): void {
  const output: PreToolUseOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
    },
  };
  console.log(JSON.stringify(output));
}

function denyCommand(reason: string): void {
  const output: PreToolUseOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  };
  console.log(JSON.stringify(output));
}

/**
 * Check if command is an official Ralph command with bypass marker.
 *
 * Any command containing a registered bypass marker (e.g., RALPH_STOP_SCRIPT,
 * RALPH_ENCOURAGE_SCRIPT) is allowed to operate on protected files.
 */
function isOfficialRalphCommand(command: string): boolean {
  const cfg = getProtectionConfig();

  // Check bypass_markers list
  for (const marker of cfg.bypass_markers) {
    if (command.includes(marker)) {
      return true;
    }
  }

  // Fallback to legacy single marker for backward compatibility
  return command.includes(cfg.stop_script_marker);
}

/**
 * Check if command attempts to delete protected files.
 */
function isDeletionCommand(command: string): boolean {
  const cfg = getProtectionConfig();

  // Check for deletion patterns (from config)
  const hasDeletionCmd = cfg.deletion_patterns.some((pattern) => {
    try {
      return new RegExp(pattern).test(command);
    } catch {
      // Invalid regex pattern, skip it
      return false;
    }
  });

  if (!hasDeletionCmd) {
    return false;
  }

  // Check if any protected file is mentioned (from config)
  for (const protectedFile of cfg.protected_files) {
    // Check for full path or relative path
    if (command.includes(protectedFile)) {
      return true;
    }
    // Check for just the filename
    const filename = basename(protectedFile);
    if (command.includes(filename)) {
      return true;
    }
  }

  return false;
}

// --- Main ---

async function main(): Promise<void> {
  // Read tool input from stdin
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let toolInput: HookInput;
  try {
    toolInput = JSON.parse(inputText);
  } catch (e) {
    // Can't parse input, allow the command but warn
    trackHookError("pretooluse-loop-guard", `Failed to parse tool input: ${e}`);
    allowCommand();
    return;
  }

  const command = toolInput.tool_input?.command || "";

  if (!command) {
    allowCommand();
    return;
  }

  // Allow official Ralph commands to operate on protected files
  if (isOfficialRalphCommand(command)) {
    allowCommand();
    return;
  }

  // Check if this is a deletion attempt on protected files
  if (isDeletionCommand(command)) {
    denyCommand(
      "[RALPH LOOP GUARD] Cannot delete loop control files. " +
        "The Ralph autonomous loop is active. Only the user can stop it " +
        "by running /ru:stop or removing .claude/loop-enabled manually. " +
        "Continue working on improvement opportunities instead."
    );
    return;
  }

  // Allow all other commands
  allowCommand();
}

main().catch((e) => {
  trackHookError("pretooluse-loop-guard", `Error in pretooluse-loop-guard: ${e}`);
  // On error, allow command to avoid blocking legitimate operations
  allowCommand();
});
