#!/usr/bin/env bun
/**
 * PreToolUse hook: Pueue Auto-Wrap Guard + 1Password Token Injection (+ cargo TTY isolation)
 *
 * Three responsibilities, in ONE hook because Claude Code keeps only the last hook's
 * `updatedInput` (anthropics/claude-code#15897), so only one hook may rewrite a Bash command:
 *
 * 1. OP TOKEN INJECTION: Prepends OP_SERVICE_ACCOUNT_TOKEN for commands
 *    targeting the "Claude Automation" 1Password vault. Avoids biometric prompts.
 *    Token source: OP_SA_TOKEN_CMD or OP_SA_TOKEN_FILE (see lib/op-token-injector.ts)
 *
 * 2. PUEUE WRAPPING: Wraps known long-running Bash commands with pueue.
 *    Uses allowlist approach: ONLY wraps commands matching LONG_RUNNING_PATTERNS.
 *
 * 3. CARGO TTY ISOLATION (moved here 2026-10-17 from pretooluse-cargo-tty-guard.ts): a backgrounded
 *    `cargo bench|test|build|run|check … &`, or any cargo command marked `CARGO-TTY-WRAP`, runs in
 *    pueue. That guard had been running inside the Bash orchestrator since 2026-10-01, which does
 *    not apply `updatedInput`, so its rewrite had been silently dropped ever since.
 *
 * Pipeline: originalCommand → maybeInjectOpToken → (cargo | long-running) → validated wrapper
 *
 * IMPORTANT: This MUST be the LAST PreToolUse entry in hooks.json.
 * Reason: GitHub #15897 — multi-hook updatedInput aggregation bug means the
 * last hook's updatedInput wins unconditionally (even if undefined).
 *
 * WHAT A REWRITE MUST NEVER DO (2026-10-17). The previous wrapper pasted the command after
 * `pueue add -- ` unquoted, so every loop, `&&`, pipe or quote in it was parsed by the OUTER shell
 * and the agent got zsh parse errors for a command it had written correctly. It also matched the
 * loop patterns against heredoc bodies and quoted strings, so writing a script FILE that contained
 * a loop, or `bash -c '…for…'`, was rewritten. Now:
 *   - patterns are matched on the command line only: data heredoc bodies and quoted spans removed,
 *     and an inline `python -c '…'` snippet is not a long-running job;
 *   - the command reaches pueue as one single-quoted argument (lib/pueue-safe-wrap.ts);
 *   - the rewrite is emitted only if the original parses under bash, the user's $SHELL and sh, and
 *     the wrapper parses under bash and $SHELL. Otherwise the command passes through untouched;
 *   - the wrapper returns the TASK's exit code (pueue wait itself exits 0 on a failed task).
 *
 * Opt-in:  # PUEUE-WRAP comment forces wrapping for any command
 * Opt-out: # PUEUE-SKIP comment prevents wrapping even for long-running patterns
 * Op-token bypass: OP_SERVICE_ACCOUNT_TOKEN already in command → skip injection
 *
 * Reference: /plugins/devops-tools/skills/pueue-job-orchestration/references/claude-code-integration.md
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/15897 (updatedInput aggregation bug)
 * GitHub Issue: https://github.com/anthropics/claude-code/issues/11282 (ask + updatedInput broken)
 */

import { allow, allowWithInput, deny, parseStdinOrAllow, trackHookError } from "./pretooluse-helpers.ts";
import { maybeInjectOpToken } from "./lib/op-token-injector.ts";
import { withoutQuotedSpans } from "./lib/review-round-artifact.ts";
import { stripDataHeredocBodies } from "./lib/shell-heredoc-data.ts";
import { lexShellCommands } from "./lib/shell-command-quote-aware-static-lexer.ts";
import { buildPueueWrapper, wrapIsSafe } from "./lib/pueue-safe-wrap.ts";
import {
  buildSafeWrapper as buildCargoWrapper,
  cargoCommandNeedsPueueIsolation,
  ensurePueueDaemon,
} from "./pretooluse-cargo-tty-guard.ts";

/** File where we record pueue task IDs for session-scoped cleanup.
 *  The stop hook reads this to kill only OUR jobs, not all jobs. */
const SESSION_TASK_LOG = `/tmp/claude-pueue-tasks-${process.env.CLAUDE_SESSION_ID || process.ppid}.txt`;

const HOOK_NAME = "PUEUE-WRAP-GUARD";

/** Opt-in escape hatch — force wrapping */
const WRAP_COMMENT = /# *PUEUE-WRAP/i;

/** Opt-out escape hatch — prevent wrapping */
const SKIP_COMMENT = /# *PUEUE-SKIP/i;

/** Commands that are already pueue-related (local or via SSH) */
const PUEUE_COMMANDS = /\bpueue\s+(add|status|log|wait|restart|send|kill|remove|clean|reset|follow|group)\b/i;

/** Scripts that ARE pueue wrappers (e.g., pueue-populate.sh, pueue-setup.sh) */
const PUEUE_SCRIPTS = /pueue[_-]/i;

