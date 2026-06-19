#!/usr/bin/env bun
/**
 * PostToolUse reminder for itp-hooks plugin.
 * TypeScript/Bun implementation for type safety and maintainability.
 *
 * Provides non-blocking reminders for decision traceability:
 * 1. graph-easy CLI used → remind about using the skill for reproducibility
 * 2. pip/venv usage → remind about using uv instead
 * 3. Long-running tasks → remind about using Pueue for job orchestration
 * 4. ADR modified → remind to update Design Spec
 * 5. Design Spec modified → remind to update ADR
 * 6. Implementation code modified → remind about ADR traceability + ruff linting
 *
 * ADR: 2025-12-17-posttooluse-hook-visibility.md
 * ADR: 2026-01-10-uv-reminder-hook.md
 * Issue: https://github.com/terrylica/rangebar-py/issues/77 (Pueue reminder)
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "fs";
import { join, basename } from "path";
import { execSync } from "child_process";
import { homedir } from "os";
import { trackHookError } from "./lib/hook-error-tracker.ts";
// Iter-112: route the SETPROCTITLE-OK escape-hatch detection through the
// iter-107 canonical helper rather than a raw `fileContent.includes()`
// substring check. Closes the iter-111 registry-consistency gap and
// expands the iter-110 canonical cohort from 8 → 9 (this hook becomes
// the ninth member). Behavior-preserving: pre-iter-112 used
// `fileContent.includes("# SETPROCTITLE-OK")` which required the literal
// `# ` comment prefix; iter-112 routes through
// `hasFileWideEscapeHatchMarkerInContent` in CASE_SENSITIVE mode (pure
// substring match on `SETPROCTITLE-OK`), which (a) accepts `// `, `<!-- `,
// or no comment prefix as well, matching the UPPER-KEBAB-CASE-never-collides
// substring convention used by the other 8 cohort members, and (b) the
// iter-111 registry entry already documents this mode pairing as the
// canonical declaration. The pre-iter-112 leading-`#` requirement was
// incidental to the implementation (never documented as a constraint),
// so widening the prefix tolerance is operator-friendly.
import { hasFileWideEscapeHatchMarkerInContent } from "./lib/shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";
// Iter-124: skip lint/quality nudges on throwaway scripts edited in temp dirs.
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

const SETPROCTITLE_REMINDER_ESCAPE_HATCH_CONFIGURATION_REGISTERED_IN_ITER111_CANONICAL_REGISTRY = {
  markerNameTokenIncludingSuffix: "SETPROCTITLE-OK",
  caseSensitivityMode: "CASE_SENSITIVE" as const,
};

// --- Types ---

interface HookInput {
  tool_name: string;
  tool_input: {
    command?: string;
    file_path?: string;
    content?: string;
    new_string?: string;
  };
  tool_result?: {
    stdout?: string;
    stderr?: string;
  };
  session_id?: string;
  duration_ms?: number;
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
    trackHookError("posttooluse-reminder", `Failed to create state directory: ${stateDir}`);
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

  // 1. Already in uv context (match anywhere — catches SSH-wrapped commands)
  if (/\buv\s+(run|exec|pip|venv)\b/i.test(commandLower)) {
    return null;
  }

  // 2. Documentation/comments
  if (/^\s*#|^\s*echo.*pip|grep.*pip/i.test(commandLower)) {
    return null;
  }

  // 3. Commands with free-form text arguments (commit messages, issue bodies)
  if (/^\s*gh\s+(issue|pr)\s+(create|edit|comment)\b/i.test(commandLower)) {
    return null;
  }
  if (/^\s*git\s+(commit|tag)\b/i.test(commandLower)) {
    return null;
  }

  // 4. Lock file GENERATION operations
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
 * Check for long-running tasks that should use Pueue
 * Issue: https://github.com/terrylica/rangebar-py/issues/77
 *
 * Detects patterns that indicate long-running or batch processing tasks:
 * - Data population/cache scripts
 * - Batch processing with loops
 * - Multi-symbol/multi-threshold operations
 * - SSH commands running remote jobs
 */
