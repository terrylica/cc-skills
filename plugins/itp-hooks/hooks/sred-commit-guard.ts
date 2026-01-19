#!/usr/bin/env bun
/**
 * sred-commit-guard.ts - Claude Code PreToolUse hook for SR&ED commit enforcement
 *
 * ADR: 2026-01-18-sred-dynamic-discovery
 *
 * Validates commits include BOTH conventional commit type AND SR&ED git trailers.
 * Provides comprehensive educational feedback when blocking.
 * Uses dynamic discovery via Claude Agent SDK for project identifier suggestions.
 *
 * Usage:
 *   PreToolUse: Piped JSON with tool_input.command containing git commit
 *   Git hook:   bun sred-commit-guard.ts --git-hook <commit-msg-file>
 */

import { discoverProject, formatDiscoveryResult } from './sred-discovery';
import { type PreToolUseInput } from './pretooluse-helpers.ts';

// ============================================================================
// CONFIGURATION
// ============================================================================

const CONVENTIONAL_TYPES = [
  'feat', 'fix', 'docs', 'style', 'refactor',
  'perf', 'test', 'build', 'ci', 'chore', 'revert'
] as const;

// Valid SRED-Type values per CRA glossary
// ADR: 2026-01-18-sred-dynamic-discovery
const SRED_TYPES: Record<string, string> = {
  'experimental-development': 'Achieving technological advancement through systematic work',
  'applied-research': 'Scientific knowledge with specific practical application in view',
  'basic-research': 'Scientific knowledge without specific practical application',
  'support-work': 'Programming, testing, data collection supporting SR&ED activities',
};

// Project identifier format: PROJECT[-VARIANT] (uppercase)
// Year/quarter extracted from git commit timestamp at CRA report time
// ADR: 2026-01-18-sred-dynamic-discovery
const PROJECT_ID_PATTERN = /^[A-Z][A-Z0-9]*(-[A-Z][A-Z0-9]*)*$/;

const CONFIG = {
  requireSredType: true,
  requireSredClaim: true,  // Now mandatory for proper tracking
};

// ============================================================================
// TYPES
// ============================================================================

// PreToolUseInput imported from ./pretooluse-helpers.ts

interface ValidationError {
  field: string;
  message: string;
}

interface HookResult {
  exitCode: number;
  stdout?: string;
  stderr?: string;
}

// ============================================================================
// EDUCATIONAL REFERENCE MATERIAL
// ============================================================================

const REFERENCE_MATERIAL = `
## Git Commit Format Reference

This project requires commits to include BOTH conventional commit format
AND SR&ED (Scientific Research & Experimental Development) metadata for
Canada CRA tax credit compliance.

### Required Format

\`\`\`
<type>(<scope>): <subject>

<body>

SRED-Type: <category>
SRED-Claim: <claim-id>
\`\`\`

### Conventional Commit Types

| Type       | When to Use                                    |
|------------|------------------------------------------------|
| feat       | New feature or capability                      |
| fix        | Bug fix                                        |
| docs       | Documentation only changes                     |
| style      | Formatting, missing semicolons, etc.           |
| refactor   | Code change that neither fixes nor adds        |
| perf       | Performance improvement                        |
| test       | Adding or correcting tests                     |
| build      | Build system or external dependencies          |
| ci         | CI configuration files and scripts             |
| chore      | Maintenance tasks                              |
| revert     | Reverting a previous commit                    |

### SR&ED Types (CRA Definitions)

| Type                       | CRA Definition                                |
|----------------------------|-----------------------------------------------|
| experimental-development   | Achieving technological advancement through   |
|                            | systematic work                               |
| applied-research           | Scientific knowledge with specific practical  |
|                            | application in view                           |
| basic-research             | Scientific knowledge without specific         |
|                            | practical application                         |
| support-work               | Programming, testing, data collection         |
|                            | supporting SR&ED activities                   |

### Project Identifier Format

Format: \`PROJECT[-VARIANT]\` (uppercase)
- PROJECT: Internal project name derived from commit scope
- VARIANT: Optional sub-project identifier

Examples: \`MY-PROJECT\`, \`MY-PROJECT-VARIANT\`, \`FEATURE-X\`

Year and quarter are automatically extracted from git commit timestamps
at CRA report time - no need to include in the project identifier.

### Git Trailer Syntax

Git trailers are key-value metadata at the END of commit messages:
- Must be preceded by a blank line
- Format: \`Key: Value\` (key, colon, space, value)
- Machine-parseable with: \`git interpret-trailers --parse\`
- Extractable with: \`git log --format='%(trailers:key=SRED-Type,valueonly)'\`

### Complete Examples

**Example 1: Feature with Experimental Development**
\`\`\`
feat(my-feature): implement adaptive threshold algorithm

Adds regime-aware threshold adjustment for epoch detection.
Uses rolling windows for baseline calculation with dynamic adjustment.

SRED-Type: experimental-development
SRED-Claim: MY-FEATURE
\`\`\`

**Example 2: Performance with Experimental Development**
\`\`\`
perf(optimization): optimize SIMD vectorization for calculation

Benchmarks show 4.2x speedup over scalar implementation for datasets
exceeding 100K points. Memory bandwidth saturation observed at 1M+ points.

SRED-Type: experimental-development
SRED-Claim: OPTIMIZATION
\`\`\`

**Example 3: Fix with Applied Research**
\`\`\`
fix(metrics): correct ratio annualization for different markets

The original implementation assumed 252 trading days. Different markets
operate 365 days, requiring adjusted annualization factor.

SRED-Type: applied-research
SRED-Claim: METRICS
\`\`\`

### Extraction for CRA Claims

\`\`\`bash
# List all SR&ED commits
git log --format='%H|%ad|%s|%(trailers:key=SRED-Type,valueonly)' --date=short | grep -v '|$'

# Sum by category
git log --format='%(trailers:key=SRED-Type,valueonly)' | sort | uniq -c

# Export for claim period
git log --since="2026-01-01" --until="2026-03-31" \\
  --format='%ad|%s|%(trailers:key=SRED-Type,valueonly)|%(trailers:key=SRED-Claim,valueonly)' \\
  --date=short
\`\`\`
`;

