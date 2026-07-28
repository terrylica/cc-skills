#!/usr/bin/env bun
/**
 * PostToolUse hook: TypeScript upgrade reminder (once per session).
 *
 * ── Why this hook exists (operator directive 2026-07-24) ──────────────────
 *
 * TypeScript 7 (Go-native tsc) is the standard. The policy is:
 *   - greenfield: "typescript": "latest" (commit the lockfile)
 *   - compiler-embedding tools (Volar, Angular, typescript-eslint,
 *     ts-morph): dual-install compat alias
 *     { "@typescript/native": "npm:typescript@latest",
 *       "typescript": "npm:@typescript/typescript6@^6.0.2" }
 *
 * This subhook fires on the FIRST eligible code Write/Edit each session and
 * emits a once-per-session nudge surfacing the highest-yield TS 7 migration
 * checks (breaking changes, performance knobs, etc.) and the SSoT reference
 * (~/.claude/typescript-latest-CLAUDE.md).
 *
 * This is the COMPANION to iter-92's PreToolUse guards:
 *   - pretooluse-typescript-version-guard: blocks Write/Edit of package.json
 *     with legacy TS declarations
 *   - pretooluse-typescript-legacy-install-command-guard: blocks Bash install
 *     commands that would pull legacy TypeScript
 *
 * This PostToolUse reminder is ADVISORY, not blocking — it informs about
 * migration opportunities AFTER a TypeScript-related file is edited,
 * encouraging deliberate upgrades and refactors.
 *
 * ── Skip conditions (noop) ────────────────────────────────────────────────
 *
 * The reminder does NOT fire if:
 *   1. Tool is not Write/Edit/MultiEdit
 *   2. File path is inside a temporary scratch directory (iter-124 helper)
 *   3. File extension is not .ts/.tsx/.mts/.cts (TypeScript files) and not
 *      package.json or tsconfig.json
 *   4. Already reminded THIS SESSION (atomic O_EXCL gate-claim; prevents nag)
 *   5. Any unexpected error (fail-open to noop)
 *
 * ── Message content ──────────────────────────────────────────────────────
 *
 * A compact, useful reminder that:
 *   - Names the TypeScript 7 standard and "latest" pinning policy
 *   - Lists the highest-yield breaking changes (types defaults to [],
 *     strict defaults true, baseUrl/downlevelIteration/target/moduleResolution/
 *     module/esModuleInterop hard errors, rootDir defaults to ./)
 *   - Mentions perf knobs (--checkers, --builders, --singleThreaded)
 *   - Points at the SSoT ~/.claude/typescript-latest-CLAUDE.md
 *   - Invites surfacing concrete refactor opportunities
 *
 * Wrapped in the canonical truncation helper so the aggregated reason
 * stays below Claude's hook-output spillover threshold (iter-106 invariant).
 *
 * ── Architecture ──────────────────────────────────────────────────────────
 *
 * Dual-mode (mirrors posttooluse-python-preference-nudge.ts +
 * posttooluse-memory-efficiency-reminder.ts):
 *   - `classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator` is the
 *     pure classifier imported by the iter-93 PostToolUse orchestrator —
 *     amortizes the bun cold-start across the registry.
 *   - The `import.meta.main` block keeps it runnable as a standalone CLI.
 *
 * ── Once-per-session gate ─────────────────────────────────────────────────
 *
 * Uses the shared iter-95/iter-98 atomic gate-claim helper to ensure the
 * reminder fires at most once per Claude session. The gate is O_EXCL atomic
 * at the POSIX layer (no race, no multiple reminders), so multiple session
 * instances or fast-firing Write events cannot double-emit.
 */

