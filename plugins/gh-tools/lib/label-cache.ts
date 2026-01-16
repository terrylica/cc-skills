#!/usr/bin/env bun
/**
 * label-cache.ts - Label taxonomy caching with 24h TTL
 *
 * Cache location: ~/.cache/gh-issue-skill/labels/{owner}_{repo}.json
 *
 * Caches repository labels to avoid repeated API calls.
 * TTL: 24 hours (configurable via LABEL_CACHE_TTL_MS env var)
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { logger } from "./logger";

const CACHE_DIR = `${process.env.HOME}/.cache/gh-issue-skill/labels`;
const DEFAULT_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

export interface Label {
  name: string;
  description: string;
  color: string;
}

interface CacheEntry {
  labels: Label[];
  cachedAt: number;
  repo: string;
}

/**
 * Get cache file path for a repository
 */
function getCachePath(repo: string): string {
  // Convert owner/repo to owner_repo for filesystem safety
  const safeRepo = repo.replace("/", "_");
  return `${CACHE_DIR}/${safeRepo}.json`;
}

/**
 * Get TTL from environment or use default
 */
function getTTL(): number {
  const envTTL = process.env.LABEL_CACHE_TTL_MS;
  if (envTTL) {
    const parsed = parseInt(envTTL, 10);
    if (!isNaN(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return DEFAULT_TTL_MS;
}

/**
 * Check if cache entry is expired
 */
function isExpired(entry: CacheEntry): boolean {
  const ttl = getTTL();
  const age = Date.now() - entry.cachedAt;
  return age > ttl;
}

/**
 * Read cached labels for a repository
 * Returns null if cache miss or expired
 */
function readCache(repo: string): CacheEntry | null {
  const cachePath = getCachePath(repo);

  if (!existsSync(cachePath)) {
    return null;
  }

  const content = readFileSync(cachePath, "utf-8");
  const entry = JSON.parse(content) as CacheEntry;

  if (isExpired(entry)) {
    logger.debug("Label cache expired", { event: "cache_expired", ctx: { repo } });
    return null;
  }

  return entry;
}

/**
 * Write labels to cache
 */
function writeCache(repo: string, labels: Label[]): void {
  // Ensure cache directory exists
  if (!existsSync(CACHE_DIR)) {
    mkdirSync(CACHE_DIR, { recursive: true, mode: 0o755 });
  }

  const entry: CacheEntry = {
    labels,
    cachedAt: Date.now(),
    repo,
  };

  const cachePath = getCachePath(repo);
  writeFileSync(cachePath, JSON.stringify(entry, null, 2));
  logger.debug("Label cache written", { event: "cache_written", ctx: { repo, labels_count: labels.length } });
}

/**
 * Fetch labels from GitHub API using gh CLI
 */
function fetchLabelsFromGitHub(repo: string): Label[] {
  const startTime = Date.now();

  const output = execSync(
    `gh label list --repo "${repo}" --json name,description,color --limit 200`,
    {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
      timeout: 30000, // 30 second timeout
    }
  );

  const labels = JSON.parse(output) as Label[];
  const duration = Date.now() - startTime;

  logger.info("Labels fetched from GitHub", {
    event: "labels_fetched",
    duration_ms: duration,
    ctx: { repo, labels_count: labels.length },
  });

  return labels;
}

/**
 * Get labels for a repository (cached or fresh)
 *
 * @param repo - Repository in "owner/repo" format
 * @returns Array of labels
 */
export function getLabels(repo: string): Label[] {
  // Check cache first
  const cached = readCache(repo);
  if (cached) {
    logger.debug("Label cache hit", { event: "cache_hit", ctx: { repo, labels_count: cached.labels.length } });
    return cached.labels;
  }

  // Fetch fresh and cache
  const labels = fetchLabelsFromGitHub(repo);
  writeCache(repo, labels);
  return labels;
}

/**
 * Invalidate cache for a repository
 */
export function invalidateCache(repo: string): void {
  const cachePath = getCachePath(repo);
  if (existsSync(cachePath)) {
    const { unlinkSync } = require("node:fs");
    unlinkSync(cachePath);
    logger.info("Label cache invalidated", { event: "cache_invalidated", ctx: { repo } });
  }
}

/**
 * Get cache stats for debugging
 */
export function getCacheStats(repo: string): { exists: boolean; age_ms?: number; label_count?: number } {
  const cachePath = getCachePath(repo);

  if (!existsSync(cachePath)) {
    return { exists: false };
  }

  const content = readFileSync(cachePath, "utf-8");
  const entry = JSON.parse(content) as CacheEntry;

  return {
    exists: true,
    age_ms: Date.now() - entry.cachedAt,
    label_count: entry.labels.length,
  };
}
