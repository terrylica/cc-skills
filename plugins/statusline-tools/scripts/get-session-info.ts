#!/usr/bin/env bun
/**
 * get-session-info.ts - Query current session from registry
 *
 * Reads ~/.claude/projects/{encoded-cwd}/.session-chain-cache.json
 * and outputs session information for the current working directory.
 *
 * Usage: bun get-session-info.ts [cwd]
 *        If cwd not provided, uses process.cwd()
 */

import { readRegistry } from "../lib/session-registry";
import { getProjectDir, sanitizePath } from "../lib/path-encoder";
import { log } from "../lib/logger";

const cwd = process.argv[2] || process.cwd();
const projectDir = getProjectDir(cwd);
const cacheFile = `${projectDir}/.session-chain-cache.json`;

const registry = readRegistry(cwd);

if (!registry) {
  console.log(`No session registry found for: ${sanitizePath(cwd)}`);
  console.log(`Expected at: ${sanitizePath(cacheFile)}`);
  console.log(`\nRegistry will be created on next statusline render.`);
  process.exit(0);
}

console.log(`Current Session: ${registry.currentSessionId}`);
console.log(`Short ID: ${registry.currentSessionId.split("-")[0]}`);
console.log(`Project: ${sanitizePath(cwd)}`);
console.log(`Registry: ${sanitizePath(cacheFile)}`);
console.log(`Chain Length: ${registry.chain?.length || 1} session(s)`);
console.log(`Last Updated: ${new Date(registry.updatedAt).toISOString()}`);

if (registry._managedBy) {
  console.log(`Managed By: ${registry._managedBy}`);
}

if (registry._userExtensions) {
  const ext = registry._userExtensions;
  console.log(`\nMetadata:`);
  if (ext.repoName) console.log(`  Repo: ${ext.repoName}`);
  if (ext.repoHash) console.log(`  Hash: ${ext.repoHash}`);
  if (ext.gitBranch) console.log(`  Branch: ${ext.gitBranch}`);
  if (ext.model) console.log(`  Model: ${ext.model}`);
  if (ext.costUsd !== undefined) console.log(`  Cost: $${ext.costUsd.toFixed(2)}`);
}

if (registry.chain && registry.chain.length > 1) {
  console.log(`\nRecent Sessions (last 5):`);
  registry.chain.slice(-5).forEach((entry, i) => {
    console.log(`  ${i + 1}. ${entry.shortId} (${entry.timestamp})`);
  });
}

log("info", "Session info queried", {
  session_id: registry.currentSessionId,
  project_path: cwd,
  event: "session_info_queried",
});
