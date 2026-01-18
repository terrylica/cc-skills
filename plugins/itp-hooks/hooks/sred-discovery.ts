/**
 * sred-discovery.ts - SR&ED project identifier discovery via Claude Agent SDK
 *
 * ADR: 2026-01-18-sred-dynamic-discovery
 *
 * Spawns an isolated Haiku session to analyze git history and suggest
 * appropriate SR&ED project identifiers for commits missing SRED-Claim trailers.
 *
 * Key features:
 * - Uses Claude Agent SDK with settingSources: [] for hook isolation
 * - 8-second internal timeout for responsive git commit flow
 * - Offline detection with 100ms TCP check
 * - Scope-based caching with 5-minute TTL
 * - Fallback to scope-derived project on errors
 */

import { createHash } from 'crypto';
import { mkdir } from 'fs/promises';
import { join } from 'path';
import { z } from 'zod';
import {
  formatFailure,
  formatSuggestion,
  generateFallbackProject,
  type FailurePatternCode,
} from './failure-patterns';

// ============================================================================
// TYPES
// ============================================================================

export interface DiscoveryResult {
  suggestedProject: string;
  alternatives: string[];
  reasoning: string;
  confidence: number;
  fromCache: boolean;
}

export interface DiscoveryError {
  code: FailurePatternCode;
  fallbackProject: string;
  alternatives: string[];
}

// Zod schema for SDK response validation
const SdkResponseSchema = z.object({
  suggestedProject: z.string(),
  alternatives: z.array(z.string()).default([]),
  reasoning: z.string(),
  confidence: z.number().min(0).max(1),
});

// ============================================================================
// CONFIGURATION
// ============================================================================

const CONFIG = {
  /** Internal timeout for SDK calls (ms) */
  sdkTimeout: 8000,
  /** Network check timeout (ms) */
  networkCheckTimeout: 100,
  /** Cache TTL (ms) - 5 minutes */
  cacheTtl: 5 * 60 * 1000,
  /** Cache directory */
  cacheDir: join(process.env.HOME || '~', '.cache', 'sred-hook', 'suggestions'),
  /** Max input size (bytes) */
  maxInputSize: 4096,
  /** Anthropic API host for connectivity check */
  apiHost: 'api.anthropic.com',
  /** Anthropic API port */
  apiPort: 443,
  /** Days of git history to analyze */
  historyDays: 365,
};

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Sanitize input by removing control characters and truncating.
 */
export function sanitizeInput(input: string): string {
  // Remove control characters except newlines and tabs
  const cleaned = input.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
  return cleaned.slice(0, CONFIG.maxInputSize);
}

/**
 * Generate cache key from commit scope and staged files.
 */
export function generateCacheKey(scope: string, stagedFiles: string[] = []): string {
  const content = [scope, ...stagedFiles.sort()].join('\n');
  return createHash('sha256').update(content).digest('hex').slice(0, 16);
}

/**
 * Check if network is available by attempting TCP connection.
 */
async function checkNetworkConnectivity(): Promise<boolean> {
  return new Promise((resolve) => {
    const net = require('net');
    const socket = new net.Socket();

    const timeout = setTimeout(() => {
      socket.destroy();
      resolve(false);
    }, CONFIG.networkCheckTimeout);

    socket.connect(CONFIG.apiPort, CONFIG.apiHost, () => {
      clearTimeout(timeout);
      socket.destroy();
      resolve(true);
    });

    socket.on('error', () => {
      clearTimeout(timeout);
      socket.destroy();
      resolve(false);
    });
  });
}

/**
 * Read cached suggestion if valid.
 */
async function readCache(cacheKey: string): Promise<DiscoveryResult | null> {
  try {
    const cachePath = join(CONFIG.cacheDir, `${cacheKey}.json`);
    const file = Bun.file(cachePath);

    if (!(await file.exists())) {
      return null;
    }

    const content = await file.json();
    const cachedAt = new Date(content.cachedAt).getTime();

    if (Date.now() - cachedAt > CONFIG.cacheTtl) {
      return null;
    }

    return { ...content.result, fromCache: true };
  } catch {
    return null;
  }
}

/**
 * Write suggestion to cache.
 */
async function writeCache(cacheKey: string, result: DiscoveryResult): Promise<void> {
  try {
    await mkdir(CONFIG.cacheDir, { recursive: true });
    const cachePath = join(CONFIG.cacheDir, `${cacheKey}.json`);
    await Bun.write(cachePath, JSON.stringify({
      cachedAt: new Date().toISOString(),
      result,
    }, null, 2));
  } catch {
    // Cache write failures are non-fatal
  }
}

/**
 * Get existing SR&ED projects from git history.
 */
async function getExistingProjects(): Promise<string[]> {
  try {
    const proc = Bun.spawn([
      'git', 'log',
      `--since=${CONFIG.historyDays} days ago`,
      '--format=%(trailers:key=SRED-Claim,valueonly)',
    ], {
      stdout: 'pipe',
      stderr: 'pipe',
    });

    const output = await new Response(proc.stdout).text();
    const projects = output
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.length > 0);

    // Return unique projects
    return [...new Set(projects)];
  } catch {
    return [];
  }
}