/** Already backgrounded commands */
const BACKGROUNDED = /\bnohup\s|&\s*$|\bscreen\s|\btmux\s/i;

/** Fast local commands that should never be wrapped, even if their arguments
 *  (commit messages, branch names, file paths) happen to match LONG_RUNNING_PATTERNS.
 *  Includes linters/formatters whose file path arguments can trigger false positives
 *  (e.g., `ruff check scripts/populate_full_cache.py` matching "populate_cache"). */
const NEVER_WRAP = /^\s*(git|ruff|mypy|pyright|pylint|flake8|black|isort|prettier|eslint|biome|mise|cargo\s+(check|build|test|clippy|fmt|doc|nextest|bench|run|publish|install|update|add|remove))\s/i;

/**
 * Known long-running patterns that benefit from pueue wrapping.
 * Mirrors posttooluse-reminder.ts detection patterns (SSoT alignment).
 * Matched against {@link commandLineForPatternMatching}, never against the raw command.
 */
const LONG_RUNNING_PATTERNS = [
  // Data population/cache scripts
  /populate[_-]?(cache|full|data)/i,
  /cache[_-]?populat/i,
  /bulk[_-]?(insert|load|import)/i,

  // Batch processing with multiple items
  /--phase\s+\d/i,
  // Shell loops are judged by loopBodyRunsLongJob() below, on the PROGRAM each body command runs.

  // SSH commands are EXCLUDED from auto-wrapping (opt-in only via # PUEUE-WRAP).
  // Reason: SSH commands already run remotely — local pueue wrapping adds no value
  // but creates quoting hell (zsh → pueue add → SSH → remote bash = 4 quote layers).
  // The PostToolUse pueue-reminder still suggests pueue for SSH long-running commands.
  // Evidence: opendeviationbar session 3774932e — 3 consecutive failures from
  // quote mangling when auto-wrapping `ssh <remote-host> 'for sym in ...; do curl ...; done'`.
];

/** `python -c ''` / `uv run … python -c ''` after quoted spans are emptied: an inline snippet. */
const INLINE_PYTHON_SNIPPET = /(?:\S*\/)?\bpython[\d.]*\s+-c\s+(?:''|"")/gi;
const UV_RUN_INLINE_SNIPPET = /\buv\s+run\b[^;&|\n]*?INLINE_SNIPPET/gi;

/**
 * The text the long-running patterns are matched against: the command line itself.
 *
 * Data heredoc bodies are removed (a script being WRITTEN is not being run), quoted spans are
 * emptied (`bash -c '…'`, `grep 'for x in'`, commit messages), and inline `python -c` snippets are
 * collapsed (a one-line snippet in a loop is not a batch job). Exported for tests.
 */
export function commandLineForPatternMatching(command: string): string {
  return withoutQuotedSpans(stripDataHeredocBodies(command))
    .replace(INLINE_PYTHON_SNIPPET, " INLINE_SNIPPET ")
    .replace(UV_RUN_INLINE_SNIPPET, " INLINE_SNIPPET ");
}

const LOOP_OPENERS: ReadonlySet<string> = new Set(["for", "while", "until", "select"]);
const BODY_LEADING_KEYWORDS: ReadonlySet<string> = new Set(["do", "then", "else", "elif", "{", "!", "time"]);

/** A body command whose PROGRAM is python, `uv run`, or a populate/bulk/cache script. */
function runsLongJobProgram(words: readonly string[]): boolean {
  let k = 0;
  while (k < words.length && BODY_LEADING_KEYWORDS.has(words[k]!)) k++;
  while (k < words.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[k]!)) k++;
  if (k >= words.length) return false;
  const program = words[k]!.slice(words[k]!.lastIndexOf("/") + 1);
  if (/^python[\d.]*$/.test(program)) return true;
  if (program === "uv" && words[k + 1] === "run") return true;
  return /populate|bulk|cache/i.test(program);
}

/**
 * Does a `for|while|until … do … done` loop on the command line run a long job in its body?
 *
 * The earlier regexes (`for … ; do [^;]*(populate|bulk|cache|python|uv run)`) matched any WORD in
 * the body, so `for f in *.py; do grep -l cache "$f"; done` (a read-only search for the word
 * "cache") was wrapped. Here only the program each body command runs counts. Exported for tests.
 */
export function loopBodyRunsLongJob(visibleCommandLine: string): boolean {
  let pendingHeaders = 0;
  let depth = 0;
  for (const command of lexShellCommands(visibleCommandLine).commands) {
    const words = command.map((w) => w.value);
    if (words.length === 0) continue;
    if (LOOP_OPENERS.has(words[0]!)) {
      pendingHeaders += 1;
      continue;
    }
    if (words[0] === "done") {
      depth = Math.max(0, depth - 1);
      continue;
    }
    if (words[0] === "do" && pendingHeaders > 0) {
      pendingHeaders -= 1;
      depth += 1;
    }
    if (depth > 0 && runsLongJobProgram(words)) return true;
  }
  return false;
}

/**
 * Check if a command matches known long-running patterns.
 * Returns true ONLY for commands that should be wrapped.
 */
