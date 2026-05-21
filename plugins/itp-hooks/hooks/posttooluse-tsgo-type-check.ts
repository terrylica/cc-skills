#!/usr/bin/env bun
/**
 * PostToolUse hook: tsgo (native Go TypeScript compiler) type checker —
 * iter-94 async-spawn from day one + iter-95 shared-lib-helpers refactor.
 *
 * Runs `tsgo --noEmit` after every Write/Edit of a .ts/.tsx file.
 * tsgo is the native Go TypeScript compiler (~170ms full project check),
 * making it viable as a PostToolUse hook where tsc would not be.
 *
 * Iter-95 hoists the async-spawn + install-reminder gate-file helpers to
 * `lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts`.
 */

import { existsSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail,
  tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName,
} from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts";

// --- Constants ---

const TSGO_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS = 4000;

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

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

export async function classifyTsgoNativeGoTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator(
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

    const fileDir = dirname(filePath);
    const tsconfigDir = locateNearestEnclosingTsconfigJsonDirectoryByWalkingUpward(fileDir);
    if (!tsconfigDir) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    const tsgoExecutionResult =
      await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
        ["tsgo", "--noEmit"],
        { cwd: tsconfigDir, timeoutMs: TSGO_SUBPROCESS_COOPERATIVE_TIMEOUT_MILLISECONDS },
      );

    if (tsgoExecutionResult.spawnFailed) {
      const sessionId = input.session_id || "unknown";
      if (
        !tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName("tsgo", sessionId)
      ) {
        return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
      }
      return buildPostToolUseAdditionalContextDecision(
        `[TSGO] TypeScript native compiler not installed. Install for instant type checking after every .ts/.tsx edit:

  npm install -g @typescript/native-preview

tsgo is ~30x faster than tsc (~170ms full project check) — fast enough to run on every edit.`,
      );
    }

    if (tsgoExecutionResult.timedOut) return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;

    if (tsgoExecutionResult.exitCode === 0) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

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
//  Standalone CLI entry point
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
