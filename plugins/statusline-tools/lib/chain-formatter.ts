/**
 * chain-formatter.ts - Format ~/.claude/projects JSONL ID for statusline display
 *
 * Output format: Full UUID in gray (BRIGHT_BLACK)
 * Example: 8e017a43-227e-4b37-b1bb-0d136f894271
 */

// ANSI color codes
const BRIGHT_BLACK = "\x1b[90m"; // Gray
const RESET = "\x1b[0m";

/**
 * Format JSONL ID for display
 * Returns full UUID in gray for uniform, non-distracting reference display
 */
export function formatSessionId(sessionId: string): string {
  if (!sessionId) return "";

  // Full UUID in gray
  return `${BRIGHT_BLACK}${sessionId}${RESET}`;
}

/**
 * Format for plain output (no ANSI colors)
 */
export function formatSessionIdPlain(sessionId: string): string {
  return sessionId || "";
}