// ============================================================================
// VALIDATION FUNCTIONS
// ============================================================================

function validateConventionalType(firstLine: string): ValidationError | null {
  const pattern = new RegExp(`^(${CONVENTIONAL_TYPES.join('|')})(\\(.+\\))?: .+`);

  if (!pattern.test(firstLine)) {
    return {
      field: 'type',
      message: `Invalid or missing conventional commit type.

Expected format: <type>(<scope>): <subject>
Valid types: ${CONVENTIONAL_TYPES.join(', ')}`
    };
  }
  return null;
}

function validateSredType(message: string): ValidationError | null {
  if (!CONFIG.requireSredType) return null;

  const validTypes = Object.keys(SRED_TYPES);
  const pattern = new RegExp(`^SRED-Type:\\s*(${validTypes.join('|')})`, 'm');

  if (!pattern.test(message)) {
    const typeList = Object.entries(SRED_TYPES)
      .map(([type, desc]) => `  SRED-Type: ${type}\n    → ${desc}`)
      .join('\n\n');

    return {
      field: 'SRED-Type',
      message: `Missing or invalid SRED-Type trailer.

Required for SR&ED (Scientific Research & Experimental Development)
tax credit compliance with Canada Revenue Agency.

Add one of the following at the END of your commit message:

${typeList}`
    };
  }
  return null;
}

function validateSredClaim(message: string): ValidationError | null {
  if (!CONFIG.requireSredClaim) return null;

  const pattern = /^SRED-Claim:\s*(.+)/m;
  const match = message.match(pattern);

  if (!match) {
    // Missing SRED-Claim - will trigger discovery in async validation
    return {
      field: 'SRED-Claim',
      message: `Missing SRED-Claim trailer.

Required for SR&ED project tracking and year-end T661 form preparation.

Format: PROJECT[-VARIANT] (uppercase)
Examples: MY-PROJECT, MY-PROJECT-VARIANT, FEATURE-X

Add at the END of your commit message:
  SRED-Claim: <PROJECT-IDENTIFIER>`
    };
  }

  // Validate format only - no hardcoded registry
  const claimId = match[1].trim();
  if (!PROJECT_ID_PATTERN.test(claimId)) {
    return {
      field: 'SRED-Claim',
      message: `Invalid SRED-Claim format: "${claimId}"

Project identifier must be:
- Uppercase letters and numbers only
- Format: PROJECT[-VARIANT]
- Start with a letter
- Use hyphens to separate parts

Examples: MY-PROJECT, MY-PROJECT-VARIANT, FEATURE-X`
    };
  }

  return null;
}

function validateCommitMessage(message: string): ValidationError[] {
  const errors: ValidationError[] = [];
  const lines = message.split('\n');
  const firstLine = lines[0] || '';

  const typeError = validateConventionalType(firstLine);
  if (typeError) errors.push(typeError);

  const sredTypeError = validateSredType(message);
  if (sredTypeError) errors.push(sredTypeError);

  const sredClaimError = validateSredClaim(message);
  if (sredClaimError) errors.push(sredClaimError);

  return errors;
}

// ============================================================================
// OUTPUT FORMATTERS
// ============================================================================

function formatBlockResponse(errors: ValidationError[], originalMessage: string): string {
  const errorList = errors
    .map((e, i) => `### Error ${i + 1}: ${e.field}\n\n${e.message}`)
    .join('\n\n---\n\n');

  return `[SRED-COMMIT-GUARD] Commit blocked - validation failed

## Validation Errors

${errorList}

---

## Your Commit Message

\`\`\`
${originalMessage}
\`\`\`

---

${REFERENCE_MATERIAL}`;
}

function formatNoVerifyBlock(): string {
  return `[SRED-COMMIT-GUARD] Commit blocked - --no-verify not allowed

## Why This Is Blocked

The \`--no-verify\` flag bypasses all git hooks, including SR&ED compliance validation.

For Canada CRA SR&ED tax credit claims, all commits must be validated to ensure
proper documentation of:
- Technological uncertainty addressed
- Systematic investigation performed
- Technological advancement achieved

## Solution

Remove \`--no-verify\` (or \`-n\`) from your git commit command and ensure your
commit message includes required SR&ED metadata.

---

${REFERENCE_MATERIAL}`;
}

