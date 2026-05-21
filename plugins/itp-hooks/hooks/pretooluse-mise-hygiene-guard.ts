#!/usr/bin/env bun
/**
 * PreToolUse hook: mise.toml Hygiene Guard (iter-88 orchestrator-inlined)
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
 *
 * Iter-88 dual-use contract (mirrors iter-85/86/87 migrations):
 *   - Standalone CLI mode (preserved for backward-compat + direct testing):
 *     `bun pretooluse-mise-hygiene-guard.ts < payload.json` runs main()
 *     under `import.meta.main` guard.
 *   - Orchestrator-inlined mode (NEW owner of the Write|Edit hooks.json slot):
 *     The orchestrator imports `classifyMiseHygieneGuardForOrchestrator`
 *     and invokes it directly in the single bun process. Conforms to
 *     PreToolUseSubhookContract.
 */

import {
  parseStdinOrAllow,
  deny,
  allow,
  isPlanMode,
  createHookLogger,
  trackHookError,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import {
  ALLOW_DECISION,
  denyDecision,
  isFileEditToolNameHonoredByPreToolUseBlockingSubhook,
  type PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";

// ============================================================================
// Configuration
// ============================================================================

const MISE_HYGIENE_GUARD_CONFIG = {
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
  ] as const,

  // Safe patterns - these reference external sources, not hardcoded secrets
  safePatterns: [
    /\{\{\s*read_file\s*\(/i, // Tera template reading from file
    /\{\{\s*env\.[A-Z_]+\s*\}\}/i, // Tera env var reference
    /\{\{\s*get_env\s*\(/i, // Tera get_env function
    /\{\{\s*op_read\s*\(/i, // 1Password reference
    /\{\{\s*cache\s*\(/i, // Cached external command
    /op:\/\//i, // 1Password URI
    /doppler\s+secrets/i, // Doppler reference
  ] as const,

  // Files to check
  targetFiles: ["mise.toml", ".mise.toml"] as const,

  // Files to ignore (these are meant for local/secrets)
  ignoreFiles: ["mise.local.toml", ".mise.local.toml"] as const,
} as const;

// ============================================================================
// Types
// ============================================================================

interface SecretFindingInMiseTomlContent {
  line: number;
  content: string;
  pattern: string;
}

interface MiseTomlHygieneAnalysisResult {
  lineCount: number;
  exceedsLineCountLimit: boolean;
  secretFindings: SecretFindingInMiseTomlContent[];
  taskCount: number;
}

// ============================================================================
// Detection Functions
// ============================================================================

/** Check if a single line contains a safe external-reference pattern. */
function lineContainsKnownSafeExternalReferencePattern(line: string): boolean {
  return MISE_HYGIENE_GUARD_CONFIG.safePatterns.some((pattern) => pattern.test(line));
}

/** Detect secrets in mise.toml content, line-by-line with safe-pattern filtering. */
function detectSecretLiteralsInMiseTomlContent(content: string): SecretFindingInMiseTomlContent[] {
  const findings: SecretFindingInMiseTomlContent[] = [];
  const lines = content.split("\n");

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line) continue;

    // Skip comments
    if (line.trim().startsWith("#")) continue;

    // Skip if line contains safe pattern (external reference)
    if (lineContainsKnownSafeExternalReferencePattern(line)) continue;

    // Check each secret pattern
    for (const pattern of MISE_HYGIENE_GUARD_CONFIG.secretPatterns) {
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

/** Count [tasks.*] sections via regex match. */
function countMiseTaskSections(content: string): number {
  const taskMatches = content.match(/\[tasks\.["']?[^\]]+["']?\]/g);
  return taskMatches?.length || 0;
}

/** Analyze full mise.toml content for hygiene issues. */
function analyzeMiseTomlContentForHygieneViolations(content: string): MiseTomlHygieneAnalysisResult {
  const lines = content.split("\n");
  const lineCount = lines.length;
  const secretFindings = detectSecretLiteralsInMiseTomlContent(content);
  const taskCount = countMiseTaskSections(content);

  return {
    lineCount,
    exceedsLineCountLimit: lineCount > MISE_HYGIENE_GUARD_CONFIG.maxLines,
    secretFindings,
    taskCount,
  };
}

/** Check if file path is a target mise.toml file (and NOT a local ignore-file). */
function isTargetMiseTomlFileNotLocalIgnoreFile(filePath: string): boolean {
  const fileName = filePath.split("/").pop() || "";

  // Ignore local files (they're meant for secrets)
  if ((MISE_HYGIENE_GUARD_CONFIG.ignoreFiles as readonly string[]).includes(fileName)) {
    return false;
  }

  return (MISE_HYGIENE_GUARD_CONFIG.targetFiles as readonly string[]).includes(fileName);
}

/** Build the hub-spoke refactoring suggestion text shown in deny reasons. */
function buildHubSpokeRefactoringSuggestionText(): string {
  return [
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
    "Reference: https://mise.jdx.dev/tasks/task-configuration.html",
  ].join("\n");
}

/** Build the secrets-migration suggestion text shown in deny reasons. */
function buildSecretsMigrationToMiseLocalTomlSuggestionText(
  findings: SecretFindingInMiseTomlContent[],
): string {
  return [
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
    "Reference: https://mise.jdx.dev/configuration.html",
  ].join("\n");
}

// ============================================================================
// Pure classifier (iter-88 orchestrator-inlineable contract)
// ============================================================================

const logger = createHookLogger("MISE-HYGIENE");

/**
 * Pure classifier conforming to PreToolUseSubhookClassifierFunction.
 *
 * Identical 2-policy logic to the pre-iter-88 main() body, but factored
 * out so the orchestrator can invoke it without subprocess-spawning this
 * file (which would defeat the orchestrator's ~17ms empirical cold-start
 * saving — iter-87 microbenchmark).
 *
 * Short-circuit order (cheap → expensive):
 *   1. tool_name not Write/Edit → ALLOW
 *   2. plan mode → ALLOW
 *   3. file is not mise.toml or is .mise.local.toml → ALLOW
 *   4. no content → ALLOW
 *   5. secrets detected → DENY (highest-priority block)
 *   6. Write + line count > 100 → DENY (hub-spoke suggestion)
 *   7. all clean → ALLOW
 *
 * MUST NOT call allow()/deny() or touch stdin/stdout/process.exit.
 */
export async function classifyMiseHygieneGuardForOrchestrator(
  input: PreToolUseInput,
): Promise<PreToolUseSubhookDecision> {
  const { tool_name, tool_input } = input;

  // Iter-102: route through canonical contract helper (closes iter-101 residual gap).
  if (!isFileEditToolNameHonoredByPreToolUseBlockingSubhook(tool_name)) {
    return ALLOW_DECISION;
  }
  // Iter-102 staged-migration short-circuit: MultiEdit payload-shape
  // adaptation is iter-103+ per-classifier work. Preserves status quo.
  if (tool_name === "MultiEdit") {
    return ALLOW_DECISION;
  }

  // Skip in plan mode
  const planContext = isPlanMode(input, { checkPermission: true, checkPath: true });
  if (planContext.inPlanMode) {
    logger.debug("Skipping mise hygiene check in plan mode", {
      hook_event: "PreToolUse",
      tool_name,
      trace_id: input.tool_use_id,
      reason: planContext.reason,
    });
    return ALLOW_DECISION;
  }

  const filePath = tool_input?.file_path;
  if (!filePath || !isTargetMiseTomlFileNotLocalIgnoreFile(filePath)) {
    return ALLOW_DECISION;
  }

  // Get content to analyze
  const content = (tool_input?.content as string) || (tool_input?.new_string as string);
  if (!content) {
    return ALLOW_DECISION;
  }

  const result = analyzeMiseTomlContentForHygieneViolations(content);

  // POLICY 1: Secrets detected → DENY (highest priority)
  if (result.secretFindings.length > 0) {
    const message = [
      "[MISE-HYGIENE] Secrets detected in mise.toml",
      "",
      `Found ${result.secretFindings.length} potential secret(s) that should NOT be committed.`,
      "mise.toml is meant to be shared; secrets belong in .mise.local.toml (gitignored).",
      buildSecretsMigrationToMiseLocalTomlSuggestionText(result.secretFindings),
    ].join("\n");
    return denyDecision(message);
  }

  // POLICY 2: Line count exceeded on Write → DENY with hub-spoke suggestion
  // (Only for Write tool, since Edit only gives partial content.)
  if (tool_name === "Write" && result.exceedsLineCountLimit) {
    const message = [
      `[MISE-HYGIENE] mise.toml exceeds ${MISE_HYGIENE_GUARD_CONFIG.maxLines} lines (${result.lineCount} lines)`,
      "",
      "Large mise.toml files become hard to maintain. Consider hub-spoke refactoring:",
      "- Keep [env], [tools], [task_config] in root mise.toml (hub)",
      "- Move [tasks.*] to .mise/tasks/*.toml files (spokes)",
      buildHubSpokeRefactoringSuggestionText(),
    ].join("\n");
    return denyDecision(message);
  }

  return ALLOW_DECISION;
}

// ============================================================================
// Standalone main (backward-compat for direct CLI invocation)
// ============================================================================

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("MISE-HYGIENE");
  if (!input) return;

  const decision = await classifyMiseHygieneGuardForOrchestrator(input);
  switch (decision.kind) {
    case "deny":
      return deny(decision.reason ?? "(no reason given)");
    case "ask":
      return deny(decision.reason ?? "(no reason given)");
    default:
      return allow();
  }
}

// import.meta.main is true only for the entry-point script; when the orchestrator
// imports classifyMiseHygieneGuardForOrchestrator, this branch does NOT fire.
if (import.meta.main) {
  main().catch((err: unknown) => {
    trackHookError("pretooluse-mise-hygiene-guard", err instanceof Error ? err.message : String(err));
    allow();
  });
}
