/**
 * chain-formatter.ts - Format session chain for statusline display
 *
 * Output format: abc12345 → def67890 → ghi11223
 * All UUIDs in BRIGHT_BLACK (gray) for uniform, non-distracting reference display
 */

import type { SessionChainEntry } from "../types/session";

// ANSI color codes
const BRIGHT_BLACK = "\x1b[90m"; // Gray
const RESET = "\x1b[0m";

/**
 * Format chain for display (last 5 sessions)
 * Returns: "abc12345 → def67890 → ... → current12" (all in gray)
 */
export function formatChain(chain: SessionChainEntry[]): string {
  if (chain.length === 0) return "";

  // Take last 5, ensure current is last
  const displayChain = chain.slice(-5);

  const parts = displayChain.map((entry) => entry.shortId);

  // All in gray - uniform, non-distracting reference display
  return `${BRIGHT_BLACK}${parts.join(" → ")}${RESET}`;
}

/**
 * Format for plain output (no ANSI colors)
 */
export function formatChainPlain(chain: SessionChainEntry[]): string {
  if (chain.length === 0) return "";

  const displayChain = chain.slice(-5);
  return displayChain.map((e) => e.shortId).join(" → ");
}
