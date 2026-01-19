/**
 * failure-patterns.ts - Scripted failure outputs for SR&ED discovery hook
 *
 * ADR: 2026-01-18-sred-dynamic-discovery
 *
 * All failure outputs follow a consistent format for testability.
 * The `permissionDecisionReason` explicitly instructs Claude to use AskUserQuestion,
 * ensuring failure is never silent.
 */

export const FAILURE_PATTERNS = {
  NETWORK_TIMEOUT: {
    code: 'NETWORK_TIMEOUT',
    message: 'Discovery failed (network timeout)',
    instruction: 'Please ask the user to confirm or select a different project identifier',
  },
  SDK_ERROR: {
    code: 'SDK_ERROR',
    message: 'Discovery failed (SDK error)',
    instruction: 'Please ask the user to confirm the fallback suggestion or enter manually',
  },
  PARSE_ERROR: {
    code: 'PARSE_ERROR',
    message: 'Discovery failed (invalid response)',
    instruction: 'Please ask the user which project identifier to use',
  },
  OFFLINE: {
    code: 'OFFLINE',
    message: 'Discovery unavailable (offline)',
    instruction: 'Please ask the user to confirm the fallback project identifier',
  },
} as const;

export type FailurePatternCode = keyof typeof FAILURE_PATTERNS;

/**
 * Format a failure message with fallback suggestion and alternatives.
 *
 * @param pattern - The failure pattern code
 * @param fallbackProject - The scope-derived project identifier
 * @param alternatives - List of alternative project identifiers from history
 * @returns Formatted message for permissionDecisionReason
 */
export function formatFailure(
  pattern: FailurePatternCode,
  fallbackProject: string,
  alternatives: string[] = [],
): string {
  const { message, instruction } = FAILURE_PATTERNS[pattern];

  const alternativeLines = alternatives.map((alt) => `- ${alt}`).join('\n');

  return (
    `[SRED-GUARD] ${message}.\n\n` +
    `Fallback suggestion: SRED-Claim: ${fallbackProject}\n` +
    (alternatives.length > 0 ? `Alternatives: ${alternatives.join(', ')}\n` : '') +
    `\n${instruction}:\n` +
    `- ${fallbackProject} (derived from scope)\n` +
    (alternativeLines ? `${alternativeLines}\n` : '') +
    `- Enter manually\n\n` +
    `Then retry the commit with the selected SRED-Claim trailer.`
  );
}

/**
 * Format a success message with AI-suggested project identifier.
 *
 * @param suggestedProject - The AI-suggested project identifier
 * @param reasoning - Why this project was suggested
 * @param alternatives - List of alternative project identifiers
 * @param confidence - Confidence level (0-1)
 * @returns Formatted message for permissionDecisionReason
 */
function getConfidenceLabel(confidence: number): string {
  if (confidence >= 0.8) return 'high';
  if (confidence >= 0.5) return 'medium';
  return 'low';
}

export function formatSuggestion(
  suggestedProject: string,
  reasoning: string,
  alternatives: string[] = [],
  confidence: number = 0.8,
): string {
  const alternativeLines = alternatives.map((alt) => `- ${alt}`).join('\n');
  const confidenceLabel = getConfidenceLabel(confidence);

  return (
    `[SRED-GUARD] Missing SRED-Claim trailer.\n\n` +
    `Suggested project: SRED-Claim: ${suggestedProject}\n` +
    `Confidence: ${confidenceLabel} (${(confidence * 100).toFixed(0)}%)\n` +
    `Reasoning: ${reasoning}\n\n` +
    (alternatives.length > 0
      ? `Alternatives:\n${alternativeLines}\n\n`
      : '') +
    `Please ask the user which project to use, then retry with:\n` +
    `SRED-Claim: <selected-project>`
  );
}

/**
 * Extract project identifier from commit scope.
 *
 * @param scope - The commit scope (e.g., "my-feature")
 * @returns Uppercase project identifier (e.g., "MY-FEATURE")
 */
export function scopeToProject(scope: string): string {
  return scope
    .toUpperCase()
    .replace(/[^A-Z0-9-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
}

/**
 * Extract scope from conventional commit first line.
 *
 * @param firstLine - First line of commit message (e.g., "feat(my-scope): description")
 * @returns The scope or null if not found
 */
export function extractScope(firstLine: string): string | null {
  const match = firstLine.match(/^\w+\(([^)]+)\):/);
  return match ? match[1] : null;
}

/**
 * Generate fallback project identifier from commit message.
 *
 * @param commitMessage - The full commit message
 * @returns Uppercase project identifier derived from scope, or "UNKNOWN-PROJECT"
 */
export function generateFallbackProject(commitMessage: string): string {
  const firstLine = commitMessage.split('\n')[0] || '';
  const scope = extractScope(firstLine);

  if (scope) {
    return scopeToProject(scope);
  }

  return 'UNKNOWN-PROJECT';
}
