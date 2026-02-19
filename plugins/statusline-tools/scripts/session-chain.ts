#!/usr/bin/env bun
/**
 * session-chain.ts - ~/.claude/projects JSONL ID display for statusline
 *
 * Usage: bun session-chain.ts <session-id>
 * Output: Full JSONL ID in gray
 *
 * The ID maps to ~/.claude/projects/<encoded-path>/<id>.jsonl
 * and stays the same throughout a session's lifetime.
 */

import { formatSessionId } from "../lib/chain-formatter";

// Get session ID from args
const sessionId = process.argv[2];

if (!sessionId) {
  console.error("Usage: session-chain <session-id>");
  process.exit(1);
}

// Output formatted JSONL ID (full UUID in gray)
console.log(formatSessionId(sessionId));
