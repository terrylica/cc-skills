#!/usr/bin/env bun
/**
 * PreToolUse Edit-Time Orchestrator — iter-84
 * Combines multiple Write|Edit subhooks into a single bun process to
 * amortize the ~44ms bun cold-start cost (measured iter-80) across the
 * full PreToolUse Write|Edit registry instead of paying it N separate times.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Architectural precedent vs. departure from iter-66 stop-orchestrator
 * ════════════════════════════════════════════════════════════════════════
 *
 * Iter-66 (stop-orchestrator.ts) consolidated 5 Stop-hook table entries
 * into 1, BUT it subprocess-spawned each subhook. That works for Stop
 * hooks because the savings there come from collapsing operator-visible
 * hook-table entries (and stdout/stderr aggregation), not from process
 * startup cost — Stop hooks fire once per turn, so 5 × bun-startup-floor
 * is a one-time per-turn cost, not a per-tool-call cost.
 *
 * Iter-84 (this file) targets PreToolUse Write|Edit, which fires on
 * EVERY single Write or Edit tool call. With 8 separate hooks.json
 * entries each spawning a fresh bun process at ~44ms cold-start, the
 * unconditional per-call overhead = 8 × 44 = 352ms. If we replicated
 * iter-66's subprocess-spawn pattern here we'd still pay that 352ms.
 * The only way to actually realize the savings is to INLINE subhooks
 * as imported async classifier functions running inside this single
 * bun process. Iter-81's ranker quantified the upside at 308ms saved
 * per Write|Edit once all 8 subhooks are inlined.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Trade-offs and mitigations vs subprocess isolation
 * ════════════════════════════════════════════════════════════════════════
 *
 * Loss: iter-66 got crash-domain isolation for free (a hung or crashing
 * subhook subprocess couldn't take down the others; SIGKILL on timeout).
 * In-process inlining loses that isolation by default.
 *
 * Mitigations (defense-in-depth):
 *   1. Each subhook MUST conform to PreToolUseSubhookContract (pure async
 *      function, no stdin/stdout/exit, returns decision object).
 *   2. Orchestrator wraps every `classify()` call in try/catch — thrown
 *      errors fail-open as `allow` and are logged to stderr.
 *   3. Orchestrator wraps every `classify()` call in Promise.race with a
 *      per-subhook timeout — runaway classifiers fail-open as `allow`
 *      and are logged to stderr (orchestrator does NOT enforce hard
 *      process kill because there's no subprocess to kill; this is a
 *      cooperative timeout that signals via diagnostic log).
 *   4. Subhook order is deterministic (registry-array iteration order);
 *      first-deny-wins matches Claude Code's own multi-hook semantics.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Belt-and-suspenders deny defense (iter-78 / GitHub #37210)
 * ════════════════════════════════════════════════════════════════════════
 *
 * When a subhook returns `deny`, the orchestrator emits THREE deny signals
 * concurrently, because GitHub #37210 documents that Claude Code's Edit
 * tool ignores stdout-JSON `permissionDecision: "deny"` in some build
 * versions, while still respecting stderr + exit 2:
 *
 *   (1) stdout JSON: {hookSpecificOutput: {permissionDecision: "deny", ...}}
 *   (2) stderr diagnostic: "[orchestrator] DENY: <subhook> — <reason>"
 *   (3) process.exit(2)
 *
 * This matches the iter-78 layer3-stripped-path-edit-time-guard pattern.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Iter-84 registry contents (PROOF-OF-CONCEPT — single subhook)
 * ════════════════════════════════════════════════════════════════════════
 *
 * Only `file-size-guard` is inlined in iter-84. Iter-85+ migrates the
 * remaining Write|Edit subhooks one at a time (each migration removes
 * the corresponding standalone hooks.json entry and saves +44ms per call).
 *
 * Migration target order (per iter-81 ranker output, lightest-first to
 * de-risk migrations by exercising the orchestrator on simple subhooks
 * before tackling complex ones):
 *
 *   iter-84  file-size-guard          ← THIS ITER
 *   iter-85  version-guard
 *   iter-86  hoisted-deps-guard
 *   iter-87  gpu-optimization-guard
 *   iter-88  mise-hygiene-guard
 *   iter-89  pyi-stub-guard
 *   iter-90  native-binary-guard
 *   iter-91  vale-claude-md-guard
 *
 * Final state: 1 orchestrator entry for Write|Edit instead of 8 entries,
 * saving (8-1) × 44ms = 308ms per Write|Edit tool call.
 */

import {
  parseStdinOrAllow,
  allow,
  trackHookError,
  type PreToolUseInput,
} from "./pretooluse-helpers.ts";
import type {
  PreToolUseSubhookRegistryEntry,
  PreToolUseSubhookDecision,
} from "./lib/pretooluse-subhook-contract-for-in-process-orchestrator-inlining-iter84.ts";
import { classifyFileSizeGuardForOrchestrator } from "./pretooluse-file-size-guard.ts";

// ══════════════════════════════════════════════════════════════════════════
//  Subhook registry — order matters (first-deny-wins, lightest-first)
// ══════════════════════════════════════════════════════════════════════════

const PRETOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY: PreToolUseSubhookRegistryEntry[] = [
  {
    name: "file-size-guard",
    timeoutMs: 4500,
    classify: classifyFileSizeGuardForOrchestrator,
    description:
      "Blocks Write/Edit operations that would produce files exceeding the per-extension line-count threshold (default 1000 lines, configurable via .claude/file-size-guard.json). Iter-84 first inlined subhook.",
  },
];

// ══════════════════════════════════════════════════════════════════════════
//  Per-subhook execution with cooperative timeout + crash isolation
// ══════════════════════════════════════════════════════════════════════════