import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import {
  POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
  buildPostToolUseAdditionalContextDecision,
  isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { truncateHookOutputToStayBelowClaudeFileSpilloverThreshold } from "./lib/shared-truncation-helper-against-claude-file-spillover-threshold-cross-pretooluse-and-posttooluse-iter106.ts";
import { isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts } from "./lib/shared-temporary-directory-edited-file-path-detection-to-skip-lint-on-throwaway-scripts-cross-posttooluse-iter124.ts";
import { tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName } from "./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts";

// ══════════════════════════════════════════════════════════════════════════
//  TypeScript-relevant file detection
// ══════════════════════════════════════════════════════════════════════════

const TYPESCRIPT_FILE_EXTENSIONS = new Set([
  ".ts",
  ".tsx",
  ".mts",
  ".cts",
]);

const TYPESCRIPT_CONFIG_FILENAMES = new Set([
  "package.json",
  "tsconfig.json",
]);

function isTypeScriptRelevantFile(filePath: string | undefined): boolean {
  if (!filePath || typeof filePath !== "string") return false;

  // Check config files (basename only)
  const basename = filePath.split("/").pop() || "";
  if (TYPESCRIPT_CONFIG_FILENAMES.has(basename)) return true;

  // Check TypeScript source extensions
  for (const ext of TYPESCRIPT_FILE_EXTENSIONS) {
    if (filePath.endsWith(ext)) return true;
  }

  return false;
}

// ══════════════════════════════════════════════════════════════════════════
//  Reminder message construction (with concrete drift check)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Walk upward from the edited file to the directory that owns it — the nearest
 * ancestor holding a `.git` or a `package.json` — so the drift sweep can be
 * scoped to one project instead of the whole estate. Returns null when the file
 * sits outside any recognizable project, in which case the caller skips the
 * sweep rather than falling back to an unbounded one.
 */
function locateNearestEnclosingProjectRootByWalkingUpwardFromEditedFile(
  editedFilePath: string,
): string | null {
  let currentDirectory = dirname(editedFilePath);
  // Bounded walk: filesystem root terminates it, but cap iterations anyway so a
  // pathological symlink cycle cannot spin a hook that runs on every edit.
  for (let ascent = 0; ascent < 40; ascent++) {
    if (
      existsSync(resolve(currentDirectory, ".git")) ||
      existsSync(resolve(currentDirectory, "package.json"))
    ) {
      return currentDirectory;
    }
    const parentDirectory = dirname(currentDirectory);
    if (parentDirectory === currentDirectory) return null;
    currentDirectory = parentDirectory;
  }
  return null;
}

/**
 * Run the typescript-version-drift-guard to get concrete drift report.
 * Falls back to generic message if guard errors or times out.
 *
 * SCOPED TO ONE PROJECT, deliberately. An unscoped run sweeps every root
 * (~/eon, ~/vj, ~/own) and takes ~22 seconds — far past the 5s budget below, so
 * it timed out on EVERY invocation and the reminder silently degraded to the
 * generic message while still stalling each edit for the full five seconds. The
 * failure was invisible: a timeout returns null, which is indistinguishable
 * here from "no drift found".
 *
 * Scoping is also the more useful behaviour. The reminder fires because of a
 * file the operator just edited, so drift in THAT project is actionable, while
 * drift in an unrelated checkout is noise they cannot act on from here. The
 * estate-wide sweep remains available from the CLI and the release preflight,
 * where 22 seconds is affordable.
 */
async function getConcreteTypeScriptDriftReport(editedFilePath: string): Promise<string | null> {
  try {
    const projectRoot = locateNearestEnclosingProjectRootByWalkingUpwardFromEditedFile(editedFilePath);
    if (projectRoot === null) return null;

    // Try to run the drift guard with a 5-second timeout
    const { executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail } =
      await import("./lib/posttooluse-subhook-async-subprocess-execution-and-once-per-session-reminder-gate-file-helpers-iter95.ts");

    const result = await executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
      ["typescript-version-drift-guard", "--json", "--roots", projectRoot],
      { timeoutMs: 5000 },
    );

    if (result.timedOut || result.spawnFailed || result.exitCode === null) {
      return null; // Guard not available or timed out; fall back to generic message
    }

    if (result.exitCode === 0) {
      // No drift detected
      return null;
    }

    if (result.exitCode === 1) {
      // Drift detected — extract concrete message from JSON output
      try {
        const json = JSON.parse(result.stdoutText);
        const drifts = json.packages?.filter((p: Record<string, unknown>) => p.verdict === "drift") || [];

        if (drifts.length === 0) {
          return null;
        }

        const reportLines = ["Drift detected in TypeScript declarations:"];
        for (const drift of drifts.slice(0, 3)) {
          // Limit to top 3 to avoid message spam
          reportLines.push(
            `  • ${drift.path || "(unknown)"}: declared ${drift.declared}, ${drift.reason}`,
          );
        }
        if (drifts.length > 3) {
          reportLines.push(`  • ... and ${drifts.length - 3} more`);
        }

        return reportLines.join("\n");
      } catch {
        return null; // JSON parse failed; use generic message
      }
    }

    return null;
  } catch {
    // Any error → fall back to generic message
    return null;
  }
}