// ============================================================================
// SDK INTEGRATION
// ============================================================================

/**
 * Query Haiku for project suggestion.
 */
async function queryHaiku(
  commitMessage: string,
  existingProjects: string[],
): Promise<DiscoveryResult> {
  // Dynamic import to handle SDK availability
  const { query } = await import('@anthropic-ai/claude-agent-sdk');

  const projectList = existingProjects.length > 0
    ? `Existing projects in history: ${existingProjects.join(', ')}`
    : 'No existing SR&ED projects found in history.';

  const prompt = `Analyze this git commit and suggest an appropriate SR&ED project identifier.

Commit message:
${sanitizeInput(commitMessage)}

${projectList}

Instructions:
1. If the commit scope matches an existing project, suggest that project
2. If no match, derive a new project identifier from the scope (uppercase, PROJECT[-VARIANT] format)
3. List up to 3 alternatives
4. Provide brief reasoning for your suggestion
5. Rate your confidence (0.0-1.0)

Respond with JSON only:
{
  "suggestedProject": "PROJECT-NAME",
  "alternatives": ["ALT-1", "ALT-2"],
  "reasoning": "Brief explanation",
  "confidence": 0.8
}`;

  let response = '';

  // Create abort controller for timeout
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), CONFIG.sdkTimeout);

  try {
    for await (const msg of query({
      prompt,
      options: {
        settingSources: [], // No filesystem settings = hook isolation
        model: 'haiku',
        maxTurns: 2,
        allowedTools: ['Bash'],
      },
    })) {
      if (msg.type === 'text') {
        response += msg.content;
      }
    }
  } finally {
    clearTimeout(timeoutId);
  }

  // Parse JSON from response
  const jsonMatch = response.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    throw new Error('No JSON found in response');
  }

  const parsed = JSON.parse(jsonMatch[0]);
  const validated = SdkResponseSchema.parse(parsed);

  return {
    ...validated,
    fromCache: false,
  };
}

// ============================================================================
// MAIN DISCOVERY FUNCTION
// ============================================================================

/**
 * Discover SR&ED project identifier for a commit.
 *
 * @param commitMessage - The full commit message
 * @returns Either a successful discovery result or an error with fallback
 */
export async function discoverProject(
  commitMessage: string,
): Promise<{ success: true; result: DiscoveryResult } | { success: false; error: DiscoveryError }> {
  // Defense-in-depth: Skip if spawned from another hook
  if (process.env.CLAUDE_HOOK_SPAWNED === '1') {
    const fallbackProject = generateFallbackProject(commitMessage);
    return {
      success: false,
      error: {
        code: 'SDK_ERROR',
        fallbackProject,
        alternatives: [],
      },
    };
  }

  const sanitized = sanitizeInput(commitMessage);
  const firstLine = sanitized.split('\n')[0] || '';
  const scopeMatch = firstLine.match(/^\w+\(([^)]+)\):/);
  const scope = scopeMatch ? scopeMatch[1] : 'unknown';

  // Generate cache key
  const cacheKey = generateCacheKey(scope);

  // Check cache
  const cached = await readCache(cacheKey);
  if (cached) {
    return { success: true, result: cached };
  }

  // Check network connectivity
  const isOnline = await checkNetworkConnectivity();
  if (!isOnline) {
    const fallbackProject = generateFallbackProject(commitMessage);
    const existingProjects = await getExistingProjects();
    return {
      success: false,
      error: {
        code: 'OFFLINE',
        fallbackProject,
        alternatives: existingProjects.slice(0, 3),
      },
    };
  }

  // Query Haiku
  try {
    const existingProjects = await getExistingProjects();
    const result = await queryHaiku(commitMessage, existingProjects);

    // Cache the result
    await writeCache(cacheKey, result);

    return { success: true, result };
  } catch (error) {
    const fallbackProject = generateFallbackProject(commitMessage);
    const existingProjects = await getExistingProjects();

    let code: FailurePatternCode = 'SDK_ERROR';
    if (error instanceof Error) {
      if (error.name === 'AbortError' || error.message.includes('timeout')) {
        code = 'NETWORK_TIMEOUT';
      } else if (error.message.includes('JSON') || error.message.includes('parse')) {
        code = 'PARSE_ERROR';
      }
    }

    return {
      success: false,
      error: {
        code,
        fallbackProject,
        alternatives: existingProjects.slice(0, 3),
      },
    };
  }
}

/**
 * Format discovery result as permissionDecisionReason.
 */
export function formatDiscoveryResult(
  discoveryResult: { success: true; result: DiscoveryResult } | { success: false; error: DiscoveryError },
): string {
  if (discoveryResult.success) {
    const { result } = discoveryResult;
    return formatSuggestion(
      result.suggestedProject,
      result.reasoning,
      result.alternatives,
      result.confidence,
    );
  } else {
    const { error } = discoveryResult;
    return formatFailure(
      error.code,
      error.fallbackProject,
      error.alternatives,
    );
  }
}
