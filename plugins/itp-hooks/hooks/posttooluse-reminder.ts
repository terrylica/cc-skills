#!/usr/bin/env bun
/**
 * PostToolUse reminder for itp-hooks plugin.
 * TypeScript/Bun implementation for type safety and maintainability.
 *
 * Provides non-blocking reminders for decision traceability:
 * 1. graph-easy CLI used → remind about using the skill for reproducibility
 * 2. pip/venv usage → remind about using uv instead
 * 3. ADR modified → remind to update Design Spec
 * 4. Design Spec modified → remind to update ADR
 * 5. Implementation code modified → remind about ADR traceability + ruff linting
 * 6. Pandas usage → remind to prefer Polars for dataframe operations
 *
 * ADR: 2025-12-17-posttooluse-hook-visibility.md
 * ADR: 2026-01-10-uv-reminder-hook.md
 * ADR: 2026-01-22-polars-preference-hook (pending)
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { join, basename } from "path";
import { execSync } from "child_process";
import { homedir } from "os";

// --- Types ---

interface HookInput {
  tool_name: string;
  tool_input: {
    command?: string;
    file_path?: string;
    content?: string;
    new_string?: string;
  };
  session_id?: string;
}

interface HookOutput {
  decision: "block" | "allow";
  reason: string;
}

// --- Utility Functions ---

function output(result: HookOutput): void {
  console.log(JSON.stringify(result));
}

function blockWithReminder(reason: string): void {
  // ADR: /docs/adr/2025-12-17-posttooluse-hook-visibility.md
  // MUST use decision:block format - only "reason" field is visible to Claude
  output({ decision: "block", reason });
}

function normalizePath(filePath: string): string {
  // Only normalize for pattern matching (ADR/Spec detection)
  // Keep absolute paths intact for file reading operations
  return filePath.replace(/^\.\//, "");
}

function normalizeForPatternMatch(filePath: string): string {
  // Strip leading ./ and / for ADR/Spec pattern matching
  return filePath.replace(/^\.\//, "").replace(/^\//, "");
}

// --- Detection Functions ---

/**
 * Check for graph-easy CLI usage and track for PreToolUse exemption
 */
function checkGraphEasy(command: string, sessionId?: string): string | null {
  if (!command.includes("graph-easy")) {
    return null;
  }

  // Track graph-easy usage for PreToolUse exemption
  // ADR: 2025-12-09-itp-hooks-workflow-aware-graph-easy
  const stateDir = join(homedir(), ".claude", "hooks", "state");
  try {
    mkdirSync(stateDir, { recursive: true });
    if (sessionId) {
      writeFileSync(
        join(stateDir, `${sessionId}.graph-easy-used`),
        String(Math.floor(Date.now() / 1000))
      );
    }
  } catch (err) {
    console.error(`[itp-hooks] Failed to create state directory: ${stateDir}`);
  }

  return `[GRAPH-EASY SKILL] You used graph-easy CLI directly. For reproducible diagrams, prefer the graph-easy skill (or adr-graph-easy-architect for ADRs). Skills ensure: proper --as=boxart mode, correct \\n escaping, and <details> source block for future edits.`;
}

/**
 * Check for venv activation patterns
 * ADR: 2026-01-10-uv-reminder-hook (extended 2026-01-22)
 */
function checkVenvActivation(command: string): string | null {
  const commandLower = command.toLowerCase();

  // Exception: documentation/echo context
  if (/^\s*(echo|printf)|grep.*venv/i.test(commandLower)) {
    return null;
  }

  // Detect: source .venv/bin/activate, . .venv/bin/activate, etc.
  const venvPattern = /(source|\.)\s+[^|;&]*\.?venv\/bin\/activate/i;
  if (!venvPattern.test(commandLower)) {
    return null;
  }

  // Extract venv path for context
  const venvMatch = command.match(/[^ ]*\.?venv\/bin\/activate/);
  const venvPath = venvMatch
    ? venvMatch[0].replace("/bin/activate", "")
    : ".venv";

  return `[UV-REMINDER] venv activation detected - use 'uv run' instead

EXECUTED: ${command}
PREFERRED: uv run <command>  # No activation needed - uv manages venv automatically

WHY UV:
- No manual activation/deactivation
- Auto-creates .venv if missing
- Syncs dependencies from pyproject.toml/uv.lock
- Works with SSH: ssh host 'cd /path && uv run python script.py'

EXAMPLE:
  OLD: source ${venvPath}/bin/activate && python script.py
  NEW: uv run python script.py`;
}