export function shouldWrap(command: string): boolean {
  // Opt-in: explicit wrap request
  if (WRAP_COMMENT.test(command)) return true;

  // Opt-out: explicit skip request
  if (SKIP_COMMENT.test(command)) return false;

  // Never wrap pueue commands or pueue management scripts
  if (PUEUE_COMMANDS.test(command)) return false;
  if (PUEUE_SCRIPTS.test(command)) return false;

  // Never wrap already-backgrounded commands
  if (BACKGROUNDED.test(command)) return false;

  // Never wrap fast local commands (git commit messages can contain any text)
  if (NEVER_WRAP.test(command)) return false;

  // Check against known long-running patterns, on the command line only
  const visible = commandLineForPatternMatching(command);
  return LONG_RUNNING_PATTERNS.some((p) => p.test(visible)) || loopBodyRunsLongJob(visible);
}

/**
 * Build the synchronous pueue wrapper command.
 * Pattern: queue → wait → log → the task's own exit status (stdout flows back to Claude Code).
 */
export function buildWrappedCommand(command: string, cwd: string): string {
  return buildPueueWrapper({
    command,
    cwd,
    taskLog: SESSION_TASK_LOG,
    onQueueFailure: "run-directly",
    label: "pueue-wrap",
  });
}

function passThrough(toolName: string, command: string, opTokenInjected: boolean): void {
  if (opTokenInjected) allowWithInput(HOOK_NAME, toolName, { command });
  else allow();
}

/** Daemon up and default group not paused; fail-open (no wrap) otherwise. */
function pueueReadyForDefaultGroup(): boolean {
  const daemonCheck = Bun.spawnSync(["pueue", "status", "--json"], { stdout: "pipe", stderr: "ignore" });
  if (daemonCheck.exitCode !== 0) return false;
  try {
    const status = JSON.parse(daemonCheck.stdout.toString());
    const defaultGroup = status?.groups?.default;
    if (defaultGroup === "Paused" || defaultGroup?.status === "Paused") return false;
  } catch {
    // JSON parse failed — the daemon answered; keep the old behaviour and wrap.
  }
  return true;
}

async function main() {
  const input = await parseStdinOrAllow(HOOK_NAME);
  if (!input) return;

  const { tool_name, tool_input = {}, cwd } = input;

  // Only process Bash commands
  if (tool_name !== "Bash") {
    allow();
    return;
  }

  const originalCommand = tool_input.command || "";

  // Step 1: Maybe inject OP_SERVICE_ACCOUNT_TOKEN for Claude Automation vault
  const command = await maybeInjectOpToken(originalCommand);
  const opTokenInjected = command !== originalCommand;
  const workingDir = cwd || process.cwd();

  // Step 2a: backgrounded cargo (or CARGO-TTY-WRAP) must not hold the TTY.
  if (cargoCommandNeedsPueueIsolation(command)) {
    if (!ensurePueueDaemon()) {
      deny(
        "[CARGO-TTY-GUARD] A backgrounded cargo command needs pueue isolation, and the pueue daemon is not running.\n" +
          "A backgrounded cargo opens /dev/tty and suspends the session (anthropics/claude-code#11898).\n\n" +
          "Fix: start it (`pueued -d`) and retry, or run cargo in the foreground without `&`.\n" +
          "Escape hatch: add `# CARGO-TTY-SKIP` to the command.",
      );
      return;
    }
    const wrapped = buildCargoWrapper(command, workingDir, SESSION_TASK_LOG);
    const verdict = wrapIsSafe(command.replace(/\s+&\s*$/, ""), wrapped);
    if (!verdict.ok) {
      // NOT a pass-through: unwrapped, this is exactly the backgrounded cargo that suspends the
      // session. Say why and let the agent rewrite it (found in review, 2026-10-17).
      deny(
        `[CARGO-TTY-GUARD] A backgrounded cargo command must run in pueue, and a safe wrapper could not be built (${verdict.reason}).\n` +
          "Fix: run it in the foreground without `&`, or queue it yourself: pueue add -- <command>.\n" +
          "Escape hatch: add `# CARGO-TTY-SKIP` to the command.",
      );
      return;
    }
    allowWithInput(HOOK_NAME, tool_name, { command: wrapped });
    return;
  }

  // Step 2b: Allowlist check — only wrap known long-running commands
  if (!shouldWrap(command) || !pueueReadyForDefaultGroup()) {
    passThrough(tool_name, command, opTokenInjected);
    return;
  }

  // Wrap tier: rewrite command with pueue wrapper — only if both sides parse.
  const wrappedCommand = buildWrappedCommand(command, workingDir);
  const verdict = wrapIsSafe(command, wrappedCommand);
  if (!verdict.ok) {
    process.stderr.write(`[${HOOK_NAME}] not wrapped: ${verdict.reason}\n`);
    passThrough(tool_name, command, opTokenInjected);
    return;
  }

  allowWithInput(HOOK_NAME, tool_name, { command: wrappedCommand });
}

if (import.meta.main) {
  main().catch((err) => {
    trackHookError("pretooluse-pueue-wrap-guard", err instanceof Error ? err.message : String(err));
    allow();
  });
}
