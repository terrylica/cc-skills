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
import { classifyVersionGuardForOrchestrator } from "./pretooluse-version-guard.ts";
import { classifyHoistedDepsGuardForOrchestrator } from "./pretooluse-hoisted-deps-guard.ts";
import { classifyGpuOptimizationGuardForOrchestrator } from "./pretooluse-gpu-optimization-guard.ts";

// ══════════════════════════════════════════════════════════════════════════
//  Subhook registry — order matters (first-deny-wins, lightest-first)
// ══════════════════════════════════════════════════════════════════════════
//
// Lightest-first ordering rationale: subhooks with O(1) early-exit fastpaths
// (non-Write/Edit tools, non-markdown files, plan mode) should run BEFORE
// subhooks that do file I/O or large content scans. The orchestrator
// short-circuits on first deny/ask, so the cheapest filters win the most
// when the registry grows.

const PRETOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY: PreToolUseSubhookRegistryEntry[] = [
  {
    name: "version-guard",
    timeoutMs: 3000,
    classify: classifyVersionGuardForOrchestrator,
    description:
      "Blocks Write/Edit on markdown files that introduce hardcoded version strings (semver, calver, pre-release tags) outside CHANGELOG/HISTORY/ADR/planning paths. Forces use of <version> placeholder pattern (SSoT discipline). Iter-85 inlined; fast O(1) extension+path filter pre-empts the regex scan on non-markdown files.",
  },
  {
    name: "hoisted-deps-guard",
    timeoutMs: 4000,
    classify: classifyHoistedDepsGuardForOrchestrator,
    description:
      "Blocks pyproject.toml Write/Edit that violates any of 3 monorepo policies: (1) root-only pyproject.toml [except maturin PyO3 crates that must co-locate with Cargo.toml], (2) [tool.uv.sources] paths escaping git root, (3) [dependency-groups] in sub-packages. Iter-86 inlined; O(1) filename-suffix fastpath skips non-pyproject.toml writes, then spawns git rev-parse subprocess only for actual pyproject.toml edits.",
  },
  {
    name: "gpu-optimization-guard",
    timeoutMs: 4000,
    classify: classifyGpuOptimizationGuardForOrchestrator,
    description:
      "Blocks Write/Edit on Python PyTorch training scripts missing mandatory GPU optimizations (AMP, torch.compile, DataLoader num_workers/pin_memory, auto-batch-size, cudnn.benchmark, device availability check). Iter-87 inlined; O(1) .py extension + test-file filename fastpath pre-empts the PyTorch training-script regex scan, then async loads .claude/gpu-optimization-guard.json config only when training script is detected.",
  },
  {
    name: "file-size-guard",
    timeoutMs: 4500,
    classify: classifyFileSizeGuardForOrchestrator,
    description:
      "Blocks Write/Edit operations that would produce files exceeding the per-extension line-count threshold (default 1000 lines, configurable via .claude/file-size-guard.json). Iter-84 first inlined subhook; does sync fs.readFileSync for Edit operations (~1-2ms typical).",
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

/**
 * Convert an AbortSignal into a rejecting promise that fires when the signal
 * aborts. Used by the orchestrator to race a classifier against
 * AbortSignal.timeout(). Hoisted to module scope (closure-free) per the
 * oxlint consistent-function-scoping rule.
 *
 * Iter-87 design: AbortSignal.timeout() is the 2026 community-standard
 * primitive for promise cancellation (Node 17.3+, Bun 1.0+, native Web
 * Platform API). It rejects with a DOMException named "TimeoutError" so
 * the caller distinguishes timeout-rejections from classifier-thrown errors
 * via the standard `.name` property.
 */
async function awaitAbortSignalAsTimeoutSentinelPromiseRejection(
  signal: AbortSignal,
): Promise<never> {
  return await new Promise<never>((_, reject) => {
    if (signal.aborted) {
      reject(signal.reason);
      return;
    }
    signal.addEventListener("abort", () => reject(signal.reason), { once: true });
  });
}

async function executeSubhookWithCooperativeTimeoutAndCrashIsolation(
  entry: PreToolUseSubhookRegistryEntry,
  input: PreToolUseInput,
): Promise<SubhookExecutionResult> {
  const startTimeMs = Date.now();
  const failOpenAllow: PreToolUseSubhookDecision = { kind: "allow" };

  // Iter-87 refactor: idiomatic AbortSignal.timeout() pattern replaces the
  // iter-84 Symbol-sentinel + raw setTimeout. AbortSignal.timeout() is the
  // 2026 community-standard primitive for promise cancellation (Node 17.3+,
  // Bun 1.0+, native Web Platform API). It auto-creates an AbortSignal that
  // fires its `abort` event after timeoutMs with a `TimeoutError` DOMException
  // as the reason — no manual setTimeout bookkeeping, no Symbol-sentinel
  // type gymnastics, and the abort signal is composable with fetch() and
  // other AbortSignal-aware APIs in case future subhooks adopt them.
  //
  // The cooperative-timeout semantic is unchanged: classifiers still cannot
  // be forcibly killed (no subprocess); the AbortSignal merely tells the
  // orchestrator to move on and log the laggard, while the classifier's
  // promise continues running until bun exits.

  const cooperativeTimeoutAbortSignal = AbortSignal.timeout(entry.timeoutMs);

  try {
    const decision: PreToolUseSubhookDecision = await Promise.race([
      entry.classify(input),
      awaitAbortSignalAsTimeoutSentinelPromiseRejection(cooperativeTimeoutAbortSignal),
    ]);

    return {
      name: entry.name,
      decision,
      elapsedMs: Date.now() - startTimeMs,
      timedOut: false,
      errored: false,
    };
  } catch (err) {
    // AbortSignal.timeout() rejects with a DOMException named "TimeoutError".
    // Detect via the standard `.name` property rather than instanceof checks
    // (which can be fragile across realms in some runtimes).
    if (err instanceof Error && err.name === "TimeoutError") {
      return {
        name: entry.name,
        decision: failOpenAllow,
        elapsedMs: Date.now() - startTimeMs,
        timedOut: true,
        errored: false,
      };
    }
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

/**
 * Emit a deny/ask decision with belt-and-suspenders defense per GH #37210
 * (iter-78 pattern):
 *   (1) stdout JSON with hookSpecificOutput.permissionDecision = <decision>
 *   (2) stderr diagnostic line (always respected even when Edit-tool
 *       ignores stdout-JSON deny in some Claude Code build versions)
 *   (3) process.exitCode = 2  (iter-85 hardening — replaces process.exit(2);
 *       the exitCode pattern lets bun's event loop drain stdout buffers
 *       BEFORE the process terminates, eliminating the truncation hazard
 *       the iter-84 audit flagged where short-JSON-then-immediate-exit
 *       could race the kernel write buffer)
 *
 * Iter-85 audit-driven hardening: the `ask` decision path now uses the
 * same belt-and-suspenders defense as `deny` (previously `ask` only
 * emitted stdout JSON, which would silently fail on the same Claude Code
 * build versions that drop stdout-JSON deny).
 *
 * Uses a callback-form stdout.write to wait for flush completion before
 * setting exitCode and returning. Defense-in-depth: even if the callback
 * never fires (e.g., stdout closed early), the function still returns and
 * the caller's natural process exit picks up the exitCode value.
 */
function emitBeltAndSuspendersBlockingDecisionWithStdoutDrainBeforeExitCodeTwo(
  decisionKind: "deny" | "ask",
  subhookName: string,
  reason: string,
): Promise<void> {
  const stdoutBlockingDecisionJsonPayload = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: decisionKind,
      permissionDecisionReason:
        `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} ${subhookName} → ${decisionKind.toUpperCase()}\n${reason}`,
    },
  };
  const serializedJsonLine = JSON.stringify(stdoutBlockingDecisionJsonPayload) + "\n";

  // (2) stderr diagnostic — fire synchronously so it's queued before we wait on stdout
  process.stderr.write(
    `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} ${decisionKind.toUpperCase()} from subhook=${subhookName}: ${reason}\n`,
  );

  // (3) exitCode (not exit() — lets bun drain stdout naturally before termination)
  process.exitCode = 2;

  // (1) stdout JSON with drain-await — Promise resolves once the kernel
  // accepts the bytes, eliminating the race the iter-84 audit flagged
  // where process.exit(2) before drain could truncate the JSON payload.
  return new Promise<void>((resolve) => {
    const writeAcceptedByKernel = process.stdout.write(serializedJsonLine, () => resolve());
    if (writeAcceptedByKernel) {
      // Already drained synchronously; the callback will still fire on
      // next tick but we don't have to wait for it.
      resolve();
    }
  });
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

    if (result.decision.kind === "deny" || result.decision.kind === "ask") {
      await emitBeltAndSuspendersBlockingDecisionWithStdoutDrainBeforeExitCodeTwo(
        result.decision.kind,
        entry.name,
        result.decision.reason ?? "(no reason given)",
      );
      return; // exitCode=2 is already set; let bun's event loop finish naturally
    }
    // allow → continue to next subhook
  }

  // All subhooks returned allow (or fail-open allow).
  allow();
}

// Iter-85 audit-driven hardening: install a process-level unhandled-rejection
// handler BEFORE main() runs. Bun's current default behavior is to log
// unhandled rejections to stderr but NOT exit the process. Node's behavior
// is the opposite. If the runtime under us ever switches to Node-compatible
// "exit-on-unhandled-rejection" semantics, the orchestrator would die mid-
// registry and skip remaining subhooks. This handler fails-open (allow) so
// the tool call still proceeds when a subhook's internal promise rejects
// without being caught by the per-subhook try/catch + Promise.race wrap.
process.on("unhandledRejection", (reason: unknown) => {
  const message = reason instanceof Error ? reason.message : String(reason);
  process.stderr.write(
    `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} unhandledRejection: ${message} — fail-open allow\n`,
  );
  trackHookError("pretooluse-edit-time-orchestrator/unhandledRejection", message);
  // Don't allow() here — main() will still complete and emit allow normally.
  // Explicit allow() here would emit duplicate JSON to stdout.
});

main().catch((err) => {
  const message = err instanceof Error ? err.message : String(err);
  process.stderr.write(`${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} fatal: ${message}\n`);
  trackHookError("pretooluse-edit-time-orchestrator", message);
  allow(); // Fail-open at the outermost layer
});
