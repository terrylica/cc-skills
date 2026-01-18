#!/usr/bin/env bun
/**
 * sred-commit-guard.ts - Claude Code PreToolUse hook for SR&ED commit enforcement
 *
 * Validates commits include BOTH conventional commit type AND SR&ED git trailers.
 * Provides comprehensive educational feedback when blocking.
 *
 * Usage:
 *   PreToolUse: Piped JSON with tool_input.command containing git commit
 *   Git hook:   bun sred-commit-guard.ts --git-hook <commit-msg-file>
 */

// ============================================================================
// CONFIGURATION
// ============================================================================

const CONVENTIONAL_TYPES = [
  'feat', 'fix', 'docs', 'style', 'refactor',
  'perf', 'test', 'build', 'ci', 'chore', 'revert'
] as const;

const SRED_TYPES: Record<string, string> = {
  'experimental-development': 'Work undertaken to achieve technological advancement through systematic investigation or search by experiment',
  'applied-research': 'Work undertaken to advance scientific knowledge with a specific practical application in view',
  'basic-research': 'Work undertaken to advance scientific knowledge without a specific practical application in view',
  'systematic-investigation': 'Work involving systematic investigation through hypothesis testing and experimentation'
};

const CONFIG = {
  requireSredType: true,
  requireSredClaim: false,
};

// ============================================================================
// TYPES
// ============================================================================

interface PreToolUseInput {
  tool_name: string;
  tool_input: {
    command?: string;
  };
  tool_use_id?: string;
  cwd?: string;
}

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

### SR&ED Categories (CRA Definitions)

| Category                   | CRA Definition                                |
|----------------------------|-----------------------------------------------|
| experimental-development   | Systematic work using scientific knowledge    |
|                            | to produce new materials, devices, products,  |
|                            | or processes, or to improve existing ones     |
| applied-research           | Original investigation to acquire new         |
|                            | scientific knowledge with specific practical  |
|                            | application in view                           |
| basic-research             | Original investigation to acquire new         |
|                            | scientific knowledge without specific         |
|                            | practical application in view                 |
| systematic-investigation   | Work involving hypothesis, testing, and       |
|                            | analysis to resolve technological uncertainty |

### Git Trailer Syntax

Git trailers are key-value metadata at the END of commit messages:
- Must be preceded by a blank line
- Format: \`Key: Value\` (key, colon, space, value)
- Machine-parseable with: \`git interpret-trailers --parse\`
- Extractable with: \`git log --format='%(trailers:key=SRED-Type,valueonly)'\`

### Complete Examples

**Example 1: Feature with Experimental Development**
\`\`\`
feat(ith-python): implement adaptive TMAEG threshold algorithm

Adds volatility-regime-aware threshold adjustment for ITH epoch detection.
Uses rolling 60-day windows for baseline calculation with dynamic adjustment
based on realized volatility vs implied volatility spread.

SRED-Type: experimental-development
SRED-Claim: 2026-Q1-ITH
\`\`\`

**Example 2: Performance with Systematic Investigation**
\`\`\`
perf(core-rust): optimize SIMD vectorization for fitness calculation

Benchmarks show 4.2x speedup over scalar implementation for datasets
exceeding 100K points. Memory bandwidth saturation observed at 1M+ points.

SRED-Type: systematic-investigation
SRED-Claim: 2026-Q1-ITH
\`\`\`

**Example 3: Fix with Applied Research**
\`\`\`
fix(metrics): correct Sharpe ratio annualization for crypto markets

The original implementation assumed 252 trading days. Crypto markets
operate 365 days, requiring adjusted annualization factor.

SRED-Type: applied-research
SRED-Claim: 2026-Q1-ITH
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

  const pattern = /^SRED-Claim:\s*.+/m;

  if (!pattern.test(message)) {
    return {
      field: 'SRED-Claim',
      message: `Missing SRED-Claim trailer.

Add at the END of your commit message:
  SRED-Claim: <claim-id>

Example: SRED-Claim: 2026-Q1-ITH`
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
