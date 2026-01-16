/**
 * session-registry.ts - Registry read/write with security hardening
 *
 * Maintains ~/.claude/projects/{encoded-path}/.session-chain-cache.json
 * in Claude Code's native format with user extensions.
 *
 * Security measures:
 * - Symlink check before write
 * - chmod 600 after write
 * - Hashed cwd for PII prevention
 * - Provenance marker for forward-compatibility
 */

import {
  existsSync,
  readFileSync,
  writeFileSync,
  mkdirSync,
  lstatSync,
  renameSync,
  chmodSync,
} from "fs";
import { execSync } from "child_process";
import { log } from "./logger";
import { getProjectDir, hashPath, getRepoName } from "./path-encoder";
import { getPluginVersion, isWriteEnabled } from "./config";

const MAX_CHAIN_LENGTH = 50;
const PROVENANCE_MARKER = getPluginVersion();

interface ChainEntry {
  sessionId: string;
  shortId: string;
  timestamp: string;
}

interface UserExtensions {
  repoHash: string;
  repoName: string;
  gitBranch?: string;
  model?: string;
  costUsd?: number;
}

interface SessionRegistry {
  version: number;
  currentSessionId: string;
  chain: ChainEntry[];
  updatedAt: number;
  _managedBy?: string;
  _userExtensions?: UserExtensions;
}

/**
 * Check if a path is a symlink (security check)
 */
function isSymlink(path: string): boolean {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch (e) {
    // File doesn't exist or not accessible - treat as not symlink
    if (process.env.DEBUG_SESSION_REGISTRY) {
      console.error("[session-registry] isSymlink check failed:", e);
    }
    return false;
  }
}

/**
 * Get current git branch name
 */
function getGitBranch(cwd: string): string | undefined {
  try {
    return execSync("git branch --show-current", {
      cwd,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim() || undefined;
  } catch (e) {
    // Not a git repo or git not available - branch is optional
    if (process.env.DEBUG_SESSION_REGISTRY) {
      console.error("[session-registry] getGitBranch failed:", e);
    }
    return undefined;
  }
}

/**
 * Detect if Claude Code has resumed writes (our marker is missing)
 */
function detectCCWrites(data: SessionRegistry): boolean {
  // If _managedBy is missing or changed, Claude Code may have written
  if (!data._managedBy) return true;
  if (data._managedBy !== PROVENANCE_MARKER) return true;
  return false;
}

/**
 * Read existing registry or return null if not exists/corrupted
 */
export function readRegistry(cwd: string): SessionRegistry | null {
  const projectDir = getProjectDir(cwd);
  const cacheFile = `${projectDir}/.session-chain-cache.json`;

  if (!existsSync(cacheFile)) {
    return null;
  }

  try {
    const content = readFileSync(cacheFile, "utf-8");
    return JSON.parse(content) as SessionRegistry;
  } catch (e) {
    log("warn", "Registry corrupted, will recreate", {
      project_path: cwd,
      event: "registry_corrupted",
      ctx: { message: e instanceof Error ? e.message : String(e) },
    });
    // Backup corrupted file
    try {
      renameSync(cacheFile, `${cacheFile}.bak`);
    } catch (backupErr) {
      // Backup failure is non-critical - log and continue
      console.error("[session-registry] Backup of corrupted file failed:", backupErr);
    }
    return null;
  }
}

/**
 * Write registry with security hardening
 */
function writeRegistry(cwd: string, data: SessionRegistry): boolean {
  const projectDir = getProjectDir(cwd);
  const cacheFile = `${projectDir}/.session-chain-cache.json`;

  // Security: Check for symlink attack
  if (existsSync(cacheFile) && isSymlink(cacheFile)) {
    log("warn", "Symlink detected, aborting write", {
      project_path: cwd,
      event: "symlink_attack_blocked",
    });
    return false;
  }

  try {
    // Ensure directory exists
    if (!existsSync(projectDir)) {
      mkdirSync(projectDir, { recursive: true, mode: 0o755 });
      log("info", "Created project directory", {
        project_path: cwd,
        event: "directory_created",
      });
    }

    // Write with restrictive permissions
    writeFileSync(cacheFile, JSON.stringify(data, null, 2), {
      mode: 0o600,
    });

    // Ensure permissions are set (in case file existed)
    chmodSync(cacheFile, 0o600);

    return true;
  } catch (e) {
    log("warn", "Registry write failed", {
      project_path: cwd,
      event: "write_failed",
      ctx: { message: e instanceof Error ? e.message : String(e) },
    });
    return false;
  }
}

/**
 * Update session registry with new session ID
 *
 * @param sessionId - Current session UUID
 * @param cwd - Current working directory
 * @param model - Optional model name
 * @param costUsd - Optional session cost
 * @returns true if update succeeded
 */
export function updateRegistry(
  sessionId: string,
  cwd: string,
  model?: string,
  costUsd?: number
): boolean {
  if (!isWriteEnabled()) {
    log("info", "Registry writes disabled by config", {
      session_id: sessionId,
      project_path: cwd,
      event: "write_disabled",
    });
    return false;
  }

  const startTime = Date.now();
  const existing = readRegistry(cwd);

  // Check if Claude Code resumed native writes
  if (existing && detectCCWrites(existing)) {
    log("warn", "Claude Code native writes detected, skipping our update", {
      session_id: sessionId,
      project_path: cwd,
      event: "cc_writes_detected",
    });
    return false;
  }

  // Check if session already in chain (deduplication)
  if (existing?.currentSessionId === sessionId) {
    // Same session, just update metadata
    const updated: SessionRegistry = {
      ...existing,
      updatedAt: Date.now(),
      _managedBy: PROVENANCE_MARKER,
      _userExtensions: {
        repoHash: hashPath(cwd),
        repoName: getRepoName(cwd),
        gitBranch: getGitBranch(cwd),
        model: model || existing._userExtensions?.model,
        costUsd: costUsd ?? existing._userExtensions?.costUsd,
      },
    };

    const success = writeRegistry(cwd, updated);
    const duration = Date.now() - startTime;

    if (success) {
      log("info", "Registry metadata updated", {
        session_id: sessionId,
        project_path: cwd,
        event: "metadata_updated",
        duration_ms: duration,
      });
    }

    return success;
  }

  // New session - append to chain
  const shortId = sessionId.split("-")[0];
  const timestamp = new Date().toISOString();
  const newEntry: ChainEntry = { sessionId, shortId, timestamp };

  let chain: ChainEntry[] = existing?.chain || [];
  chain.push(newEntry);

  // Limit chain length
  if (chain.length > MAX_CHAIN_LENGTH) {
    chain = chain.slice(-MAX_CHAIN_LENGTH);
  }

  const registry: SessionRegistry = {
    version: 1,
    currentSessionId: sessionId,
    chain,
    updatedAt: Date.now(),
    _managedBy: PROVENANCE_MARKER,
    _userExtensions: {
      repoHash: hashPath(cwd),
      repoName: getRepoName(cwd),
      gitBranch: getGitBranch(cwd),
      model,
      costUsd,
    },
  };

  const success = writeRegistry(cwd, registry);
  const duration = Date.now() - startTime;

  if (success) {
    const eventType = existing ? "chain_appended" : "registry_created";
    log("info", existing ? "Session appended to chain" : "Registry created", {
      session_id: sessionId,
      project_path: cwd,
      event: eventType,
      duration_ms: duration,
      ctx: { chainLength: chain.length },
    });
  }

  return success;
}
