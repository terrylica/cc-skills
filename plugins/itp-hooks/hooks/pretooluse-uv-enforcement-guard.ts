#!/usr/bin/env bun
/**
 * PreToolUse hook: UV Enforcement Guard
 *
 * Blocks non-UV Python package management commands before execution.
 * pip, conda, pipx, virtualenv, easy_install → uv equivalents.
 *
 * Escape hatch: # UV-OK
 * ADR: /docs/adr/2026-01-10-uv-reminder-hook.md
 */

import { allow, deny, parseStdinOrAllow, isReadOnly, trackHookError } from "./pretooluse-helpers.ts";

// ============================================================================
// Blocked patterns: non-UV Python package management
// ============================================================================

interface BlockedPattern {
  regex: RegExp;
  label: string;
  uvEquivalent: string;
}

const BLOCKED_PATTERNS: BlockedPattern[] = [
  // pip install variants
  { regex: /\bpip\s+install\b/, label: "pip install", uvEquivalent: "uv add <pkg>" },
  { regex: /\bpip3\s+install\b/, label: "pip3 install", uvEquivalent: "uv add <pkg>" },
  { regex: /\bpython[0-9.]*\s+(-m\s+)?pip\s+install\b/, label: "python -m pip install", uvEquivalent: "uv add <pkg>" },

  // pip uninstall variants
  { regex: /\bpip3?\s+uninstall\b/, label: "pip uninstall", uvEquivalent: "uv remove <pkg>" },

  // conda
  { regex: /\bconda\s+install\b/, label: "conda install", uvEquivalent: "uv add <pkg>" },
  { regex: /\bconda\s+create\b/, label: "conda create", uvEquivalent: "uv venv (or: uv init)" },

  // pipx
  { regex: /\bpipx\s+install\b/, label: "pipx install", uvEquivalent: "uv tool install <pkg>" },

  // easy_install (legacy)
  { regex: /\beasy_install\b/, label: "easy_install", uvEquivalent: "uv add <pkg>" },

  // virtualenv / python -m venv
  { regex: /\bpython[0-9.]*\s+-m\s+venv\b/, label: "python -m venv", uvEquivalent: "uv venv" },
  { regex: /\bvirtualenv\b/, label: "virtualenv", uvEquivalent: "uv venv" },
];

// Fast-path keywords: if command doesn't contain any of these, skip all regex checks
const FAST_PATH_KEYWORDS = [
  "pip", "conda", "pipx", "easy_install", "virtualenv", "venv",
];

// ============================================================================
// Exception patterns: contexts where pip/conda/etc. are acceptable
// ============================================================================

/**
 * Check if the command is in an exception context (should be allowed).
 */
function isException(command: string): boolean {
  const commandLower = command.toLowerCase();

  // 1. Already in uv context (matches anywhere — catches SSH-wrapped commands)
  if (/\buv\s+(run|exec|pip|venv|add|remove|sync|tool)\b/i.test(commandLower)) {
    return true;
  }

  // 2. Escape hatch: # UV-OK
  if (/# UV-OK/i.test(command)) {
    return true;
  }

  // 3. Documentation/echo/printf context
  if (/^\s*(echo|printf)\s/i.test(commandLower)) {
    return true;
  }

  // 4. Comments
  if (/^\s*#/.test(command)) {
    return true;
  }

  // 5. Search context (grep, rg, etc.)
  if (/^\s*(grep|egrep|fgrep|rg|ag|ack)\b/i.test(commandLower)) {
    return true;
  }

  // 6. Commands whose arguments contain free-form text (commit messages, issue bodies)
  //    These commonly reference pip/conda as documentation, not as actual operations
  if (/^\s*gh\s+(issue|pr)\s+(create|edit|comment)\b/i.test(commandLower)) {
    return true;
  }
  if (/^\s*git\s+(commit|tag)\b/i.test(commandLower)) {
    return true;
  }

  // 7. Read-only pip operations (list, show, freeze, check, --version, --help)
  if (/\bpip3?\s+(list|show|freeze|check|--version|--help|-h)\b/i.test(commandLower)) {
    return true;
  }

  // 8. pip-compile (constraint compilation tool)
  if (/\bpip-compile\b/i.test(commandLower)) {
    return true;
  }

  return false;
}

/**
 * Build the deny message with the blocked command and UV equivalent.
 */
function buildDenyMessage(command: string, matched: BlockedPattern): string {
  // Extract the specific command that was blocked (first line or truncated)
  const cmdPreview = command.length > 80 ? command.slice(0, 77) + "..." : command;

  return `[UV-ENFORCEMENT] Non-UV Python package operation blocked

BLOCKED: ${cmdPreview}
USE INSTEAD: ${matched.uvEquivalent}

UV EQUIVALENTS:
  pip install <pkg>     \u2192 uv add <pkg>
  pip uninstall <pkg>   \u2192 uv remove <pkg>
  pip install -e .      \u2192 uv pip install -e .
  pip install -r req    \u2192 uv pip install -r req  (or: uv sync)
  python -m venv        \u2192 uv venv
  conda install <pkg>   \u2192 uv add <pkg>
  conda create          \u2192 uv venv (or: uv init)
  pipx install <pkg>    \u2192 uv tool install <pkg>
  virtualenv            \u2192 uv venv

Escape hatch: # UV-OK`;
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  const input = await parseStdinOrAllow("UV-ENFORCEMENT-GUARD");
  if (!input) return;

  const { tool_name, tool_input = {} } = input;

  // Only check Bash commands
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const command = tool_input.command || "";

  // Skip empty commands
  if (!command.trim()) {
    allow();
    return;
  }

  // Skip read-only commands (can't install anything)
  if (isReadOnly(command)) {
    allow();
    return;
  }

  // Fast path: skip if command doesn't contain any target keywords
  const commandLower = command.toLowerCase();
  if (!FAST_PATH_KEYWORDS.some((kw) => commandLower.includes(kw))) {
    allow();
    return;
  }

  // Check exception contexts
  if (isException(command)) {
    allow();
    return;
  }

  // Match against blocked patterns
  for (const pattern of BLOCKED_PATTERNS) {
    if (pattern.regex.test(command)) {
      deny(buildDenyMessage(command, pattern));
      return;
    }
  }

  // No match — allow
  allow();
}

main().catch((err) => {
  trackHookError("pretooluse-uv-enforcement-guard", err instanceof Error ? err.message : String(err));
  allow();
});