interface SubhookExecutionResult {
  name: string;
  decision: PreToolUseSubhookDecision;
  elapsedMs: number;
  timedOut: boolean;
  errored: boolean;
  errorMessage?: string;
}

async function executeSubhookWithCooperativeTimeoutAndCrashIsolation(
  entry: PreToolUseSubhookRegistryEntry,
  input: PreToolUseInput,
): Promise<SubhookExecutionResult> {
  const startTimeMs = Date.now();
  const failOpenAllow: PreToolUseSubhookDecision = { kind: "allow" };

  // Promise.race the classifier against a cooperative timeout. The
  // classifier itself is not killable from outside (no subprocess); this
  // timeout is a *signaling* mechanism so the orchestrator can move on
  // and log the laggard. The classifier may still be running in the
  // background until bun exits.
  //
  // Sentinel Symbol distinguishes timeout from any legitimate decision
  // value; async/await wrapper functions (no floating promise chains)
  // keep rejection paths observable per the JS-silent-failure linter.
  const TIMEOUT_SENTINEL: unique symbol = Symbol("orchestrator-cooperative-timeout");
  type TimeoutSentinel = typeof TIMEOUT_SENTINEL;

  let timeoutHandle: ReturnType<typeof setTimeout> | undefined;

  async function awaitSubhookClassifierResolution(): Promise<PreToolUseSubhookDecision> {
    return await entry.classify(input);
  }

  async function awaitCooperativeTimeoutWindow(): Promise<TimeoutSentinel> {
    return await new Promise<TimeoutSentinel>((resolve) => {
      timeoutHandle = setTimeout(() => resolve(TIMEOUT_SENTINEL), entry.timeoutMs);
    });
  }

  try {
    const raceResult: PreToolUseSubhookDecision | TimeoutSentinel = await Promise.race([
      awaitSubhookClassifierResolution(),
      awaitCooperativeTimeoutWindow(),
    ]);
    if (timeoutHandle !== undefined) clearTimeout(timeoutHandle);

    if (raceResult === TIMEOUT_SENTINEL) {
      return {
        name: entry.name,
        decision: failOpenAllow,
        elapsedMs: Date.now() - startTimeMs,
        timedOut: true,
        errored: false,
      };
    }
    return {
      name: entry.name,
      decision: raceResult,
      elapsedMs: Date.now() - startTimeMs,
      timedOut: false,
      errored: false,
    };
  } catch (err) {
    if (timeoutHandle !== undefined) clearTimeout(timeoutHandle);
    const errorMessage = err instanceof Error ? err.message : String(err);
    return {
      name: entry.name,
      decision: failOpenAllow,
      elapsedMs: Date.now() - startTimeMs,
      timedOut: false,
      errored: true,
      errorMessage,
    };
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Orchestrator entry point
// ══════════════════════════════════════════════════════════════════════════

const ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX = "[pretooluse-edit-time-orchestrator]";

function emitBeltAndSuspendersDenyDecisionOutputAndExitWithCodeTwo(
  subhookName: string,
  reason: string,
): never {
  // (1) stdout JSON deny (the canonical channel; Edit-tool sometimes ignores per GH #37210)
  const denyOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} ${subhookName} → DENY\n${reason}`,
    },
  };
  process.stdout.write(JSON.stringify(denyOutput) + "\n");

  // (2) stderr diagnostic (always respected per GH #37210)
  process.stderr.write(
    `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} DENY from subhook=${subhookName}: ${reason}\n`,
  );

  // (3) exit 2 (always respected per GH #37210)
  process.exit(2);
}

function emitAskDecisionOutputAndExit(subhookName: string, reason: string): void {
  const askOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} ${subhookName} → ASK\n${reason}`,
    },
  };
  process.stdout.write(JSON.stringify(askOutput) + "\n");
}

async function main(): Promise<void> {
  const input = await parseStdinOrAllow("pretooluse-edit-time-orchestrator");
  if (!input) return;

  // Fastpath: only run the registry on Write/Edit. For any other tool
  // (which shouldn't happen given the hooks.json matcher, but defense-
  // in-depth), allow immediately.
  if (input.tool_name !== "Write" && input.tool_name !== "Edit") {
    return allow();
  }

  // Iterate registry in order; first deny/ask short-circuits.
  for (const entry of PRETOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY) {
    const result = await executeSubhookWithCooperativeTimeoutAndCrashIsolation(entry, input);

    if (result.timedOut) {
      process.stderr.write(
        `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} TIMEOUT subhook=${entry.name} after ${entry.timeoutMs}ms — fail-open allow\n`,
      );
      continue;
    }

    if (result.errored) {
      process.stderr.write(
        `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} ERROR subhook=${entry.name}: ${result.errorMessage} — fail-open allow\n`,
      );
      trackHookError(
        `pretooluse-edit-time-orchestrator/${entry.name}`,
        result.errorMessage ?? "(unknown)",
      );
      continue;
    }

    if (result.decision.kind === "deny") {
      emitBeltAndSuspendersDenyDecisionOutputAndExitWithCodeTwo(
        entry.name,
        result.decision.reason ?? "(no reason given)",
      );
    }
    if (result.decision.kind === "ask") {
      emitAskDecisionOutputAndExit(
        entry.name,
        result.decision.reason ?? "(no reason given)",
      );
      return;
    }
    // allow → continue to next subhook
  }

  // All subhooks returned allow (or fail-open allow).
  allow();
}

main().catch((err) => {
  const message = err instanceof Error ? err.message : String(err);
  process.stderr.write(`${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} fatal: ${message}\n`);
  trackHookError("pretooluse-edit-time-orchestrator", message);
  allow(); // Fail-open at the outermost layer
});
