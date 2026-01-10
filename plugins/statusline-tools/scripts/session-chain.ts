#!/usr/bin/env bun
/**
 * session-chain.ts - Session UUID display for statusline
 *
 * Usage: bun session-chain.ts <session-id>
 * Output: Full session UUID in gray
 *
 * Simplified implementation: Just displays the current session UUID.
 * Auto-compaction does NOT create new session UUIDs - the UUID stays
 * the same throughout a session's lifetime.
 */

import { formatSessionId } from "../lib/chain-formatter";

// Get session ID from args
const sessionId = process.argv[2];

if (!sessionId) {
  console.error("Usage: session-chain <session-id>");
  process.exit(1);
}

// Output formatted session UUID (full UUID in gray)
console.log(formatSessionId(sessionId));
