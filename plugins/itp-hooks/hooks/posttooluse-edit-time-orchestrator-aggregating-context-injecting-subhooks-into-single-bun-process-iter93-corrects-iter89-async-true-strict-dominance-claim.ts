#!/usr/bin/env bun
/**
 * PostToolUse Edit-Time Orchestrator — iter-93 kick-off of the PostToolUse
 * Write|Edit consolidation arc (analogous to iter-84 → iter-91 PreToolUse
 * arc, but with MULTI-AGGREGATION semantics instead of first-deny-short-
 * circuit).
 *
 * Why a separate orchestrator from the PreToolUse one:
 *
 *   1. PostToolUse decision schema cannot deny — only `{decision: "block",
 *      reason}` is honored as a context-injection mechanism (iter-66
 *      forensic finding + iter-92 audit). So the orchestrator MUST NOT
 *      short-circuit on first non-noop; it must RUN ALL subhooks and merge
 *      their additional_context payloads into ONE consolidated reason.
 *
 *   2. PostToolUse subhooks are typically heavier than PreToolUse ones —
 *      they may spawn ty/tsgo/oxlint/biome/vale subprocesses. Per-subhook
 *      timeouts are correspondingly more generous (4000-8000ms typical vs
 *      3000-5000ms PreToolUse).
 *
 *   3. PostToolUse subhooks fire AFTER the tool's side effects are durable,
 *      so they MAY perform read-only filesystem operations on the
 *      just-written file. The PreToolUse contract forbids file I/O on
 *      `allow` paths (Edit-path scope-to-changed-lines is the exception).
 *
 * Why this orchestrator exists (motivation distinct from `async: true`):
 *
 *   The iter-89 firing originally proposed `async: true` (Anthropic's
 *   Jan-2026 flag) as a strict-dominant alternative to orchestrator
 *   inlining for PostToolUse (filename-encoded as `corrects-iter89-async-
 *   true-strict-dominance-claim` for forensic traceability). Iter-92's web research + classifier audit ruled that
 *   strategy OUT for 15 of 17 marketplace PostToolUse hooks because async
 *   hooks cannot reliably inject `additionalContext` next-to-tool-result
 *   (the model advances before the hook finishes — see Anthropic timing
 *   semantics in docs/HOOKS.md).
 *
 *   Path B (orchestrator inlining, this file) is the only viable strategy
 *   for the 15 [C] CONTEXT-INJECTING hooks. The 1 confirmed [S] PURE-
 *   SIDE-EFFECT hook can independently get `async: true` (out of scope
 *   here).
 *
 *   Cold-start savings projection (final-state, after migrating all 15
 *   context-injecting hooks): (15-1) × 17ms = ~238ms per Write/Edit, on
 *   top of the iter-91 PreToolUse arc's ~119ms savings = ~357ms total
 *   per-tool-call cold-start reduction.
 *
 * Contract enforcement:
 *
 *   Every registered subhook MUST conform to PostToolUseSubhookContract
 *   (pure async classifier, AbortSignal.timeout() cooperative cancellation,
 *   internal try/catch crash isolation). See
 *   `lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts`.
 *
 * Iter-93 starting state: 1 subhook (ty-type-check) inlined; 14 remaining
 * context-injecting PostToolUse hooks queued for iter-94+ migration.
 */

import type {
  PostToolUseInput,
  PostToolUseSubhookDecision,
  PostToolUseSubhookRegistryEntry,
} from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import { POSTTOOLUSE_SUBHOOK_NOOP_DECISION } from "./lib/posttooluse-subhook-contract-for-in-process-orchestrator-with-multi-aggregation-additional-context-merging-iter93.ts";
import { classifyTyTypeCheckForPostToolUseOrchestrator } from "./posttooluse-ty-type-check.ts";
import { classifyTsgoTypeCheckForPostToolUseOrchestrator } from "./posttooluse-tsgo-type-check.ts";
import { classifyOxlintCheckForPostToolUseOrchestrator } from "./posttooluse-oxlint-check.ts";
import { classifyBiomeLintForPostToolUseOrchestrator } from "./posttooluse-biome-lint.ts";

// ══════════════════════════════════════════════════════════════════════════
//  Subhook registry — order matters (aggregation order in the reason)
// ══════════════════════════════════════════════════════════════════════════
//
// Unlike the PreToolUse orchestrator's lightest-first deny-wins ordering,
// the PostToolUse orchestrator runs ALL subhooks regardless of individual
// results — so registry order affects ONLY the visual order of subhook
// contributions inside the aggregated reason. Lightest-first is still
// preferred (cheaper subhooks finish sooner → orchestrator wall-clock
// closer to the slowest subhook, not the sum) but it does not change
// semantic outcome.

const POSTTOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY: PostToolUseSubhookRegistryEntry[] = [
  {
    name: "ty-type-check",
    timeoutMs: 5000,
    classify: classifyTyTypeCheckForPostToolUseOrchestrator,
    description:
      "Runs `ty check <file> --python-version 3.13 --output-format concise` after every Write/Edit of a .py/.pyi file. ~4.7ms incremental (60x faster than mypy → hook-viable). Iter-93 first inlined PostToolUse subhook (kicks off the iter-93+ PostToolUse Write|Edit consolidation arc analogous to iter-84→iter-91 PreToolUse arc). Iter-94 refactor: spawnSync → Bun.spawn (async) so the orchestrator's Promise.all actually achieves OS-level parallelism with sibling subhooks (per Bun docs + 2026 community guidance — spawnSync inside Promise.all yields ZERO parallelism because it blocks the event loop). Lightest-first registry position: FIRST (cheap O(1) extension+venv filter pre-empts the ty subprocess spawn). Surfaces install reminder once per session on ENOENT from posix_spawn. Algorithm encoded in `classifyTyPythonTypeCheckOnEditedFileForPostToolUseOrchestrator` (re-exported as `classifyTyTypeCheckForPostToolUseOrchestrator` for symmetric naming with sibling subhooks).",
  },
  {
    name: "tsgo-type-check",
    timeoutMs: 5000,
    classify: classifyTsgoTypeCheckForPostToolUseOrchestrator,
    description:
      "Runs `tsgo --noEmit` after every Write/Edit of a .ts/.tsx file. tsgo is the native Go TypeScript compiler (~170ms full project check). Iter-94 second inlined PostToolUse subhook (2/15 in the iter-93+ migration arc). Async Bun.spawn from day one (no spawnSync legacy). Project-scoped: walks up to find the nearest tsconfig.json directory and runs from there, then filters output to errors referencing the edited file's tsconfig-relative path (avoids basename collisions when two index.ts files live in different project subdirs). Lightest-first registry position: SECOND (cheap O(1) .ts/.tsx extension filter pre-empts the tsgo subprocess spawn). Algorithm encoded in `classifyTsgoNativeGoTypeScriptCompilerProjectScopedTypeCheckForPostToolUseOrchestrator` (re-exported as `classifyTsgoTypeCheckForPostToolUseOrchestrator` for symmetric naming).",
  },
  {
    name: "oxlint-check",
    timeoutMs: 5000,
    classify: classifyOxlintCheckForPostToolUseOrchestrator,
    description:
      "Runs `oxlint -D correctness -D suspicious` after every Write/Edit of a .ts/.tsx/.js/.jsx/.mjs/.cjs/.mts/.cts file. oxlint is the Oxc Rust-based linter (~40-65ms typical). Iter-95 third inlined PostToolUse subhook (3/15 in the iter-93+ migration arc). Async Bun.spawn from day one via the iter-95 shared lib helpers (`executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail`). Only the correctness + suspicious categories enabled — these catch RUNTIME bugs (const reassignment, duplicate keys, debugger statements) rather than style preferences (which belong in config-level enforcement). Algorithm encoded in `classifyOxlintCorrectnessAndSuspiciousCategoryLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator` (re-exported as `classifyOxlintCheckForPostToolUseOrchestrator`).",
  },
  {
    name: "biome-lint",
    timeoutMs: 5000,
    classify: classifyBiomeLintForPostToolUseOrchestrator,
    description:
      "Runs `biome lint <file>` after every Write/Edit of a JS/TS file (~40-80ms). Iter-95 fourth inlined PostToolUse subhook (4/15 in arc). Async Bun.spawn from day one via the iter-95 shared lib helpers. COMPLEMENTARY-TO-OXLINT (not a replacement): catches rules oxlint misses with default config — useConst, noDoubleEquals, useNodejsImportProtocol, noImplicitAnyLet, noAssignInExpressions. Suppresses 6 noisy rules via --skip (noExplicitAny, useNodejsImportProtocol, noUnusedVariables, noNonNullAssertion, useTemplate, noUnusedImports) that caused 67% false-positive rate on real codebases. Algorithm encoded in `classifyBiomeComplementaryToOxlintLintOnEditedJavaScriptOrTypeScriptFileForPostToolUseOrchestrator` (re-exported as `classifyBiomeLintForPostToolUseOrchestrator`).",
  },
];