function createClaudeBlockOutput(reason: string): string {
  const output = {
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason
    }
  };
  return JSON.stringify(output, null, 2);
}

// ============================================================================
// MAIN EXECUTION - Pure function returning result, no process.exit in logic
// ============================================================================

async function runHook(): Promise<HookResult> {
  const args = process.argv.slice(2);

  // Git hook mode
  if (args[0] === '--git-hook') {
    const filePath = args[1] || '.git/COMMIT_EDITMSG';
    const file = Bun.file(filePath);

    const exists = await file.exists();
    if (!exists) {
      return {
        exitCode: 1,
        stderr: `ERROR: Commit message file not found: ${filePath}`
      };
    }

    const message = await file.text();
    const errors = validateCommitMessage(message);

    if (errors.length > 0) {
      return {
        exitCode: 1,
        stderr: formatBlockResponse(errors, message)
      };
    }

    return {
      exitCode: 0,
      stdout: '[SRED-COMMIT-GUARD] Commit message valid.'
    };
  }

  // Claude Code PreToolUse mode - read JSON from stdin
  const stdin = await Bun.stdin.text();
  if (!stdin.trim()) {
    return { exitCode: 0 }; // Empty stdin, allow through
  }

  let input: PreToolUseInput;
  try {
    input = JSON.parse(stdin);
  } catch (parseError: unknown) {
    // Invalid JSON from stdin - not a tool call we can process
    // Log error for visibility but allow through
    const errorMessage = parseError instanceof Error ? parseError.message : String(parseError);
    return {
      exitCode: 0,
      stderr: `[SRED-COMMIT-GUARD] JSON parse error (allowing through): ${errorMessage}`
    };
  }

  // Only intercept Bash tool
  if (input.tool_name !== 'Bash') {
    return { exitCode: 0 };
  }

  const command = input.tool_input?.command || '';

  // Only intercept git commit commands
  if (!/\bgit\s+commit\b/.test(command)) {
    return { exitCode: 0 };
  }

  // Block --no-verify attempts
  if (/--no-verify|-n\s/.test(command)) {
    return {
      exitCode: 0,
      stdout: createClaudeBlockOutput(formatNoVerifyBlock())
    };
  }

  // Extract commit message from -m flag
  const messageMatch = command.match(/-m\s+["']([^"']+)["']/) ||
                       command.match(/-m\s+"([^"]+)"/) ||
                       command.match(/-m\s+'([^']+)'/);

  if (!messageMatch) {
    // No inline message (using editor) - allow, git hook will validate
    return { exitCode: 0 };
  }

  const commitMessage = messageMatch[1]
    .replace(/\\n/g, '\n')  // Handle escaped newlines
    .replace(/\\t/g, '\t'); // Handle escaped tabs

  const errors = validateCommitMessage(commitMessage);

  // Check if only SRED-Claim is missing - trigger discovery
  const hasSredClaimError = errors.some((e) => e.field === 'SRED-Claim' && e.message.includes('Missing'));
  const otherErrors = errors.filter((e) => e.field !== 'SRED-Claim' || !e.message.includes('Missing'));

  if (hasSredClaimError && otherErrors.length === 0) {
    // Only SRED-Claim is missing - use dynamic discovery
    try {
      const discoveryResult = await discoverProject(commitMessage);
      const reason = formatDiscoveryResult(discoveryResult);
      return {
        exitCode: 0,
        stdout: createClaudeBlockOutput(reason),
      };
    } catch {
      // Discovery failed completely - use basic error message
      return {
        exitCode: 0,
        stdout: createClaudeBlockOutput(formatBlockResponse(errors, commitMessage)),
      };
    }
  }

  if (errors.length > 0) {
    return {
      exitCode: 0,
      stdout: createClaudeBlockOutput(formatBlockResponse(errors, commitMessage))
    };
  }

  // Valid - allow commit
  return { exitCode: 0 };
}

// ============================================================================
// ENTRY POINT - Single location for process.exit
// ============================================================================

async function main(): Promise<never> {
  let result: HookResult;

  try {
    result = await runHook();
  } catch (unexpectedError: unknown) {
    // Unexpected error - log full details for debugging
    console.error('[SRED-COMMIT-GUARD] Unexpected error:');
    if (unexpectedError instanceof Error) {
      console.error(`  Message: ${unexpectedError.message}`);
      console.error(`  Stack: ${unexpectedError.stack}`);
    } else {
      console.error(`  Value: ${String(unexpectedError)}`);
    }
    // Allow through to avoid blocking on hook bugs
    return process.exit(0);
  }

  // Output results
  if (result.stderr) {
    console.error(result.stderr);
  }
  if (result.stdout) {
    console.log(result.stdout);
  }

  return process.exit(result.exitCode);
}

// Run main
void main();
