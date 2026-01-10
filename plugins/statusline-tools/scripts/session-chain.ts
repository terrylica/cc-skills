#!/usr/bin/env bun
/**
 * session-chain.ts - Session ancestry chain for statusline
 *
 * Usage: bun session-chain.ts <session-id> [project-path]
 * Output: Formatted chain string (all in gray): abc12345 → def67890 → ghi11223
 *
 * Performance targets:
 *   - Cache hit: <5ms
 *   - Cache miss: <50ms (5 session traversal)
 */

import { join } from "node:path";
import { SessionCacheManager } from "../lib/session-cache";
import { buildSessionChain } from "../lib/session-parser";
import { formatChain } from "../lib/chain-formatter";

// Get args
const sessionId = process.argv[2];
const projectPathArg = process.argv[3];

if (!sessionId) {
  console.error("Usage: session-chain <session-id> [project-path]");
  process.exit(1);
}

/**
 * Infer project sessions path from current working directory
 * Claude Code encodes paths: /Users/foo/bar → -Users-foo-bar
 */
function inferProjectPath(): string {
  const cwd = process.cwd();
  // Remove leading slash, replace / and . with -, prepend -
  const encoded = "-" + cwd.slice(1).replace(/[/.]/g, "-");
  return join(process.env.HOME || "~", ".claude/projects", encoded);
}

async function main(): Promise<void> {
  const startTime = performance.now();
  const projectPath = projectPathArg || inferProjectPath();

  const cache = new SessionCacheManager(projectPath);

  // Try cache first (fast path)
  const cached = await cache.get(sessionId);
  if (cached) {
    console.log(formatChain(cached));

    if (process.env.DEBUG) {
      const elapsed = performance.now() - startTime;
      console.error(`[session-chain] Cache hit: ${elapsed.toFixed(1)}ms`);
    }
    return;
  }

  // Build chain from session files (slower path)
  const chain = await buildSessionChain(sessionId, projectPath);

  // Cache for next time
  await cache.set(sessionId, chain);

  // Output formatted chain
  console.log(formatChain(chain));

  if (process.env.DEBUG) {
    const elapsed = performance.now() - startTime;
    console.error(`[session-chain] Built chain: ${elapsed.toFixed(1)}ms`);
  }
}

main().catch((error) => {
  if (process.env.DEBUG) {
    console.error("[session-chain] Error:", error);
  }
  process.exit(1);
});