// ══════════════════════════════════════════════════════════════════════════
//  Per-subhook execution with cooperative timeout + crash isolation
// ══════════════════════════════════════════════════════════════════════════

interface PostToolUseSubhookExecutionResult {
  name: string;
  decision: PostToolUseSubhookDecision;
  elapsedMs: number;
  timedOut: boolean;
  errored: boolean;
  errorMessage?: string;
}

/**
 * Convert an AbortSignal into a rejecting promise that fires when the
 * signal aborts. Used by the orchestrator to race a classifier against
 * AbortSignal.timeout(). Hoisted to module scope (closure-free) per the
 * oxlint consistent-function-scoping rule. Mirrors the iter-87 PreToolUse
 * orchestrator's helper of the same shape.
 */
async function awaitAbortSignalAsPostToolUseTimeoutSentinelPromiseRejection(
  signal: AbortSignal,
): Promise<never> {
  return new Promise<never>((_resolve, reject) => {
    signal.addEventListener(
      "abort",
      () => {
        reject(signal.reason);
      },
      { once: true },
    );
  });
}

/**
 * Execute one subhook with cooperative timeout + crash isolation.
 *
 * - Timeout: AbortSignal.timeout(timeoutMs) races against the classifier.
 *   On timeout, returns a fail-open `noop` decision with `timedOut: true`.
 * - Crash: try/catch wraps the classifier (classifiers SHOULD catch their
 *   own errors per contract, but this is belt-and-suspenders). On error,
 *   returns a fail-open `noop` decision with `errored: true`.
 */
