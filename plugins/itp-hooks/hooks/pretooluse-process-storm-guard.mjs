#!/usr/bin/env bun
/**
 * PreToolUse hook: Process Storm Prevention Guard
 *
 * Detects patterns that cause runaway processes BEFORE execution.
 * Critical for macOS where cgroups don't exist for runtime containment.
 *
 * Patterns detected:
 * - Fork bombs (:(){ :|:& };:)
 * - gh CLI recursion (gh auth token in hooks)
 * - Credential helper storms
 * - mise activation in .zshenv
 * - Python subprocess storms
 * - Node.js child_process storms
 *
 * Usage:
 *   Installed via hooks.json in itp-hooks plugin
 *   Escape hatch: # PROCESS-STORM-OK comment
 *
 * ADR: /docs/adr/2026-01-13-process-storm-prevention.md
 */

import { detectPatterns, formatFindings, DEFAULT_CONFIG } from "./process-storm-patterns.mjs";

// ============================================================================
// HELPER FUNCTIONS (lifecycle-reference.md compliant)
// ============================================================================

/**
 * Output JSON response to stdout
 * @param {object} response - The response object
 */
function output(response) {
  console.log(JSON.stringify(response));
}

/**
 * Allow the tool operation to proceed
 * Lifecycle: permissionDecision: "allow"
 */
function allow() {
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
    },
  });
}

/**
 * Deny the tool operation with a reason
 * Lifecycle: permissionDecision: "deny" + permissionDecisionReason
 * @param {string} reason - Explanation shown to Claude
 */
function deny(reason) {
  output({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  });
}

// ============================================================================
// MAIN LOGIC
// ============================================================================

async function main() {
  // Parse stdin JSON input
  let input;
  try {
    const stdin = await Bun.stdin.text();
    input = JSON.parse(stdin);
  } catch (parseError) {
    console.error(`[PROCESS-STORM-GUARD] Failed to parse stdin: ${parseError.message}`);
    allow();
    return;
  }

  const { tool_name, tool_input = {} } = input;

  // Determine content to check based on tool type
  let content = "";

  if (tool_name === "Bash") {
    content = tool_input.command || "";
  } else if (tool_name === "Write") {
    content = tool_input.content || "";
  } else if (tool_name === "Edit") {
    content = tool_input.new_string || "";
  } else {
    // Not a tool we check
    allow();
    return;
  }

  // Early exit: No content to check
  if (!content || content.trim() === "") {
    allow();
    return;
  }

  // Detect patterns
  const findings = detectPatterns(content, DEFAULT_CONFIG.categories);

  // No findings = allow
  if (findings.length === 0) {
    allow();
    return;
  }

  // Block with formatted message
  const message = formatFindings(findings);
  deny(message);
}

// Run with error handling (always allow on error to avoid blocking)
main().catch((unhandledError) => {
  console.error(`[PROCESS-STORM-GUARD] Unhandled error: ${unhandledError.message}`);
  allow();
});
