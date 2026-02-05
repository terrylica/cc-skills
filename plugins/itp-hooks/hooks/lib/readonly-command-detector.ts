#!/usr/bin/env bun
/**
 * readonly-command-detector.ts - Detect read-only/search commands for early exit
 *
 * Best practice from Claude Code hooks documentation:
 * - Skip hooks for non-destructive operations to reduce noise
 * - Early exit for read-only commands (grep, find, ls, cat, etc.)
 * - Avoid blocking or validating commands that don't modify state
 *
 * Usage:
 *   import { isReadOnlyCommand } from "./lib/readonly-command-detector.ts";
 *   if (isReadOnlyCommand(command)) {
 *     return allow();  // Skip validation for read-only commands
 *   }
 *
 * Reference: https://code.claude.com/docs/en/hooks
 * ADR: /docs/adr/2026-02-05-plan-mode-detection-hooks.md
 */

// ============================================================================
// Configuration
// ============================================================================

/**
 * Read-only command patterns that should skip validation hooks.
 * These commands only read data and don't modify system state.
 */
const READ_ONLY_PATTERNS = [
  // Search tools (ripgrep, grep, ag, ack)
  /^\s*(rg|ripgrep)\b/,
  /^\s*grep\b/,
  /^\s*egrep\b/,
  /^\s*fgrep\b/,
  /^\s*ag\b/, // The Silver Searcher
  /^\s*ack\b/, // ack (grep-like)

  // File finding tools
  /^\s*find\b/,
  /^\s*fd\b/, // fd (find alternative)
  /^\s*locate\b/,
  /^\s*mdfind\b/, // macOS Spotlight

  // File reading/viewing
  /^\s*cat\b/,
  /^\s*less\b/,
  /^\s*more\b/,
  /^\s*head\b/,
  /^\s*tail\b/,
  /^\s*bat\b/, // bat (cat clone with syntax highlighting)

  // Directory listing
  /^\s*ls\b/,
  /^\s*ll\b/, // common alias for ls -l
  /^\s*la\b/, // common alias for ls -la
  /^\s*tree\b/,
  /^\s*exa\b/, // exa (modern ls)
  /^\s*eza\b/, // eza (exa fork)

  // File info/stats
  /^\s*file\b/,
  /^\s*stat\b/,
  /^\s*wc\b/,
  /^\s*du\b/,
  /^\s*df\b/,

  // Text processing (when used for reading)
  /^\s*awk\b.*\{.*print/i, // awk printing
  /^\s*sed\s+-n\b/, // sed print-only mode
  /^\s*jq\b/, // JSON query
  /^\s*yq\b/, // YAML query
  /^\s*xq\b/, // XML query

  // Git read-only commands
  /^\s*git\s+(status|log|diff|show|branch|tag|remote|config\s+--get)\b/,
  /^\s*git\s+ls-(files|tree|remote)\b/,

  // System info
  /^\s*which\b/,
  /^\s*whereis\b/,
  /^\s*type\b/,
  /^\s*command\s+-v\b/,
  /^\s*echo\b/,
  /^\s*printf\b/,
  /^\s*date\b/,
  /^\s*whoami\b/,
  /^\s*hostname\b/,
  /^\s*uname\b/,
  /^\s*env\b/,
  /^\s*printenv\b/,
  /^\s*pwd\b/,

  // Package info (not install)
  /^\s*npm\s+(list|ls|view|info|outdated|search)\b/,
  /^\s*yarn\s+(list|info|outdated|why)\b/,
  /^\s*pnpm\s+(list|ls|view|outdated|why)\b/,
  /^\s*bun\s+(pm\s+ls)\b/,
  /^\s*pip\s+(list|show|freeze)\b/,
  /^\s*uv\s+(pip\s+(list|show|freeze)|tree)\b/,
  /^\s*cargo\s+(tree|search|info)\b/,
  /^\s*brew\s+(list|info|search|outdated)\b/,

  // mise read-only
  /^\s*mise\s+(list|ls|current|where|which|doctor|version)\b/,

  // Process info
  /^\s*ps\b/,
  /^\s*top\b/,
  /^\s*htop\b/,
  /^\s*pgrep\b/,

  // Network info (read-only)
  /^\s*curl\s+.*(-I|--head)\b/, // HEAD request only
  /^\s*ping\b/,
  /^\s*dig\b/,
  /^\s*nslookup\b/,
  /^\s*host\b/,
  /^\s*traceroute\b/,
  /^\s*netstat\b/,

  // Help commands
  /^\s*man\b/,
  /--help\b/,
  /-h\b$/,
  /--version\b/,
  /-v\b$/,
  /-V\b$/,
];

/**
 * Commands that are NEVER read-only (always need validation).
 * These patterns take precedence over READ_ONLY_PATTERNS.
 */
const NEVER_READ_ONLY_PATTERNS = [
  // Destructive commands
  /\brm\b/,
  /\brmdir\b/,
  /\bunlink\b/,

  // Write operations
  /\bmv\b/,
  /\bcp\b/,
  /\bdd\b/,
  /\bchmod\b/,
  /\bchown\b/,
  /\bchgrp\b/,

  // Git write operations
  /\bgit\s+(commit|push|pull|merge|rebase|reset|checkout|stash|clean|gc)\b/,
  /\bgit\s+(add|rm|mv)\b/,

  // Package modifications
  /\b(npm|yarn|pnpm|bun)\s+(install|add|remove|uninstall|update|upgrade)\b/,
  /\bpip\s+install\b/,
  /\buv\s+(pip\s+install|add|remove|sync)\b/,
  /\bcargo\s+(install|build|run|test)\b/,
  /\bbrew\s+(install|uninstall|upgrade|update)\b/,

  // Process control
  /\bkill\b/,
  /\bpkill\b/,
  /\bkillall\b/,

  // Redirection that writes
  /[>|]\s*[^|]/, // Output redirection (but not pipes)
];

// ============================================================================
// Types
// ============================================================================

export interface ReadOnlyCheckResult {
  /** True if the command is read-only */
  isReadOnly: boolean;
  /** Which pattern matched (for debugging) */
  matchedPattern?: string;
  /** Reason why command is NOT read-only (if applicable) */
  writeReason?: string;
}

// ============================================================================
// Detection Functions
// ============================================================================

/**
 * Check if a bash command is read-only (doesn't modify system state).
 *
 * @param command - The bash command to check
 * @returns ReadOnlyCheckResult with detection details
 *
 * @example
 * const result = isReadOnlyCommand("rg pattern src/");
 * if (result.isReadOnly) {
 *   return allow();  // Skip validation
 * }
 */
export function isReadOnlyCommand(command: string): ReadOnlyCheckResult {
  if (!command || command.trim() === "") {
    return { isReadOnly: false, writeReason: "empty command" };
  }

  const trimmedCommand = command.trim();

  // First check if command matches a NEVER read-only pattern
  for (const pattern of NEVER_READ_ONLY_PATTERNS) {
    if (pattern.test(trimmedCommand)) {
      return {
        isReadOnly: false,
        writeReason: `matches write pattern: ${pattern.source}`,
      };
    }
  }

  // Then check if command matches a read-only pattern
  for (const pattern of READ_ONLY_PATTERNS) {
    if (pattern.test(trimmedCommand)) {
      return {
        isReadOnly: true,
        matchedPattern: pattern.source,
      };
    }
  }

  // Default: not recognized as read-only
  return { isReadOnly: false, writeReason: "no read-only pattern matched" };
}

/**
 * Quick boolean check for read-only commands.
 * Use when you don't need detailed result info.
 *
 * @example
 * if (isReadOnly(command)) {
 *   return allow();
 * }
 */
export function isReadOnly(command: string): boolean {
  return isReadOnlyCommand(command).isReadOnly;
}

/**
 * Get the list of read-only patterns for testing/debugging.
 */
export function getReadOnlyPatterns(): RegExp[] {
  return [...READ_ONLY_PATTERNS];
}

/**
 * Get the list of never-read-only patterns for testing/debugging.
 */
export function getNeverReadOnlyPatterns(): RegExp[] {
  return [...NEVER_READ_ONLY_PATTERNS];
}
