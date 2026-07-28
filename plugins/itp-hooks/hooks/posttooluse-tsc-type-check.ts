#!/usr/bin/env bun
/**
 * PostToolUse hook: native TypeScript compiler type checker (tsc) —
 * Iter-126 migration from tsgo (@typescript/native-preview is now FROZEN/DEPRECATED).
 *
 * TypeScript 7 ships the native Go compiler as `tsc` itself (no separate binary).
 * This hook runs `tsc --noEmit` after every Write/Edit of a .ts/.tsx file,
 * with project-scoping (nearest tsconfig.json).
 *
 * Prefers: project's local node_modules/.bin/tsc → PATH tsc → fallback reminder
 * (no tsgo invocation; tsgo was only viable when separate @typescript/native-preview binary existed).
 *
 * Iter-126 also tunes concurrency: passes `--singleThreaded` to prevent 4-worker checker
 * spawn per keystroke-ish edit (development machine overkill). Measurement: native tsc
 * on TS 7 is ~200ms full-project check, dominated by I/O not CPU, so single-threaded
 * dominates the scheduler for the 4s PostToolUse window anyway.
 *
 * Keeps ALL existing behaviors intact:
 *  - Project-scoping via walk-up to nearest tsconfig.json
 *  - Output filtering to errors referencing the edited file's tsconfig-relative path
 *  - Async Bun.spawn + AbortSignal cooperative timeout (4000ms)
 *  - Once-per-session install reminder on ENOENT (if neither local nor PATH tsc found)
 */

import { existsSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { resolve as resolvePath } from "node:path";
import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
// Iter-106: import from the dedicated cross-Pre/PostToolUse shared lib (the
// helper's canonical home as of iter-106; relocated from the PostToolUse
// contract lib where iter-104 pragmatically introduced it).
import { truncateHookOutputToStayBelowClaudeFileSpilloverThreshold } from "./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts";
import {
  executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail,
  tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName,
} from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts";
// Iter-124: skip type-checking throwaway scripts edited in temp dirs.
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";

// --- Constants ---

const TSC_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS = 4000;

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

/**
 * Resolve the tsc executable by preference:
 * 1. Project's local node_modules/.bin/tsc (from the nearest tsconfig directory)
 * 2. PATH tsc (any tsc found in the system PATH)
 * 3. null (not found; caller should emit reminder)
 *
 * Iter-126: native tsc is preferred everywhere. tsgo (@typescript/native-preview)
 * is FROZEN and no longer shipped separately.
 */
function resolveTscExecutable(tsconfigDir: string): string | null {
  // Try local node_modules/.bin/tsc in the tsconfig directory and ancestors.
  let dir = tsconfigDir;
  const root = "/";
  while (true) {
    const localTsc = join(dir, "node_modules", ".bin", "tsc");
    if (existsSync(localTsc)) {
      return localTsc;
    }
    const parent = dirname(dir);
    if (parent === dir || parent === root) break;
    dir = parent;
  }

  // Try PATH tsc.
  try {
    const pathTsc = Bun.which("tsc");
    if (pathTsc) {
      return pathTsc;
    }
  } catch {
    // Bun.which may throw; fail-open and return null.
  }

  return null;
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

export async function classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    const filePath = input.tool_input?.file_path;
    if (!filePath) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    if (!filePath.endsWith(".ts") && !filePath.endsWith(".tsx")) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (filePath.includes("/node_modules/")) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }
    if (
      isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(
        filePath,
      )
    ) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const fileDir = dirname(filePath);
    const tsconfigDir = locateNearestEnclosingTsconfigJsonDirectoryByWalkingUpward(fileDir);
    if (!tsconfigDir) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    const tscExecutable = resolveTscExecutable(tsconfigDir);
    if (!tscExecutable) {
      const sessionId = input.session_id || "unknown";
      if (
        !tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName("tsc", sessionId)
      ) {
        return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
      }
      return buildPostToolUseAdditionalContextDecision(
        `[TypeScript] Native tsc type checker not found in project node_modules or PATH.

Install TypeScript 7+ to enable instant type checking after every .ts/.tsx edit:

  npm install -D typescript@latest

TypeScript 7 includes the native Go compiler as \`tsc\` itself (no separate binary).
Typical runtime: ~200ms full-project check.`,
      );
    }

    const tscExecutionResult =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
        [tscExecutable, "--noEmit", "--singleThreaded"],
        { cwd: tsconfigDir, timeoutMs: TSC_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS },
      );

    if (tscExecutionResult.spawnFailed) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    if (tscExecutionResult.timedOut) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    if (tscExecutionResult.exitCode === 0) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const tscOutputTextForOperator =
      tscExecutionResult.stdoutText || tscExecutionResult.stderrText;
    if (!tscOutputTextForOperator) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    // Filter output to only show errors related to the edited file. tsc
    // checks ALL files in the tsconfig scope — don't blame the user for
    // pre-existing errors in other files. Use the tsconfigDir-relative path
    // to avoid basename collisions (two index.ts files in different dirs).
    const relativePath = filePath.startsWith(`${tsconfigDir}/`)
      ? filePath.slice(tsconfigDir.length + 1)
      : basename(filePath);
    const filteredDiagnosticLines = tscOutputTextForOperator
      .split("\n")
      .filter((line) => line.startsWith(relativePath) || line.includes(filePath));

    if (filteredDiagnosticLines.length === 0) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Iter-105: defense-in-depth against Claude's 10K-character hook-output
    // file-spillover threshold (filteredDiagnosticLines.join can be unbounded).
    return buildPostToolUseAdditionalContextDecision(
      truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(
        `[TypeScript] Type errors in ${basename(filePath)}:\n\n${filteredDiagnosticLines.join("\n")}`,
      ),
    );
  } catch {
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

// Symmetric-naming alias matching the sibling subhooks (ty, oxlint, biome,
// ssot-principles), all of which the orchestrator imports as
// `classify<Tool><Concern>ForPostToolUseOrchestrator`. The precise name above
// encodes the actual algorithm; this alias keeps the orchestrator's import
// block scannable as a single uniform column.
export const classifyTscTypeCheckForPostToolUseOrchestrator =
  classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator;

// ══════════════════════════════════════════════════════════════════════════
//  Standalone CLI entry point
// ══════════════════════════════════════════════════════════════════════════

async function runStandaloneCliMain(): Promise<void> {
  // Iter-96: Bun.stdin.text() one-shot read (2026 idiomatic API)
  const inputText = await Bun.stdin.text();

  let input: PostToolUseInput;
  try {
    input = JSON.parse(inputText) as PostToolUseInput;
  } catch {
    process.exit(0);
  }

  const decision =
    await classifyNativeTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(
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