async function executeSinglePostToolUseSubhookWithCooperativeAbortSignalTimeoutAndCrashIsolation(
  entry: PostToolUseSubhookRegistryEntry,
  input: PostToolUseInput,
): Promise<PostToolUseSubhookExecutionResult> {
  const startNanos = process.hrtime.bigint();
  const timeoutSignal = AbortSignal.timeout(entry.timeoutMs);

  try {
    const decision: PostToolUseSubhookDecision = await Promise.race([
      entry.classify(input),
      awaitAbortSignalAsPostToolUseTimeoutSentinelPromiseRejection(timeoutSignal),
    ]);
    const elapsedMs = Number(process.hrtime.bigint() - startNanos) / 1_000_000;
    return { name: entry.name, decision, elapsedMs, timedOut: false, errored: false };
  } catch (raw: unknown) {
    const elapsedMs = Number(process.hrtime.bigint() - startNanos) / 1_000_000;
    const isTimeoutDomException =
      raw instanceof DOMException && raw.name === "TimeoutError";
    if (isTimeoutDomException) {
      return {
        name: entry.name,
        decision: POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
        elapsedMs,
        timedOut: true,
        errored: false,
      };
    }
    const errorMessage = raw instanceof Error ? raw.message : String(raw);
    return {
      name: entry.name,
      decision: POSTTOOLUSE_SUBHOOK_NOOP_DECISION,
      elapsedMs,
      timedOut: false,
      errored: true,
      errorMessage,
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Aggregator: merge non-noop subhook decisions into ONE reason string
// ══════════════════════════════════════════════════════════════════════════

const POSTTOOLUSE_ORCHESTRATOR_AGGREGATED_REASON_SECTION_DELIMITER = "\n\n──────────────────────\n\n";

/**
 * Fold every additional_context subhook contribution into one aggregated
 * reason string, with provenance prefix CONDITIONALLY applied:
 *
 *   - When ONLY ONE subhook contributes (e.g., only ty fired on a .py
 *     edit), the aggregator emits the subhook's message verbatim — no
 *     `[orchestrator-subhook: <name>]` prefix. Claude sees the same
 *     unchanged content as the legacy standalone-hook era, preserving
 *     UX continuity for the single-subhook case.
 *
 *   - When TWO OR MORE subhooks contribute (e.g., tsgo + oxlint + biome
 *     all fire on a .ts edit), the aggregator prefixes every section
 *     with `[orchestrator-subhook: <registry.name>]` so Claude can
 *     unambiguously attribute findings to subhooks. Delimiter-joined.
 *
 * Iter-95 usability refinement of iter-94's unconditional-prefix design:
 * the prefix added noise to the common single-subhook case (a .py edit
 * only triggers ty; a .py file is irrelevant to the JS/TS subhooks).
 * Conditional emission resolves that without giving up the multi-subhook
 * provenance signal.
 *
 * If no subhook contributed (every result was `noop`), returns `null`
 * to signal "emit nothing".
 */
function aggregatePostToolUseSubhookAdditionalContextMessagesIntoSingleReasonStringWithProvenancePrefixOnlyWhenMultipleSectionsContribute(
  results: readonly PostToolUseSubhookExecutionResult[],
): string | null {
  // Two-pass: first count contributing sections, then format based on count.
  // (One-pass with array-then-conditional-prefix would also work but is
  // less explicit about the algorithm's conditional invariant.)
  const contributingResults = results.filter(
    (result) => result.decision.kind === "additional_context",
  );

  if (contributingResults.length === 0) return null;

  const shouldEmitProvenancePrefix = contributingResults.length >= 2;

  const renderedSections = contributingResults.map((result) => {
    // narrow: contributingResults is filtered to additional_context only
    if (result.decision.kind !== "additional_context") return "";
    const messageBody = result.decision.message;
    return shouldEmitProvenancePrefix
      ? `[orchestrator-subhook: ${result.name}]\n${messageBody}`
      : messageBody;
  });

  return renderedSections.join(POSTTOOLUSE_ORCHESTRATOR_AGGREGATED_REASON_SECTION_DELIMITER);
}

// ══════════════════════════════════════════════════════════════════════════
//  Main entry — stdin → registry iteration → aggregation → stdout JSON
// ══════════════════════════════════════════════════════════════════════════

async function runPostToolUseEditTimeOrchestratorMain(): Promise<void> {
  let inputText = "";
  for await (const chunk of Bun.stdin.stream()) {
    inputText += new TextDecoder().decode(chunk);
  }

  let parsedInput: PostToolUseInput;
  try {
    parsedInput = JSON.parse(inputText) as PostToolUseInput;
  } catch {
    // Malformed stdin → silent allow (orchestrator never blocks on parse error)
    process.exit(0);
  }

  // Iter-93 invariant: run ALL subhooks (no short-circuit). Use Promise.all
  // to parallelize — each subhook is internally isolated by try/catch, and
  // AbortSignal.timeout() bounds each one's wall-clock independently. The
  // orchestrator's total wall-clock is therefore close to the slowest
  // subhook, not the sum.
  const subhookResults = await Promise.all(
    POSTTOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY.map((entry) =>
      executeSinglePostToolUseSubhookWithCooperativeAbortSignalTimeoutAndCrashIsolation(
        entry,
        parsedInput,
      ),
    ),
  );

  // Operator-visible diagnostics on stderr (transcript-visible via Ctrl-R,
  // not Claude-visible). Mirrors iter-66's stop-orchestrator stderr-routing
  // pattern for non-decision-block summaries.
  for (const result of subhookResults) {
    if (result.timedOut) {
      console.error(
        `[posttooluse-edit-time-orchestrator] subhook ${result.name} TIMED OUT after ${result.elapsedMs.toFixed(1)}ms (timeoutMs=${POSTTOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY.find((e) => e.name === result.name)?.timeoutMs}) — treating as noop (fail-open)`,
      );
    } else if (result.errored) {
      console.error(
        `[posttooluse-edit-time-orchestrator] subhook ${result.name} ERRORED in ${result.elapsedMs.toFixed(1)}ms: ${result.errorMessage} — treating as noop (fail-open)`,
      );
    }
  }

  const aggregatedReasonOrNull =
    aggregatePostToolUseSubhookAdditionalContextMessagesIntoSingleReasonStringWithProvenancePrefixOnlyWhenMultipleSectionsContribute(
      subhookResults,
    );

  if (aggregatedReasonOrNull === null) {
    // No subhook contributed context → silent allow (legacy behavior)
    process.exit(0);
  }

  // Emit ONE consolidated decision:block JSON. The `decision: "block"`
  // keyword is the documented Anthropic-schema mechanism for PostToolUse
  // context-injection — it surfaces the reason as a Claude-visible system
  // reminder, NOT a tool rejection. (Tool has already run by the time
  // PostToolUse fires.)
  console.log(JSON.stringify({ decision: "block", reason: aggregatedReasonOrNull }));
  process.exit(0);
}

if (import.meta.main) {
  runPostToolUseEditTimeOrchestratorMain().catch((error: unknown) => {
    console.error(
      `[posttooluse-edit-time-orchestrator] top-level error (fail-open): ${error instanceof Error ? error.message : String(error)}`,
    );
    process.exit(0);
  });
}
