/**
 * session-cache.ts - Per-project session chain cache
 *
 * Cache location: ~/.claude/projects/[ENCODED_PATH]/.session-chain-cache.json
 * Invalidation: When current sessionId changes
 * TTL: None (invalidated on session change)
 */

import { existsSync } from "node:fs";
import { join } from "node:path";
import type { SessionCache, SessionChainEntry } from "../types/session";

const CACHE_FILENAME = ".session-chain-cache.json";
const CACHE_VERSION = 1;

export class SessionCacheManager {
  private projectPath: string;
  private cachePath: string;

  constructor(projectPath: string) {
    this.projectPath = projectPath;
    this.cachePath = join(projectPath, CACHE_FILENAME);
  }

  /**
   * Read cache if valid for current session
   * Returns null if cache miss or stale
   * Performance: ~1ms
   */
  async get(currentSessionId: string): Promise<SessionChainEntry[] | null> {
    if (!existsSync(this.cachePath)) return null;

    try {
      const file = Bun.file(this.cachePath);
      const cache: SessionCache = await file.json();

      // Validate cache version
      if (cache.version !== CACHE_VERSION) {
        return null;
      }

      // Validate cache is for current session
      if (cache.currentSessionId !== currentSessionId) {
        return null; // Session changed, cache stale
      }

      // Convert timestamp strings back to Date objects
      return cache.chain.map((entry) => ({
        ...entry,
        timestamp: new Date(entry.timestamp),
      }));
    } catch {
      return null;
    }
  }

  /**
   * Write chain to cache
   * Performance: ~2ms
   */
  async set(
    currentSessionId: string,
    chain: SessionChainEntry[]
  ): Promise<void> {
    const cache: SessionCache = {
      version: CACHE_VERSION,
      currentSessionId,
      chain,
      updatedAt: Date.now(),
    };

    await Bun.write(this.cachePath, JSON.stringify(cache, null, 2));
  }

  /**
   * Clear cache (useful for testing)
   */
  async clear(): Promise<void> {
    if (existsSync(this.cachePath)) {
      await Bun.write(this.cachePath, "");
    }
  }
}