function checkPueueUsage(command: string): string | null {
  const commandLower = command.toLowerCase();

  // === EXCEPTIONS ===

  // 1. Already using pueue (direct commands or pueue management scripts)
  if (/pueue\s+(add|status|follow|log|restart)/i.test(commandLower)) {
    return null;
  }
  // 1b. Scripts that ARE pueue wrappers (e.g., pueue-populate.sh, pueue-setup.sh)
  if (/pueue[_-]/i.test(command)) {
    return null;
  }

  // 2. Quick status/check commands (not long-running)
  if (/--status|--plan|--help|-h|--version/i.test(commandLower)) {
    return null;
  }

  // 3. Documentation/echo context
  if (/^\s*(echo|printf|#|grep)/i.test(commandLower)) {
    return null;
  }

  // 4. Already in background mode (nohup, &, screen, tmux)
  if (/nohup\s|&\s*$|\bscreen\s|\btmux\s/i.test(command)) {
    return null;
  }

  // 5. Fast local commands — their arguments (inline JS, commit messages) can
  //    contain pattern keywords as string literals, not actual shell commands.
  //    Aligned with NEVER_WRAP in pretooluse-pueue-wrap-guard.ts (SSoT)
  if (/^\s*(git\s|bun\s|node\s|gh\s)/i.test(command)) {
    return null;
  }

  // === DETECT: Long-running task patterns ===

  const longRunningPatterns = [
    // Data population/cache scripts
    /populate[_-]?(cache|full|data)/i,
    /cache[_-]?populat/i,
    /bulk[_-]?(insert|load|import)/i,

    // Batch processing with multiple items
    /--phase\s+\d/i, // Phase-based execution
    // Shell loops with known long-running inner commands ONLY
    // Simple loops (gh api, curl, echo, git) are NOT flagged — they complete quickly
    // Aligned with pretooluse-pueue-wrap-guard.ts (SSoT)
    /for\s+\w+\s+in.*;\s*do[^;]*(populate|bulk|cache|python|uv\s+run)/i,
    /while.*;\s*do[^;]*(populate|bulk|cache|python|uv\s+run)/i,

    // SSH with long-running remote commands
    /ssh\s+\S+\s+["']?.*populate/i,
    /ssh\s+\S+\s+["']?.*--phase/i,
  ];

  const matchedPattern = longRunningPatterns.find((p) => p.test(command));
  if (!matchedPattern) {
    return null;
  }

  // Check if this is running on a remote host via SSH
  const isRemote = /^ssh\s+(\S+)/i.test(command);
  const remoteHost = isRemote ? command.match(/^ssh\s+(\S+)/i)?.[1] : null;

  let pueueCommand: string;
  if (remoteHost) {
    // Extract the inner command from SSH, stripping outer quotes and redirections
    const innerCmd = command
      .replace(/^ssh\s+\S+\s+/, "") // strip "ssh host "
      .replace(/\s*2>&1\s*$/, "") // strip trailing redirections
      .replace(/^["']/, "") // strip leading quote
      .replace(/["']$/, ""); // strip trailing quote
    pueueCommand = `ssh ${remoteHost} 'pueue add -- ${innerCmd.replace(/'/g, "'\\''")}'`;
  } else {
    pueueCommand = `pueue add -- ${command}`;
  }

  return `[PUEUE-REMINDER] Long-running task detected - consider using Pueue

EXECUTED: ${command}
PREFERRED: ${pueueCommand}

WHY PUEUE:
- Daemon survives SSH disconnects, crashes, reboots
- Queue persisted to disk - auto-resumes after failure
- Per-group parallelism limits (avoid resource exhaustion)
- Easy restart of failed jobs: pueue restart <id>

QUICK REF:
  pueue add -- <cmd>          # Queue a job
  pueue status                # Check progress
  pueue follow <id>           # Watch job in real-time
  pueue log <id>              # View completed job output
  pueue restart <id>          # Restart failed job

SETUP (if not installed):
  macOS: brew install pueue && pueued -d
  Linux: ~/.local/bin/pueued -d  # See setup-pueue-linux.sh`;
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

  for (const m of fileContent.matchAll(pathPattern)) {
    const pathValue = m[2];
    // Count levels up
    const upLevels = (pathValue.match(/\.\.\//g) || []).length;
    if (upLevels >= 3) {
      escapingPaths.push(`${m[1]} = { path = "${pathValue}" }`);
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
 * Check file size for code files (1000-2000 lines = soft reminder).
 * PreToolUse hard-blocks >2000 lines; this covers the warn tier.
 * Only code files — markdown excluded (docs are naturally long).
 *
 * Thresholds doubled 2026-05-26 (was 500/1000) to reduce reminder noise on
 * legitimately large files like the in-process hook orchestrators that
 * intentionally combine many subhook classifiers into one bun process.
 */
function checkFileSizeReminder(filePath: string): string | null {
  const CODE_EXTENSIONS = new Set([
    ".rs", ".py", ".ts", ".tsx", ".js", ".jsx",
    ".go", ".java", ".c", ".cpp", ".h", ".hpp",
    ".rb", ".swift", ".kt", ".sh", ".bash",
    ".toml", ".yml", ".yaml", ".json",
  ]);

  const lastDot = filePath.lastIndexOf(".");
  if (lastDot === -1) return null;
  const ext = filePath.substring(lastDot);

  // Only check code files, NOT markdown
  if (!CODE_EXTENSIONS.has(ext)) return null;

  // Only check files that exist
  if (!existsSync(filePath)) return null;

  const content = readFileSync(filePath, "utf-8");
  const lineCount = content.split("\n").length;

  const WARN = 1000;
  const BLOCK = 2000;

  // Skip if under warn threshold or over block threshold (PreToolUse handles >BLOCK)
  if (lineCount < WARN || lineCount > BLOCK) return null;

  // Skip if escape hatch present
  if (content.includes("FILE-SIZE-OK")) return null;

  const fileName = filePath.split("/").pop();
  return `[FILE-SIZE-REMINDER] ${fileName} is ${lineCount} lines (warn: ${WARN}, block: ${BLOCK}). Consider splitting into smaller files. Add \`# FILE-SIZE-OK\` to suppress.`;
}

/**
 * Check Bun/TypeScript loop/batch tooling for SWALLOWED errors → nudge fail-fast.
 *
 * Motivation (2026-06-08, yukon referral-intake non-PDF back-scan): a long-running
 * Bun-TS scanner caught each per-item error, logged it, and `continue`d — silently
 * masking a HEIC-decode failure and a network TimeoutError until the operator
 * happened to eyeball the output. The durable lesson: long-running Bun-TS loop
 * tooling should FAIL FAST — halt on a non-transient error (after bounded
 * retries), persist resumable state, and exit non-zero — so the error surfaces,
 * gets fixed, and the run is restarted (resuming), rather than swallow-and-continue
 * which masks regressions and forces manual intervention later.
 *
 * This is a REMINDER (warn + allow), never a block. It also reinforces the repo
 * convention of building tooling in Bun + TypeScript with proper wiring.
 *
 * Fires only when ALL hold (high-precision, low-noise — better to under-fire
 * than nag correct code):
 *   - file is Bun/TS/JS source (.ts/.tsx/.mts/.cts/.js/.mjs/.cjs), non-test
 *   - file has an AWAITED loop (for/while/.map/.forEach + `await`) → it's a
 *     batch / long-running iteration tool, the class where swallowing bites
 *   - a catch block swallows-and-continues:  catch (…) { … continue }
 *   - file has NO fail-fast path at all: no `throw`, no `process.exit(<non-zero>)`
 * Escape hatch: add `FAIL-FAST-OK` anywhere in the file.
 */
function checkFailFastErrorHandling(
  filePath: string,
  content?: string,
): string | null {
  // Bun / TypeScript / JavaScript source only.
  if (!/\.(ts|tsx|mts|cts|js|mjs|cjs)$/.test(filePath)) return null;

  // Skip test files (fixtures legitimately model swallow-and-continue).
  const fileName = filePath.split("/").pop() || "";
  if (/\.(test|spec)\.(ts|tsx|mts|cts|js|mjs|cjs)$/.test(fileName)) return null;
  if (filePath.includes("__tests__/") || filePath.includes("/tests/")) return null;

  // Resolve content (PostToolUse ⇒ file is durable on disk).
  let text = content;
  if (!text && existsSync(filePath)) {
    try {
      text = readFileSync(filePath, "utf-8");
    } catch {
      return null;
    }
  }
  if (!text) return null;

  // Escape hatch.
  if (text.includes("FAIL-FAST-OK")) return null;

  // Signal 1: awaited loop ⇒ batch / long-running iteration tool.
  const hasLoop =
    /\b(for|while)\s*\(/.test(text) ||
    /\bfor\s+(const|let|var)\b[^\n]*\bof\b/.test(text) ||
    /\.(map|forEach)\s*\(/.test(text);
  const hasAwait = /\bawait\b/.test(text);
  if (!(hasLoop && hasAwait)) return null;

  // Signal 2: a catch block that swallows-and-continues. Bounded look-ahead
  // (≤400 chars) keeps the match inside the catch body, not a later loop.
  const swallowsAndContinues = /catch\s*\([^)]*\)\s*\{[\s\S]{0,400}?\bcontinue\b/.test(text);
  if (!swallowsAndContinues) return null;

  // Signal 3: NO fail-fast path anywhere in the file. If it already throws or
  // exits non-zero, the author has a halt mechanism ⇒ stay quiet.
  const hasFailFast = /\bthrow\b/.test(text) || /process\.exit\s*\(\s*[1-9]/.test(text);
  if (hasFailFast) return null;

  return `[FAIL-FAST-REMINDER] ${fileName} looks like a long-running Bun/TS loop that catches errors and \`continue\`s — i.e. it SWALLOWS failures. This is how silent regressions hide (a decode/network error gets logged and skipped, surfacing only if someone eyeballs the output).

PREFER fail-fast for batch/long-running tooling:
- Retry only TRANSIENT errors (timeout / 5xx / rate-limit) with bounded backoff.
- On a non-transient error AFTER retries: persist resumable state, print a clear
  diagnostic (which item + why), and HALT (exit non-zero) — do not mark-and-continue.
- Make the run RESUMABLE so a restart picks up where it stopped after the fix.
- Offer an explicit opt-out (e.g. SKIP_BAD=1) to skip known-bad items on purpose.

WHY: surfacing errors immediately → fix → restart beats swallowing → silent gaps
→ manual archaeology later. Build this wiring in Bun + TypeScript (repo default).

Add \`FAIL-FAST-OK\` to suppress if this loop intentionally tolerates per-item failures.`;
}

/**
 * Check if a Python file looks like a long-running service/daemon but is missing setproctitle.
 * Without setproctitle, all Python services appear as generic "python" in ps/top/Activity Monitor.
 *
 * Detects: while True loops, asyncio.run/event loops, signal handlers, FastAPI/Flask/uvicorn,
 *          launchd/systemd paths, if __name__ == "__main__" with server patterns.
 *
 * Skips: files that already import setproctitle, test files, non-.py files.
 */
function checkSetproctitle(filePath: string, content?: string): string | null {
  // Only Python files
  if (!filePath.endsWith(".py")) return null;

  // Skip test files
  const fileName = filePath.split("/").pop() || "";
  if (/^test_|_test\.py$|_spec\.py$/.test(fileName)) return null;
  if (filePath.includes("__tests__/") || filePath.includes("/tests/")) return null;

  // Get file content
  let fileContent = content;
  if (!fileContent && existsSync(filePath)) {
    try {
      fileContent = readFileSync(filePath, "utf-8");
    } catch {
      return null;
    }
  }
  if (!fileContent) return null;

  // Already has setproctitle — nothing to do
  if (/setproctitle/.test(fileContent)) return null;

  // Escape hatch (iter-112: routed through the iter-107 canonical helper).
  if (
    hasFileWideEscapeHatchMarkerInContent(
      fileContent,
      SETPROCTITLE_REMINDER_ESCAPE_HATCH_CONFIGURATION_REGISTERED_IN_ITER111_CANONICAL_REGISTRY,
    )
  ) {
    return null;
  }

  // --- Detect service/daemon patterns ---
  const SERVICE_PATTERNS: [RegExp, string][] = [
    [/while\s+True\s*:/, "while True loop (daemon main loop)"],
    [/while\s+running\s*:/, "while running loop (daemon main loop)"],
    [/while\s+self\._?running\s*:/, "while self.running loop (daemon main loop)"],
    [/asyncio\.(run|get_event_loop|new_event_loop)\s*\(/, "asyncio event loop"],
    [/\.run_forever\s*\(/, "event loop run_forever()"],
    [/\.run_until_complete\s*\(/, "event loop run_until_complete()"],
    [/signal\.signal\s*\(\s*signal\.SIG(TERM|INT|HUP)/, "signal handler (daemon lifecycle)"],
    [/uvicorn\.run\s*\(/, "uvicorn server"],
    [/app\.run\s*\(.*(?:host|port)/, "Flask/FastAPI server"],
    [/serve_forever\s*\(/, "serve_forever() (SocketServer)"],
    [/Celery\s*\(|@app\.task/, "Celery worker"],
    [/schedule\.(every|run_pending)/, "schedule-based daemon"],
    [/APScheduler|BackgroundScheduler|AsyncIOScheduler/, "APScheduler daemon"],
    [/multiprocessing\.(Process|Pool)\s*\(/, "multiprocessing worker"],
    [/threading\.Thread\(.*daemon\s*=\s*True/, "daemon thread"],
    [/Observer\(\)[\s\S]{0,200}\.start\(\)/, "watchdog file observer"],
    [/add_argument\(\s*["']--daemon["']/, "CLI --daemon flag (daemon entry point)"],
  ];

  // Also check if file lives in a service/daemon directory
  const SERVICE_PATHS = [
    /\.claude\/automation\//,
    /LaunchAgents\//,
    /LaunchDaemons\//,
    /systemd\//,
    /\.service/,
    /daemons?\//i,
    /workers?\//i,
  ];

  const inServicePath = SERVICE_PATHS.some((p) => p.test(filePath));

  const matchedPatterns: string[] = [];
  for (const [pattern, label] of SERVICE_PATTERNS) {
    if (pattern.test(fileContent)) {
      matchedPatterns.push(label);
    }
  }

  // Need at least one service pattern, or be in a service directory with a main guard
  const hasMainGuard = /if\s+__name__\s*==\s*["']__main__["']/.test(fileContent);

  if (matchedPatterns.length === 0 && !(inServicePath && hasMainGuard)) {
    return null;
  }

  const detectedStr = matchedPatterns.length > 0
    ? `Detected: ${matchedPatterns.join(", ")}`
    : `File is in a service directory: ${filePath}`;

  return `[SETPROCTITLE-REMINDER] Python service/daemon missing setproctitle
${detectedStr}

Without setproctitle, this process appears as generic "python" in ps/top/htop/Activity Monitor,
making it impossible to identify among other Python processes.

FIX — add near the top of the file (before main loop):
  import setproctitle
  setproctitle.setproctitle("${fileName.replace(/\.py$/, "")}")

INSTALL: uv add setproctitle

NAMING CONVENTIONS:
  Static:  setproctitle.setproctitle("gmail-token-refresher")
  Dynamic: setproctitle.setproctitle("tts-engine: synthesizing")
  Worker:  setproctitle.setproctitle("cache-worker-1")

Add \`# SETPROCTITLE-OK\` to suppress if this is not a long-running service.`;
}

/**
 * Check implementation code for ruff issues
 * ADR: 2025-12-11-ruff-posttooluse-linting
 *
 * NOTE: ADR/Issue traceability check removed per user request (2026-03-29)
 */
function checkImplementationCode(
  filePath: string,
): string | null {
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

      // Run ruff for silent failure patterns ONLY (per code-correctness philosophy)
      // NO: F401 (unused imports), UP (upgrade), SIM (simplify), I (import sort)
      const ruffOutput = execSync(
        `ruff check "${filePath}" --select E722,S110,S112,PLW1510 --no-fix --output-format=concise 2>/dev/null | grep -v "All checks passed" | head -20`,
        { stdio: "pipe", encoding: "utf-8" }
      ).trim();

      if (ruffOutput) {
        return `[RUFF] Issues detected in ${fileBasename}:\n${ruffOutput}\nRun 'ruff check ${filePath} --fix' to auto-fix safe issues.`;
      }
    } catch {
      // ruff not available or no issues - continue
    }
  }

  return null;
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

    // Check for long-running tasks that should use Pueue
    // Only suggest pueue if the command took >30s (fast commands don't need queue management)
    // If duration_ms is unavailable (older Claude Code), fall back to always showing
    const durationMs = input.duration_ms;
    if (!reminder && (durationMs === undefined || durationMs > 30_000)) {
      reminder = checkPueueUsage(command);
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

    // Iter-124: throwaway scripts edited inside temp directories get no
    // lint/quality nudges — carefully checking a file that exists only to be
    // run once and discarded is wasted wall-clock + wasted Claude context.
    if (
      isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
        input.tool_input?.file_path || "",
      )
    ) {
      process.exit(0);
    }

    // Get content for content-based checks
    const content = input.tool_input?.content || input.tool_input?.new_string;

    // Check pyproject.toml path escape (highest priority for this file type)
    // Uses raw path for file reading
    reminder = checkPyprojectPathEscape(rawFilePath, content);

    // Check ADR modified (uses pattern-normalized path)
    if (!reminder) {
      reminder = checkAdrModified(patternPath);
    }

    // Check Design Spec modified (uses pattern-normalized path)
    if (!reminder) {
      reminder = checkSpecModified(patternPath);
    }

    // Check Python service/daemon files for setproctitle (before generic traceability)
    if (!reminder) {
      reminder = checkSetproctitle(rawFilePath, content);
    }

    // Check implementation code (uses raw path for file reading)
    if (!reminder) {
      reminder = checkImplementationCode(rawFilePath);
    }

    // Check file size for code files (500-1000 line soft reminder)
    if (!reminder) {
      reminder = checkFileSizeReminder(rawFilePath);
    }

    // Check Bun/TS loop/batch tooling for swallowed errors → nudge fail-fast
    if (!reminder) {
      reminder = checkFailFastErrorHandling(rawFilePath, content);
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
  trackHookError("posttooluse-reminder", err instanceof Error ? err.message : String(err));
  process.exit(0);
});