/**
 * `editedFilePath` scopes the concrete drift sweep to the project that owns the
 * edited file. Omitting it (as unit tests do) skips the sweep entirely and
 * returns the generic reminder — deliberately, since the alternative default of
 * sweeping every root costs ~22 seconds and would always exceed the subprocess
 * budget anyway.
 */
export async function buildTypeScriptUpgradeReminderMessage(
  editedFilePath?: string,
): Promise<string> {
  const driftReport =
    editedFilePath === undefined ? null : await getConcreteTypeScriptDriftReport(editedFilePath);

  const baseMessage = [
    `[TS-7] TypeScript 7 (Go-native tsc) is the standard.`,
    ``,
    `Pinning policy (see ~/.claude/typescript-latest-CLAUDE.md):`,
    `  • Greenfield: "typescript": "latest" + commit lockfile`,
    `  • Compiler-embedding tools (Volar, Angular, typescript-eslint, ts-morph):`,
    `    dual-install compat alias (TS 6.0 API unavailable in 7.0; restored 7.1+)`,
    ``,
    `Highest-yield breaking changes to verify:`,
    `  • types defaults to [] (ambient @types resolve fails → TS2591)`,
    `  • strict defaults true (implicitAny, strictNullChecks, etc. → TS7006)`,
    `  • baseUrl/downlevelIteration/target es5/moduleResolution/module/`,
    `    esModuleInterop:false hard errors (TS5102/TS5108)`,
    `  • rootDir now defaults to ./ (can affect compilation scope)`,
    ``,
    `Performance knobs for native tsc:`,
    `  • --checkers N (default 4)  • --builders N (default 1)  • --singleThreaded`,
    ``,
    `Consider surfacing concrete refactor opportunities in the file just edited.`,
  ];

  if (driftReport) {
    baseMessage.push("", driftReport);
  }

  return baseMessage.join("\n");
}

// ══════════════════════════════════════════════════════════════════════════
//  Pure classifier (orchestrator-imported)
// ══════════════════════════════════════════════════════════════════════════

export async function classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(
  input: PostToolUseInput,
): Promise<PostToolUseSubhookDecision> {
  try {
    // Early exit: not a file-edit tool
    if (!isFileEditToolNameHonoredByPostToolUseContextInjectingSubhook(input.tool_name)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    const filePath = input.tool_input?.file_path;

    // Early exit: temp-scratch file (throwaway scripts not worth nudging)
    if (isEditedFilePathInsideTemporaryScratchDirectoryWhereLintingIsWastefulForThrowawayScripts(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Early exit: not a TypeScript-relevant file
    if (!isTypeScriptRelevantFile(filePath)) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Early exit: already reminded this session
    const sessionId = input.session_id || "unknown";
    const didClaim = tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName(
      "typescript-upgrade",
      sessionId,
    );
    if (!didClaim) {
      return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
    }

    // Emit the reminder (now async to invoke drift guard)
    const message = await buildTypeScriptUpgradeReminderMessage(filePath);
    return buildPostToolUseAdditionalContextDecision(
      truncateHookOutputToStayBelowClaudeFileSpilloverThreshold(message),
    );
  } catch {
    // Fail open: any unexpected error → noop
    return POSTTOOLUSE_SUBHOOK_NOOP_DECISION;
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Standalone CLI entry point
// ══════════════════════════════════════════════════════════════════════════

async function runStandaloneCliMain(): Promise<void> {
  const inputText = await Bun.stdin.text();

  let input: PostToolUseInput;
  try {
    input = JSON.parse(inputText) as PostToolUseInput;
  } catch {
    process.exit(0);
  }

  const decision = await classifyTypeScriptUpgradeReminderForPostToolUseOrchestrator(input);
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