/**
 * Check for pip usage patterns
 * ADR: 2026-01-10-uv-reminder-hook
 */
function checkPipUsage(command: string): string | null {
  const commandLower = command.toLowerCase();

  // === EXCEPTIONS ===

  // 1. Already in uv context
  if (/^\s*uv\s+(run|exec|pip)/i.test(commandLower)) {
    return null;
  }

  // 2. Documentation/comments
  if (/^\s*#|^\s*echo.*pip|grep.*pip/i.test(commandLower)) {
    return null;
  }

  // 3. Lock file GENERATION operations
  if (/pip-compile|pip\s+freeze/i.test(commandLower)) {
    return null;
  }

  // === DETECT: pip usage ===
  const pipPattern =
    /(^|\s|"|'|&&\s*)(pip|pip3|python[0-9.]*\s+(-m\s+)?pip)\s+(install|uninstall)/i;
  if (!pipPattern.test(commandLower)) {
    return null;
  }

  // Generate suggested replacement
  let suggested = command
    .replace(/pip install/gi, "uv add")
    .replace(/pip3 install/gi, "uv add")
    .replace(/python -m pip install/gi, "uv add")
    .replace(/pip uninstall/gi, "uv remove")
    .replace(/pip3 uninstall/gi, "uv remove");

  // Special case: editable install
  if (/pip\s+install\s+(-e|--editable)/i.test(commandLower)) {
    suggested = "uv pip install -e .";
  }

  // Special case: requirements file install
  if (/pip\s+install\s+-r/i.test(commandLower)) {
    suggested = "uv sync  # or: uv pip install -r requirements.txt";
  }

  return `[UV-REMINDER] pip detected - use uv instead

EXECUTED: ${command}
PREFERRED: ${suggested}

WHY UV: 10-100x faster, lockfile management (uv.lock), reproducible builds

QUICK REF: pip install → uv add | pip uninstall → uv remove | pip -e . → uv pip install -e .`;
}

/**
 * Check if ADR was modified → remind about Design Spec
 */
function checkAdrModified(filePath: string): string | null {
  const adrPattern = /^docs\/adr\/(\d{4}-\d{2}-\d{2}-[a-zA-Z0-9_-]+)\.md$/;
  const match = filePath.match(adrPattern);

  if (!match) {
    return null;
  }

  const slug = match[1];
  const specPath = `docs/design/${slug}/spec.md`;

  return `[ADR-SPEC SYNC] You modified ADR '${slug}'. Check if Design Spec needs updating: ${specPath}. Rule: ADR and Design Spec must stay synchronized.`;
}

/**
 * Check if Design Spec was modified → remind about ADR
 */
function checkSpecModified(filePath: string): string | null {
  const specPattern =
    /^docs\/design\/(\d{4}-\d{2}-\d{2}-[a-zA-Z0-9_-]+)\/spec\.md$/;
  const match = filePath.match(specPattern);

  if (!match) {
    return null;
  }

  const slug = match[1];
  const adrPath = `docs/adr/${slug}.md`;

  return `[SPEC-ADR SYNC] You modified Design Spec '${slug}'. Check if ADR needs updating: ${adrPath}. Rule: ADR and Design Spec must stay synchronized.`;
}

/**
 * Check for pyproject.toml path escaping patterns (PostToolUse backup)
 * Soft reminder in case PreToolUse guard didn't catch it
 * ADR: 2026-01-22-pyproject-toml-root-only-policy
 */
function checkPyprojectPathEscape(
  filePath: string,
  content?: string
): string | null {
  if (!filePath.endsWith("pyproject.toml")) {
    return null;
  }

  // Get git root for context
  let gitRoot: string | null = null;
  try {
    gitRoot = execSync("git rev-parse --show-toplevel", {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    return null; // Not in git repo
  }

  // If we don't have content (PostToolUse), read the file
  let fileContent = content;
  if (!fileContent && existsSync(filePath)) {
    try {
      fileContent = readFileSync(filePath, "utf-8");
    } catch {
      return null;
    }
  }

  if (!fileContent) {
    return null;
  }

  // Check for path references that escape via ../../../
  const escapingPaths: string[] = [];
  const pathPattern =
    /([a-zA-Z0-9_-]+)\s*=\s*\{[^}]*path\s*=\s*["']([^"']+)["']/g;

  let match;
  while ((match = pathPattern.exec(fileContent)) !== null) {
    const pathValue = match[2];
    // Count levels up
    const upLevels = (pathValue.match(/\.\.\//g) || []).length;
    if (upLevels >= 3) {
      escapingPaths.push(`${match[1]} = { path = "${pathValue}" }`);
    }
  }

  if (escapingPaths.length === 0) {
    return null;
  }

  return `[PATH-ESCAPE REMINDER] pyproject.toml contains path references escaping monorepo:

DETECTED:
  ${escapingPaths.join("\n  ")}

FIX: Use git source instead:
  package = { git = "https://github.com/owner/repo", branch = "main" }

Or add as workspace member in root pyproject.toml

REFERENCE: https://docs.astral.sh/uv/concepts/projects/dependencies/`;
}

/**
 * Check implementation code for ruff issues and ADR traceability
 * ADR: 2025-12-11-ruff-posttooluse-linting
 */
function checkImplementationCode(filePath: string): string | null {
  // Check if it's implementation code
  const isImplPath =
    /^(src\/|lib\/|scripts\/|plugins\/[^/]+\/skills\/[^/]+\/scripts\/)/.test(
      filePath
    );
  const isCodeFile = /\.(py|ts|js|mjs|rs|go)$/.test(filePath);

  if (!isImplPath && !isCodeFile) {
    return null;
  }

  const fileBasename = basename(filePath);

  // --- Ruff linting for Python files ---
  if (filePath.endsWith(".py")) {
    try {
      // Check if ruff is available
      execSync("command -v ruff", { stdio: "pipe" });

      // Run ruff with comprehensive rule set
      const ruffOutput = execSync(
        `ruff check "${filePath}" --select BLE,S110,E722,F,UP,SIM,B,I,RUF --ignore D,ANN --no-fix --output-format=concise 2>/dev/null | grep -v "All checks passed" | head -20`,
        { stdio: "pipe", encoding: "utf-8" }
      ).trim();

      if (ruffOutput) {
        return `[RUFF] Issues detected in ${fileBasename}:\n${ruffOutput}\nRun 'ruff check ${filePath} --fix' to auto-fix safe issues.`;
      }
    } catch {
      // ruff not available or no issues - continue
    }
  }

  // --- ADR traceability check ---
  if (existsSync(filePath)) {
    try {
      const content = readFileSync(filePath, "utf-8");
      const first50Lines = content.split("\n").slice(0, 50).join("\n");

      // Look for common ADR reference patterns
      if (!/ADR:|docs\/adr\/|\/adr\/[0-9]/.test(first50Lines)) {
        return `[CODE-ADR TRACEABILITY] You modified implementation file: ${fileBasename}. Consider: Does this change relate to an existing ADR? If implementing a decision from docs/adr/, add ADR reference comment.`;
      }
    } catch {
      // File read error - skip
    }
  }

  return null;
}

/**
 * Check for Pandas usage that could use Polars instead (PostToolUse backup)
 * Soft reminder in case PreToolUse guard was bypassed
 * ADR: 2026-01-22-polars-preference-hook (pending)
 */
function checkPolarsPreference(
  filePath: string,
  content?: string
): string | null {
  // Only check Python files
  if (!filePath.endsWith(".py")) {
    return null;
  }

  // Exception paths where Pandas is acceptable
  const PANDAS_EXCEPTION_PATHS = ["mlflow-python", "legacy/", "third-party/"];
  if (PANDAS_EXCEPTION_PATHS.some((p) => filePath.includes(p))) {
    return null;
  }

  // Get content if not provided
  let fileContent = content;
  if (!fileContent && existsSync(filePath)) {
    try {
      fileContent = readFileSync(filePath, "utf-8");
    } catch {
      return null;
    }
  }

  if (!fileContent) {
    return null;
  }

  // Skip if exception comment present
  if (/# polars-exception:/.test(fileContent)) {
    return null;
  }

  // Skip if Polars already imported (hybrid usage is intentional)
  if (/import polars|from polars import/.test(fileContent)) {
    return null;
  }

  // Detection patterns
  const PANDAS_PATTERNS = [
    /^import pandas/m,
    /^from pandas import/m,
    /\bimport pandas as pd\b/,
    /\bpd\.DataFrame\(/,
    /\bpd\.read_csv\(/,
    /\bpd\.read_parquet\(/,
    /\bpd\.concat\(/,
    /\bpd\.merge\(/,
  ];

  const hasPandasUsage = PANDAS_PATTERNS.some((p) => p.test(fileContent));
  if (!hasPandasUsage) {
    return null;
  }

  const fileBasename = basename(filePath);
  return `[POLARS PREFERENCE] Pandas detected in newly written code.

DETECTED: Pandas import/usage in ${fileBasename}

═══════════════════════════════════════════════════════════════════
IF PANDAS IS INTENTIONAL: Add this comment at the TOP of the file:

  # polars-exception: <reason why Pandas is needed>

Then re-edit the file to add the comment. The hook will skip files
containing this exception comment.

Example reasons:
  # polars-exception: MLflow tracking requires Pandas DataFrames
  # polars-exception: pandas-ta library only accepts Pandas
  # polars-exception: upstream API returns Pandas DataFrame
═══════════════════════════════════════════════════════════════════

IF CONVERTING TO POLARS, use this cheatsheet:
  pd.read_csv()     → pl.read_csv() / pl.scan_csv()
  pd.DataFrame()    → pl.DataFrame()
  df.groupby()      → df.group_by()
  pd.concat()       → pl.concat()
  df.merge()        → df.join()

WHY POLARS: 30x faster, lazy evaluation, better memory efficiency.

REFERENCE: https://docs.pola.rs/user-guide/migration/pandas/`;
}

// --- Main ---

async function main(): Promise<void> {
  // Read JSON from stdin
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let input: HookInput;
  try {
    input = JSON.parse(inputText);
  } catch {
    // Invalid JSON - exit silently
    process.exit(0);
  }

  const toolName = input.tool_name || "";
  let reminder: string | null = null;

  // --- Handle Bash tool ---
  if (toolName === "Bash") {
    const command = input.tool_input?.command || "";

    // Check graph-easy (highest priority - tracks state)
    reminder = checkGraphEasy(command, input.session_id);

    // Check venv activation
    if (!reminder) {
      reminder = checkVenvActivation(command);
    }

    // Check pip usage
    if (!reminder) {
      reminder = checkPipUsage(command);
    }

    if (reminder) {
      blockWithReminder(reminder);
    }
    process.exit(0);
  }

  // --- Handle Write/Edit tools ---
  if (toolName === "Write" || toolName === "Edit") {
    const rawFilePath = normalizePath(input.tool_input?.file_path || "");
    const patternPath = normalizeForPatternMatch(input.tool_input?.file_path || "");

    if (!rawFilePath) {
      process.exit(0);
    }

    // Get content for content-based checks
    const content = input.tool_input?.content || input.tool_input?.new_string;

    // Check pyproject.toml path escape (highest priority for this file type)
    // Uses raw path for file reading
    reminder = checkPyprojectPathEscape(rawFilePath, content);

    // Check Polars preference (for Python files)
    if (!reminder) {
      reminder = checkPolarsPreference(rawFilePath, content);
    }

    // Check ADR modified (uses pattern-normalized path)
    if (!reminder) {
      reminder = checkAdrModified(patternPath);
    }

    // Check Design Spec modified (uses pattern-normalized path)
    if (!reminder) {
      reminder = checkSpecModified(patternPath);
    }

    // Check implementation code (uses raw path for file reading)
    if (!reminder) {
      reminder = checkImplementationCode(rawFilePath);
    }

    if (reminder) {
      blockWithReminder(reminder);
    }
    process.exit(0);
  }

  // Other tools - no action
  process.exit(0);
}

main().catch((err) => {
  console.error("[posttooluse-reminder] Error:", err);
  process.exit(0);
});
