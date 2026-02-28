#!/usr/bin/env bun
/**
 * PostToolUse hook: SSoT/DI principles reminder with ast-grep detection.
 * Triggers once per session on first Write/Edit of a code file.
 *
 * Pattern: Follows lifecycle-reference.md TypeScript template.
 * Trigger: After Write or Edit on code files (.py, .ts, .rs, .go, .java, .kt, .rb).
 * Output: { decision: "block", reason: "..." } for Claude visibility.
 *
 * GitHub Issue: https://github.com/terrylica/cc-skills/issues/28
 */

import { existsSync, mkdirSync, writeFileSync, openSync, closeSync } from "node:fs";
import { join, extname, dirname } from "node:path";
import { $ } from "bun";
import { trackHookError } from "./lib/hook-error-tracker.ts";

// ============================================================================
// CONFIGURATION
// ============================================================================

const HOOK_NAME = "posttooluse-ssot-principles";
const GATE_DIR = "/tmp/.claude-ssot-reminder";
const AST_GREP_RULES_DIR = join(dirname(import.meta.path), "ast-grep-ssot");

const CODE_EXTENSIONS = new Set([
  ".py", ".ts", ".tsx", ".js", ".jsx",
  ".rs", ".go", ".java", ".kt", ".rb",
]);

const TEST_FILE_PATTERNS = [
  /\/test_/,
  /\/tests\//,
  /_test\./,
  /_spec\./,
  /\.test\./,
  /\.spec\./,
  /\/conftest\.py$/,
  /\/__tests__\//,
];

// ============================================================================
// TYPES
// ============================================================================

interface PostToolUseInput {
  tool_name: string;
  tool_input: {
    file_path?: string;
    content?: string;
    new_string?: string;
    [key: string]: unknown;
  };
  session_id?: string;
}

interface AstGrepFinding {
  ruleId: string;
  text: string;
  message: string;
  range: { start: { line: number; column: number } };
  file: string;
}

interface HookResult {
  exitCode: number;
  stdout?: string;
  stderr?: string;
}

// ============================================================================
// HELPERS
// ============================================================================

async function parseStdin(): Promise<PostToolUseInput | null> {
  try {
    const stdin = await Bun.stdin.text();
    if (!stdin.trim()) return null;
    return JSON.parse(stdin) as PostToolUseInput;
  } catch {
    return null;
  }
}

function createVisibilityOutput(reason: string): string {
  return JSON.stringify({
    decision: "block",
    reason: reason,
  });
}

function isCodeFile(filePath: string): boolean {
  return CODE_EXTENSIONS.has(extname(filePath));
}

function isTestFile(filePath: string): boolean {
  return TEST_FILE_PATTERNS.some((pattern) => pattern.test(filePath));
}

/**
 * Gate once per session using O_CREAT|O_EXCL atomic file creation.
 * Returns true if this is the first call for this session (gate opened).
 */
function tryGate(sessionId: string): boolean {
  try {
    mkdirSync(GATE_DIR, { recursive: true });
    const gatePath = join(GATE_DIR, `${sessionId}.reminded`);
    const fd = openSync(gatePath, "ax"); // O_CREAT|O_EXCL
    closeSync(fd);
    return true;
  } catch {
    return false; // File already exists = already reminded
  }
}

/**
 * Run ast-grep on a file and return findings.
 * Uses sgconfig.yml from the ast-grep-ssot project directory.
 * Returns empty array on any error (fail-open).
 */
async function runAstGrep(filePath: string): Promise<AstGrepFinding[]> {
  if (!existsSync(AST_GREP_RULES_DIR)) return [];

  try {
    const result = await $`ast-grep scan ${filePath} --json`
      .cwd(AST_GREP_RULES_DIR)
      .quiet()
      .nothrow();
    const stdout = result.stdout.toString().trim();
    if (!stdout || stdout === "[]") return [];
    return JSON.parse(stdout) as AstGrepFinding[];
  } catch {
    return [];
  }
}

/**
 * For Write tool, write content to temp file for ast-grep scanning.
 * For Edit tool, scan the actual file (already modified).
 */
