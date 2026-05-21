#!/usr/bin/env bun
/**
 * PostToolUse hook: tsgo (native Go TypeScript compiler) type checker — iter-94
 * dual-mode (standalone CLI + orchestrator-imported classifier) with
 * **async Bun.spawn from day one** (no spawnSync legacy to refactor away).
 *
 * Runs `tsgo --noEmit` after every Write/Edit of a .ts/.tsx file.
 * tsgo is the native Go TypeScript compiler (~170ms full project check),
 * making it viable as a PostToolUse hook where tsc would not be. Runs in
 * project mode from the nearest tsconfig.json directory. Filters output to
 * only show errors related to the edited file (avoids blaming the user for
 * pre-existing errors elsewhere in the project).
 *
 * If tsgo is not installed, surfaces a once-per-session install reminder.
 *
 * Fail-open everywhere — every catch returns a `noop` (orchestrator path)
 * or exits 0 (standalone path).
 *
 * ─── Iter-94 architectural decisions ─────────────────────────────────────
 *
 * 1. **Async Bun.spawn from inception**. Per iter-94 audit (confirmed by
 *    Bun's official docs + 2026 community guidance), `Bun.spawnSync`
 *    halts the JS event loop and DEFEATS the iter-93 orchestrator's
 *    `Promise.all` parallelism. tsgo is the 2nd PostToolUse subhook in
 *    the migration arc — every newly-inlined classifier MUST use
 *    `Bun.spawn` (async) so the orchestrator's wall-clock approaches the
 *    SLOWEST subhook, not the SUM.
 *
 * 2. **Dual-export naming-drift acknowledgement**. Following the
 *    iter-89/90/91/93 dual-export pattern: the precise algorithm-encoding
 *    name `classifyTsgoNativeGoTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator`
 *    captures what the algorithm actually does (project-scoped, not file-
 *    scoped — tsgo reads tsconfig.json and checks the whole project).
 *    The symmetric-naming alias `classifyTsgoTypeCheckForPostToolUseOrchestrator`
 *    matches sibling-subhook naming for orchestrator-registry consistency.
 *
 * 3. **import.meta.main standalone guard** preserves backward-compat —
 *    direct `bun posttooluse-tsgo-type-check.ts` still works for testing
 *    or operators running the hook by hand.
 *
 * 4. **Per-edited-file filter via tsconfigDir-relative path**. tsgo
 *    project-mode reports errors across ALL project files. We filter to
 *    only lines referencing the edited file's relative path (from the
 *    tsconfig.json directory) — avoids basename collisions (e.g., two
 *    `index.ts` files in different directories of the same project).
 */

import { existsSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { mkdirSync, openSync, closeSync, constants } from "node:fs";
import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";

// --- Constants ---

const TSGO_INSTALL_REMINDER_PER_SESSION_GATE_DIRECTORY = "/tmp/.claude-tsgo-install-reminder";
const TSGO_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS = 4000;

// ══════════════════════════════════════════════════════════════════════════
//  Helpers (mirror ty-type-check iter-94 async pattern)
// ══════════════════════════════════════════════════════════════════════════

async function drainBunSubprocessStreamToUtf8Text(
  stream: ReadableStream<Uint8Array> | undefined,
): Promise<string> {
  if (!stream) return "";
  try {
    return await new Response(stream).text();
  } catch {
    return "";
  }
}

interface AsyncSubprocessExecutionResult {
  exitCode: number | null;
  stdoutText: string;
  stderrText: string;
  spawnFailed: boolean;
  timedOut: boolean;
}

async function executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndStreamDrain(
  argv: readonly string[],
  options: { cwd?: string; timeoutMs: number },
): Promise<AsyncSubprocessExecutionResult> {
  const abortSignal = AbortSignal.timeout(options.timeoutMs);
  try {
    const subprocess = Bun.spawn(argv, {
      cwd: options.cwd,
      stdout: "pipe",
      stderr: "pipe",
      signal: abortSignal,
    });

    const [stdoutText, stderrText] = await Promise.all([
      drainBunSubprocessStreamToUtf8Text(subprocess.stdout as ReadableStream<Uint8Array> | undefined),
      drainBunSubprocessStreamToUtf8Text(subprocess.stderr as ReadableStream<Uint8Array> | undefined),
    ]);
    await subprocess.exited;

    return {
      exitCode: subprocess.exitCode,
      stdoutText: stdoutText.trim(),
      stderrText: stderrText.trim(),
      spawnFailed: false,
      timedOut: false,
    };
  } catch (raw: unknown) {
    const isAbortError = raw instanceof DOMException && raw.name === "AbortError";
    return {
      exitCode: null,
      stdoutText: "",
      stderrText: raw instanceof Error ? raw.message : String(raw),
      spawnFailed: !isAbortError,
      timedOut: isAbortError,
    };
  }
}

/**
 * Walk up from startDir to find the nearest directory containing tsconfig.json.
 * Returns the directory path, or null if not found. Sync filesystem call —
 * we keep this inside the classifier because it's O(1) per directory level
 * and the orchestrator's parallelism gain comes from the SUBPROCESS spawn,
 * not from existsSync probes that resolve in microseconds.
 */
function locateNearestEnclosingTsconfigJsonDirectoryByWalkingUpward(
  startDir: string,
): string | null {
  let dir = startDir;
  const root = "/";
  while (true) {
    if (existsSync(join(dir, "tsconfig.json"))) {
      return dir;
    }
    const parent = dirname(dir);
    if (parent === dir || parent === root) {
      if (existsSync(join(root, "tsconfig.json"))) {
        return root;
      }
      return null;
    }
    dir = parent;
  }
}

function tryAtomicallyClaimTsgoInstallReminderOncePerSessionGateFile(sessionId: string): boolean {
  try {
    mkdirSync(TSGO_INSTALL_REMINDER_PER_SESSION_GATE_DIRECTORY, { recursive: true });
  } catch {
    return false;
  }
  const gateFile = join(
    TSGO_INSTALL_REMINDER_PER_SESSION_GATE_DIRECTORY,
    `${sessionId}-tsgo-install.reminded`,
  );
  try {
    const fd = openSync(gateFile, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL);
    closeSync(fd);
    return true;
  } catch {
    return false;
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Pure classifier function. Returns a PostToolUseSubhookDecision the
 * orchestrator aggregates into one consolidated reason.
 *
 * Precise algorithm-encoding name. Aliased as
 * `classifyTsgoTypeCheckForPostToolUseOrchestrator` for symmetric naming
 * with sibling subhooks.
 */
export async function classifyTsgoNativeGoTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const filePath = input.tool_input?.file_path;
    if (!filePath) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Only check .ts and .tsx files (cheap O(1) extension filter — lightest-first)
    if (!filePath.endsWith(".ts") && !filePath.endsWith(".tsx")) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Skip node_modules
    if (filePath.includes("/node_modules/")) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Find nearest tsconfig.json directory; no tsconfig → silently noop
    const fileDir = dirname(filePath);
    const tsconfigDir = locateNearestEnclosingTsconfigJsonDirectoryByWalkingUpward(fileDir);
    if (!tsconfigDir) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Run tsgo --noEmit ASYNC via Bun.spawn from the tsconfig.json directory
    const tsgoExecutionResult =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndStreamDrain(
        ["tsgo", "--noEmit"],
        { cwd: tsconfigDir, timeoutMs: TSGO_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS },
      );

    // Spawn-failed-to-start (ENOENT — tsgo not in PATH) → surface install reminder
    if (tsgoExecutionResult.spawnFailed) {
      const sessionId = input.session_id || "unknown";
      if (!tryAtomicallyClaimTsgoInstallReminderOncePerSessionGateFile(sessionId)) {
        return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
      }
      return buildPostToolUseAdditionalContextDecision(
        `[TSGO] TypeScript native compiler not installed. Install for instant type checking after every .ts/.tsx edit:

  npm install -g @typescript/native-preview

tsgo is ~30x faster than tsc (~170ms full project check) — fast enough to run on every edit.`,
      );
    }

    // Timeout / abort → silent noop
    if (tsgoExecutionResult.timedOut) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Clean exit = no type errors
    if (tsgoExecutionResult.exitCode === 0) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Collect output (tsgo writes errors to stdout)
    const tsgoOutputTextForOperator =
      tsgoExecutionResult.stdoutText || tsgoExecutionResult.stderrText;
    if (!tsgoOutputTextForOperator) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Filter output to only show errors related to the edited file. tsgo
    // checks ALL files in the tsconfig scope — don't blame the user for
    // pre-existing errors in other files. Use the tsconfigDir-relative path
    // to avoid basename collisions (two index.ts files in different dirs).
    const relativePath = filePath.startsWith(`${tsconfigDir}/`)
      ? filePath.slice(tsconfigDir.length + 1)
      : basename(filePath);
    const filteredDiagnosticLines = tsgoOutputTextForOperator
      .split("\n")
      .filter((line) => line.startsWith(relativePath) || line.includes(filePath));

    if (filteredDiagnosticLines.length === 0) {
      // Errors exist but not in the edited file — silent noop
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    return buildPostToolUseAdditionalContextDecision(
      `[TSGO] Type errors in ${basename(filePath)}:\n\n${filteredDiagnosticLines.join("\n")}`,
    );
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

export const classifyTsgoTypeCheckForPostToolUseOrchestrator =
  classifyTsgoNativeGoTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator;

// ══════════════════════════════════════════════════════════════════════════
//  Standalone CLI entry point (preserved for backward-compat)
// ══════════════════════════════════════════════════════════════════════════

async function runStandaloneCliMain(): Promise<void> {
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let input: PostToolUseInput;
  try {
    input = JSON.parse(inputText) as PostToolUseInput;
  } catch {
    process.exit(0);
  }

  const decision =
    await classifyTsgoNativeGoTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(
      input,
    );

  if (decision.kind === "additional_context") {
    console.log(JSON.stringify({ decision: "block", reason: decision.message }));
  }
  process.exit(0);
}

if (import.meta.main) {
  runStandaloneCliMain().catch(() => {
    process.exit(0);
  });
}
