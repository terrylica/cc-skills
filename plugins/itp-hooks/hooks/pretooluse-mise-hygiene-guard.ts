#!/usr/bin/env bun
/**
 * PreToolUse hook: mise.toml Hygiene Guard
 *
 * Enforces two critical mise.toml hygiene rules:
 * 1. Line count limit (~100 lines) - suggests hub-spoke refactoring
 * 2. Secrets detection - blocks sensitive data, suggests .mise.local.toml
 *
 * Plan Mode: Automatically skipped when Claude is in planning phase.
 *
 * References:
 * - https://mise.jdx.dev/tasks/task-configuration.html (task_config.includes)
 * - https://mise.jdx.dev/configuration.html (mise.local.toml precedence)
 *
 * ADR: /docs/adr/2026-02-04-mise-hygiene-guard.md
 * ADR: /docs/adr/2026-02-05-plan-mode-detection-hooks.md
 */

import {
  parseStdinOrAllow,
  deny,
  allow,
  isPlanMode,
  createHookLogger,
  trackHookError,
} from "./pretooluse-helpers.ts";

// ============================================================================
// Configuration
// ============================================================================

const CONFIG = {
  // Line count threshold for hub-spoke suggestion
  maxLines: 100,

  // Patterns that indicate secrets (case-insensitive)
  // These should be in .mise.local.toml, not mise.toml
  secretPatterns: [
    /\b(api[_-]?key|apikey)\s*=\s*["'][^"']+["']/i,
    /\b(secret[_-]?key|secretkey)\s*=\s*["'][^"']+["']/i,
    /\b(access[_-]?token|accesstoken)\s*=\s*["'][^"']+["']/i,
    /\b(auth[_-]?token|authtoken)\s*=\s*["'][^"']+["']/i,
    /\b(password|passwd|pwd)\s*=\s*["'][^"']+["']/i,
    /\b(private[_-]?key|privatekey)\s*=\s*["'][^"']+["']/i,
    /\b(credential|credentials)\s*=\s*["'][^"']+["']/i,
    /\bgh[_-]?token\s*=\s*["'][^"']+["']/i,
    /\bgithub[_-]?token\s*=\s*["'][^"']+["']/i,
    /\bnpm[_-]?token\s*=\s*["'][^"']+["']/i,
    /\baws[_-]?(access|secret)[_-]?key\s*=\s*["'][^"']+["']/i,
    /\b(database|db)[_-]?(password|pwd)\s*=\s*["'][^"']+["']/i,
    /\bencryption[_-]?key\s*=\s*["'][^"']+["']/i,
    /\bsigning[_-]?key\s*=\s*["'][^"']+["']/i,
  ],

  // Safe patterns - these reference external sources, not hardcoded secrets
  safePatterns: [
    /\{\{\s*read_file\s*\(/i, // Tera template reading from file
    /\{\{\s*env\.[A-Z_]+\s*\}\}/i, // Tera env var reference
    /\{\{\s*get_env\s*\(/i, // Tera get_env function
    /\{\{\s*op_read\s*\(/i, // 1Password reference
    /\{\{\s*cache\s*\(/i, // Cached external command
    /op:\/\//i, // 1Password URI
    /doppler\s+secrets/i, // Doppler reference
  ],

  // Files to check
  targetFiles: ["mise.toml", ".mise.toml"],

  // Files to ignore (these are meant for local/secrets)
  ignoreFiles: ["mise.local.toml", ".mise.local.toml"],
};

// ============================================================================
// Types
// ============================================================================

interface SecretFinding {
  line: number;
  content: string;
  pattern: string;
}

interface HygieneResult {
  lineCount: number;
  exceedsLimit: boolean;
  secretFindings: SecretFinding[];
  taskCount: number;
}

// ============================================================================
// Detection Functions
// ============================================================================

/**
 * Check if content contains a safe pattern (external reference)
 */
function containsSafePattern(line: string): boolean {
  return CONFIG.safePatterns.some((pattern) => pattern.test(line));
}

/**
 * Detect secrets in content
 */
function detectSecrets(content: string): SecretFinding[] {
  const findings: SecretFinding[] = [];
  const lines = content.split("\n");

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Skip comments
    if (line.trim().startsWith("#")) continue;

    // Skip if line contains safe pattern (external reference)
    if (containsSafePattern(line)) continue;

    // Check each secret pattern
    for (const pattern of CONFIG.secretPatterns) {
      if (pattern.test(line)) {
        findings.push({
          line: i + 1,
          content: line.trim().substring(0, 60) + (line.length > 60 ? "..." : ""),
          pattern: pattern.source.split("\\b")[1]?.split("\\s")[0] || "secret",
        });
        break; // One finding per line is enough
      }
    }
  }

  return findings;
}

/**
 * Count tasks in content
 */
function countTasks(content: string): number {
  // Match [tasks.xxx] or [tasks."xxx:yyy"]
  const taskMatches = content.match(/\[tasks\.["']?[^\]]+["']?\]/g);
  return taskMatches?.length || 0;
}

/**
 * Analyze mise.toml content for hygiene issues
 */
function analyzeContent(content: string): HygieneResult {
  const lines = content.split("\n");
  const lineCount = lines.length;
  const secretFindings = detectSecrets(content);
  const taskCount = countTasks(content);

  return {
    lineCount,
    exceedsLimit: lineCount > CONFIG.maxLines,
    secretFindings,
    taskCount,
  };
}

/**
 * Check if file path is a target mise.toml file
 */
function isTargetFile(filePath: string): boolean {
  const fileName = filePath.split("/").pop() || "";

  // Ignore local files (they're meant for secrets)
  if (CONFIG.ignoreFiles.includes(fileName)) {
    return false;
  }

  return CONFIG.targetFiles.includes(fileName);
}

/**
 * Generate hub-spoke refactoring suggestion
 */
function generateHubSpokeSuggestion(): string {
  const suggestions: string[] = [
    "",
    "**Recommended hub-spoke structure:**",
    "```",
    "mise.toml                    # Hub: [env] + [tools] + [task_config]",
    ".mise/tasks/",
    "  ├── dev.toml              # Spoke: fmt, lint, test, build",
    "  ├── release.toml          # Spoke: release workflow",
    "  └── ...                   # Domain-specific task files",
    "```",
    "",
    "**Add to mise.toml:**",
    "```toml",
    "[task_config]",
    'includes = [".mise/tasks/dev.toml", ".mise/tasks/release.toml"]',
    "```",
    "",
    "**Spoke file format** (no [tasks.] prefix):",
    "```toml",
    "# .mise/tasks/dev.toml",
    "[fmt]",
    'run = "cargo fmt"',
    "",
    '["test:unit"]',
    'depends = ["fmt"]',
    'run = "cargo test"',
    "```",
    "",
    `Reference: https://mise.jdx.dev/tasks/task-configuration.html`,
  ];

  return suggestions.join("\n");
}

/**
 * Generate secrets migration suggestion
 */
function generateSecretsSuggestion(findings: SecretFinding[]): string {
  const suggestions: string[] = [
    "",
    "**Move secrets to .mise.local.toml:**",
    "",
    "1. Create `.mise.local.toml` (same directory as mise.toml)",
    "2. Add to `.gitignore`: `*.local.toml`",
    "3. Move sensitive values there:",
    "",
    "```toml",
    "# .mise.local.toml (gitignored, highest precedence)",
    "[env]",
    'MY_SECRET = "actual-value-here"',
    "```",
    "",
    "**Or use external references in mise.toml:**",
    "",
    "```toml",
    "[env]",
    "# Read from file (recommended)",
    `GH_TOKEN = "{{ read_file(path=env.HOME ~ '/.secrets/gh-token') | trim }}"`,
    "",
    "# 1Password integration",
    `API_KEY = "{{ op_read('op://Vault/Item/credential') }}"`,
    "```",
    "",
    "**Detected secrets:**",
    ...findings.map((f) => `  Line ${f.line}: ${f.content}`),
    "",
    `Reference: https://mise.jdx.dev/configuration.html`,
  ];

  return suggestions.join("\n");
}

// ============================================================================
// Main Hook Logic
// ============================================================================

const logger = createHookLogger("MISE-HYGIENE");

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("MISE-HYGIENE");
  if (!input) return;

  const { tool_name, tool_input } = input;

  // Only check Write and Edit tools
  if (tool_name !== "Write" && tool_name !== "Edit") {
    return allow();
  }

  // Skip in plan mode - planning phase should not be blocked
  const planContext = isPlanMode(input, { checkPermission: true, checkPath: true });
  if (planContext.inPlanMode) {
    logger.debug("Skipping mise hygiene check in plan mode", {
      hook_event: "PreToolUse",
      tool_name,
      trace_id: input.tool_use_id,
      reason: planContext.reason,
    });
    return allow();
  }

  const filePath = tool_input.file_path;
  if (!filePath || !isTargetFile(filePath)) {
    return allow();
  }

  // Get content to analyze
  const content = tool_input.content || tool_input.new_string;
  if (!content) {
    return allow();
  }

  // For Edit tool, we only have partial content - need full file analysis
  // For now, analyze what we have
  const result = analyzeContent(content);

  // Check for secrets (highest priority - block immediately)
  if (result.secretFindings.length > 0) {
    const message = [
      `[MISE-HYGIENE] Secrets detected in mise.toml`,
      "",
      `Found ${result.secretFindings.length} potential secret(s) that should NOT be committed.`,
      `mise.toml is meant to be shared; secrets belong in .mise.local.toml (gitignored).`,
      generateSecretsSuggestion(result.secretFindings),
    ].join("\n");

    return deny(message);
  }

  // Check line count (for Write tool with full content)
  if (tool_name === "Write" && result.exceedsLimit) {
    const message = [
      `[MISE-HYGIENE] mise.toml exceeds ${CONFIG.maxLines} lines (${result.lineCount} lines)`,
      "",
      `Large mise.toml files become hard to maintain. Consider hub-spoke refactoring:`,
      `- Keep [env], [tools], [task_config] in root mise.toml (hub)`,
      `- Move [tasks.*] to .mise/tasks/*.toml files (spokes)`,
      generateHubSpokeSuggestion(),
    ].join("\n");

    return deny(message);
  }

  return allow();
}

main().catch((err) => {
  trackHookError("pretooluse-mise-hygiene-guard", err instanceof Error ? err.message : String(err));
  allow(); // Fail-open: don't block on errors
});