async function getFindings(
  toolName: string,
  filePath: string,
  content: string | undefined,
  ext: string,
): Promise<AstGrepFinding[]> {
  if (toolName === "Write" && content) {
    // Write tool: content hasn't been written yet, use temp file
    const tmpPath = `/tmp/.claude-ssot-scan${ext}`;
    writeFileSync(tmpPath, content);
    const findings = await runAstGrep(tmpPath);
    // Remap file paths to the actual file
    return findings.map((f) => ({ ...f, file: filePath }));
  }

  // Edit tool: file is already modified, scan it directly
  return runAstGrep(filePath);
}

function hasSsotOkComment(content: string | undefined): boolean {
  if (!content) return false;
  return /[#\/\/]\s*SSoT-OK/.test(content);
}

function buildReminder(findings: AstGrepFinding[], filePath: string): string {
  let message = `[SSoT-PRINCIPLES] When writing code, prefer these patterns for maintainability:

1. CONFIG SINGLETON over scattered env var calls
   → Centralize config in one validated object; add constructor validation for fail-fast

2. NONE-DEFAULT + RESOLVER over hardcoded defaults
   → def foo(mode: str | None = None) + resolve from config if None
   → Changing the system default = one env var, not 10 file edits

3. ENTRY-POINT VALIDATION over deep-in-logic checks
   → Validate all inputs at public API boundaries, not in inner functions

4. HIERARCHICAL LOOKUP over flat defaults
   → Per-item override → registry → class default → fallback (with warning)

Escape hatch: # SSoT-OK (same as version-guard)
Skill: /itp:impl-standards → references/ssot-dependency-injection.md
Batch audit: /itp:code-hardcode-audit (adds ast-grep to Ruff+Semgrep+jscpd+gitleaks)`;

  if (findings.length > 0) {
    message += "\n\nDETECTED in current edit:";
    // Deduplicate by ruleId+line
    const seen = new Set<string>();
    for (const f of findings) {
      const key = `${f.ruleId}:${f.range.start.line}`;
      if (seen.has(key)) continue;
      seen.add(key);
      const line = f.range.start.line + 1;
      const text = f.text.length > 60 ? f.text.slice(0, 57) + "..." : f.text;
      message += `\n  • ${filePath}:${line} — ${f.message.split("\n")[0].trim()} (${text})`;
    }
  }

  return message;
}

// ============================================================================
// MAIN LOGIC
// ============================================================================

async function runHook(): Promise<HookResult> {
  const input = await parseStdin();
  if (!input) return { exitCode: 0 };

  const { tool_name, tool_input } = input;
  const filePath = tool_input?.file_path || "";

  // Only trigger on Write/Edit
  if (tool_name !== "Write" && tool_name !== "Edit") {
    return { exitCode: 0 };
  }

  // Only trigger on code files
  const ext = extname(filePath);
  if (!isCodeFile(filePath)) {
    return { exitCode: 0 };
  }

  // Skip test files
  if (isTestFile(filePath)) {
    return { exitCode: 0 };
  }

  // Gate: once per session
  const sessionId = input.session_id || "unknown";
  if (!tryGate(sessionId)) {
    return { exitCode: 0 };
  }

  // Check for SSoT-OK escape hatch in content
  const content = tool_input?.content || tool_input?.new_string;
  if (hasSsotOkComment(content)) {
    return { exitCode: 0 };
  }

  // Run ast-grep detection
  const findings = await getFindings(tool_name, filePath, content, ext);

  // Filter out findings with SSoT-OK on the same line
  const filteredFindings = findings.filter((f) => {
    return !/SSoT-OK/.test(f.text);
  });

  // Build and output reminder
  const reason = buildReminder(filteredFindings, filePath);

  return {
    exitCode: 0,
    stdout: createVisibilityOutput(reason),
  };
}

// ============================================================================
// ENTRY POINT
// ============================================================================

async function main(): Promise<never> {
  let result: HookResult;

  try {
    result = await runHook();
  } catch (err: unknown) {
    trackHookError(HOOK_NAME, err instanceof Error ? err.message : String(err));
    return process.exit(0);
  }

  if (result.stderr) trackHookError(HOOK_NAME, result.stderr);
  if (result.stdout) console.log(result.stdout);
  return process.exit(result.exitCode);
}

void main();
