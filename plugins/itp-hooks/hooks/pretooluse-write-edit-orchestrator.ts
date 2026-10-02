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
 *   4. Subhook order is deterministic (registry-array iteration order).
 *      Aggregation follows Claude Code's own precedence for several hooks,
 *      deny > ask > allow: the first deny wins and stops the run; an ask is
 *      held while the remaining subhooks are checked for a deny.
 *
 * ════════════════════════════════════════════════════════════════════════
 *  Decision emission: JSON on stdout, exit 0 — for deny AND ask
 * ════════════════════════════════════════════════════════════════════════
 *
 * Both decisions are one `hookSpecificOutput.permissionDecision` JSON line
 * on stdout, and the process exits 0. Per code.claude.com/docs/en/hooks:
 *   - "Exit 2 means a blocking error. On events that can block, exit 2
 *     blocks whether or not you print JSON" — so the exit 2 this file used
 *     to set on `ask` turned every ask into a hard block, never a prompt.
 *   - "Choose one approach per hook: either use exit codes alone for
 *     signaling, or exit 0 and print JSON for structured control." `ask`
 *     exists only as JSON, so JSON-with-exit-0 is the one approach that
 *     covers both decisions; `"deny"` in that JSON "prevents the tool call".
 *
 * Until 2026-10-01 a deny also set exit 2 ("belt-and-suspenders", citing
 * GitHub anthropics/claude-code#37210). That issue was closed not-planned
 * after its reporter found their own hook's flat JSON and exit 2 were the
 * cause; exit 0 with the `hookSpecificOutput` wrapper denied Edit/Write
 * correctly. The Bash guard orchestrator already emits deny this way.
 * A stderr diagnostic line is still written; on exit 0 it reaches only
 * the debug log.
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
} from "./lib/pretooluse-subhook-contract-iter84.ts";
import { classifyFileSizeGuardForOrchestrator } from "./pretooluse-file-size-guard.ts";
import { classifyVersionGuardForOrchestrator } from "./pretooluse-version-guard.ts";
import { classifyTypeScriptVersionGuardForOrchestrator } from "./pretooluse-typescript-version-guard.ts";
import { classifyHoistedDepsGuardForOrchestrator } from "./pretooluse-hoisted-deps-guard.ts";
import { classifyGpuOptimizationGuardForOrchestrator } from "./pretooluse-gpu-optimization-guard.ts";
import { classifyMiseHygieneGuardForOrchestrator } from "./pretooluse-mise-hygiene-guard.ts";
import { classifyPyiStubGuardForOrchestrator } from "./pretooluse-pyi-stub-guard.ts";
import { classifyNativeBinaryGuardForOrchestrator } from "./pretooluse-native-binary-guard.ts";
import { classifyValeClaudeMdGuardForOrchestrator } from "./pretooluse-vale-claude-md-guard.ts";
import { classifyShellScriptSafetyGuardForOrchestrator } from "./pretooluse-shell-script-safety-guard.ts";
import { classifySkillPluginRootGuardForOrchestrator } from "./pretooluse-skill-plugin-root-guard.ts";

// ══════════════════════════════════════════════════════════════════════════
//  Subhook registry — order matters (first-deny-wins, lightest-first)
// ══════════════════════════════════════════════════════════════════════════
//
// Lightest-first ordering rationale: subhooks with O(1) early-exit fastpaths
// (non-Write/Edit tools, non-markdown files, plan mode) should run BEFORE
// subhooks that do file I/O or large content scans. The orchestrator
// short-circuits on the first deny, so the cheapest filters win the most
// when the registry grows.

export const PRETOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY: PreToolUseSubhookRegistryEntry[] =
  [
    {
      name: "version-guard",
      timeoutMs: 3000,
      classify: classifyVersionGuardForOrchestrator,
      description:
        "Blocks Write/Edit on markdown files that introduce hardcoded version strings (semver, calver, pre-release tags) outside CHANGELOG/HISTORY/ADR/planning paths. Forces use of <version> placeholder pattern (SSoT discipline). Iter-85 inlined; fast O(1) extension+path filter pre-empts the regex scan on non-markdown files.",
    },
    {
      name: "shell-script-safety-guard",
      timeoutMs: 3000,
      classify: classifyShellScriptSafetyGuardForOrchestrator,
      description:
        "Blocks Write/Edit on shell scripts that introduce two mechanically-decidable defects: (1) RULE 1 — STATUS-LOSS-AFTER-IF: $? after fi with no else/elif branch masks real failure (2026-08-02 css incident); (2) RULE 2 — MASKED-COMMAND-SUBSTITUTION: local|export|readonly|declare|typeset VAR=$(cmd) defeats set -e errexit. Iter-119; O(1) extension+shebang fastpath pre-empts regex scan on non-shell files. Escape hatch: SHELL-SAFETY-OK marker (FILE_WIDE). For Edit: flags only net-new defects.",
    },
    {
      name: "skill-plugin-root-guard",
      timeoutMs: 3000,
      classify: classifySkillPluginRootGuardForOrchestrator,
      description:
        "Blocks Write/Edit on skill markdown (any .md under a skills/ directory) that references CLAUDE_PLUGIN_ROOT in a shape the runtime cannot honor. Three deniable kinds: BARE_SPELLING (bare $CLAUDE_PLUGIN_ROOT — the substitution regex requires braces, so it is unsubstitutable everywhere, manifests included), NON_SUBSTITUTING_DEFAULT (the braced form carrying a ':-fallback' shell default — the regex needs the closing brace right after the name, so this silently always takes the hardcoded fallback and pins the skill to the L2 marketplace clone instead of the installed version), and BRACED_IN_SHELL_CONTEXT (the braced form on a non-JSON line — a SKILL.md body is served to the model verbatim on the Skill-tool path, so nothing substitutes it and Bash sees an unset variable). JSON manifest lines (key-value or array-element shape) keep the braced form and are exempt. Origin: the 2026-08-05 /notes-commander:draft-hold exit-127 incident, whose upstream cause was two reference docs teaching the rule inverted. Steers to the cc-plugin-root resolver (scripts/cc-plugin-root), which reads installed_plugins.json for the LIVE install path rather than globbing the version cache (which retains orphaned versions). Registry position EARLY — O(1) path filter (/skills/ substring + .md suffix) then an O(1) content-sentinel check; the single disk read is deferred until a real candidate violation exists. Escape hatch: FILE_WIDE `SKILL-PLUGIN-ROOT-OK: <reason ≥10 chars>`, honored in the proposed text or in the on-disk file (iter-15 pattern) so docs ABOUT the variable stay editable.",
    },
    {
      name: "typescript-version-guard",
      timeoutMs: 3000,
      classify: classifyTypeScriptVersionGuardForOrchestrator,
      description:
        "Blocks Write/Edit on package.json files that declare TypeScript < 7.x (the Go-native tsc era). Forces upgrade from pre-7 versions via 'typescript': 'latest' (+ commit lockfile), or enforces dual-install compat alias 'typescript': 'npm:@typescript/typescript6@^6.0.2' + '@typescript/native': 'npm:typescript@latest' for compiler-embedding tools (Volar/Vue/Svelte/Astro, Angular templates, typescript-eslint, ts-morph) that cannot run on TS 7.0's missing programmatic API (available 7.1+). Iter-92 inlined; O(1) basename filter pre-empts regex scan on non-package.json files. Iter-15 fix: Edit may target a region NOT containing ALLOW-LEGACY-TS marker but file on disk has it — async fs.read via Bun.file() honors the escape hatch. Sanctions @typescript/typescript6 compat alias explicitly; naive major-version regex would misread the '6' and wrongly block the Volar migration path. SSoT: ~/.claude/typescript-latest-CLAUDE.md.",
    },
    {
      name: "hoisted-deps-guard",
      timeoutMs: 4000,
      classify: classifyHoistedDepsGuardForOrchestrator,
      description:
        "Blocks pyproject.toml Write/Edit that violates any of 3 monorepo policies: (1) root-only pyproject.toml [except maturin PyO3 crates that must co-locate with Cargo.toml], (2) [tool.uv.sources] paths escaping git root, (3) [dependency-groups] in sub-packages. Iter-86 inlined; O(1) filename-suffix fastpath skips non-pyproject.toml writes, then spawns git rev-parse subprocess only for actual pyproject.toml edits.",
    },
    {
      name: "mise-hygiene-guard",
      timeoutMs: 3000,
      classify: classifyMiseHygieneGuardForOrchestrator,
      description:
        "Blocks mise.toml Write/Edit that violates 2 hygiene policies: (1) secrets (api keys, tokens, passwords) detected in shared mise.toml [should be in .mise.local.toml instead], (2) line count exceeds 100 [suggests hub-spoke refactoring with [task_config].includes]. Iter-88 inlined; O(1) filename-allowlist + ignore-list fastpath skips non-mise.toml writes (including the intentionally-secret-bearing .mise.local.toml).",
    },
    {
      name: "pyi-stub-guard",
      timeoutMs: 3000,
      classify: classifyPyiStubGuardForOrchestrator,
      description:
        "Blocks Write/Edit on Python `__init__.py` / `__init__.pyi` files that contain top-level class/def/decorator definitions (PEP 561 + clean-package-structure: init files MUST be thin re-export layers, definitions belong in dedicated modules). Iter-89 inlined; O(1) `__init__.py`/`__init__.pyi` filename-suffix fastpath skips all non-init Python writes. Algorithm encoded in `classifyInitFileTopLevelDefinitionMonolithGuardForOrchestrator` (re-exported as `classifyPyiStubGuardForOrchestrator` for symmetric naming with sibling subhooks). Escape hatch: `# INIT-MONOLITH-OK` comment in content. Re-export-dominated-write heuristic exempts files where ≥70% of meaningful lines are imports.",
    },
    {
      name: "native-binary-guard",
      timeoutMs: 4000,
      classify: classifyNativeBinaryGuardForOrchestrator,
      description:
        "Blocks Write/Edit on macOS launchd-related files (under ~/.claude/automation/, ~/Library/LaunchAgents/, ~/Library/LaunchDaemons/) that introduce shell scripts or plist `<string>/bin/bash</string>` / `<string>...something.sh</string>` ProgramArguments references. Forces compiled native binaries (Swift preferred) so launchd services show proper names in System Settings > Login Items instead of a generic 'bash' entry. Iter-90 inlined; O(1) launchd-directory-substring fastpath replaces the standalone-mode raw-stdin keyword prefilter (cheaper because orchestrator already JSON-parsed the input). Algorithm encoded in `classifyMacosLaunchdNativeBinaryRequiredGuardForOrchestrator` (re-exported as `classifyNativeBinaryGuardForOrchestrator` for symmetric naming). Iter-15 fix preserved: Edit may target a region NOT containing `BASH-LAUNCHD-OK` marker but the file on disk has it — async fs.readFile via Bun.file() honors the file-wide opt-out. Hardening: a bare interpreter as launchd arg0 (Program or first ProgramArguments entry) — /bin/bash, /bin/sh, bun, node, python, env, etc. — is DENIED for .plist files EVEN WITH the BASH-LAUNCHD-OK marker, because Login Items shows basename(arg0); the marker waives 'must be a native binary' but NOT 'arg0 must be a NAMED script/binary so the panel is identifiable'. Escape hatch: `# BASH-LAUNCHD-OK` (or `<!-- BASH-LAUNCHD-OK -->` in plists) — bash is allowed, but only via a named arg0 script.",
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
    {
      name: "vale-claude-md-guard",
      timeoutMs: 12000,
      classify: classifyValeClaudeMdGuardForOrchestrator,
      description:
        "Blocks Write/Edit on CLAUDE.md files with vale lint warning-or-error findings (terminology config at ~/.claude/.vale.ini). Iter-91 inlined (FINAL SUBHOOK — completes the iter-84→iter-91 PreToolUse Write|Edit migration arc). Heaviest classifier in the registry: spawns external `vale` subprocess against a tempfile holding the proposed content. Typical wall-clock: 100-300ms. timeoutMs=12000ms is generous to accommodate slow-disk / cold-cache machines without spurious AbortSignal.timeout() trips. Registry position LAST per lightest-first rule — Edit-path scope-to-changed-lines (±3-line buffer) heuristic preserved. Algorithm encoded in `classifyValeTerminologyConformanceOnClaudeMdGuardForOrchestrator` (re-exported as `classifyValeClaudeMdGuardForOrchestrator` for symmetric naming with sibling subhooks).",
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
    signal.addEventListener("abort", () => reject(signal.reason), {
      once: true,
    });
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
      awaitAbortSignalAsTimeoutSentinelPromiseRejection(
        cooperativeTimeoutAbortSignal,
      ),
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

const ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX =
  "[pretooluse-edit-time-orchestrator]";

/** A non-allow verdict from the registry, attributed to the subhook that gave it. */
export interface EditTimeOrchestratorVerdict {
  kind: "deny" | "ask";
  subhookName: string;
  reason: string;
}

/**
 * The single PreToolUse JSON response for a deny or ask verdict. Exported so
 * tests can pin the exact shape Claude Code reads.
 */
export function buildPermissionDecisionResponse(
  verdict: EditTimeOrchestratorVerdict,
): object {
  return {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: verdict.kind,
      permissionDecisionReason: `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} ${verdict.subhookName} → ${verdict.kind.toUpperCase()}\n${verdict.reason}`,
    },
  };
}

/**
 * Emit a deny or ask as PreToolUse JSON on stdout and leave the exit code at 0.
 * Exit 0 is load-bearing: the hooks reference says exit 2 blocks "whether or
 * not you print JSON", so exit 2 would turn an ask into a hard block (see the
 * file header).
 *
 * Waits for the stdout write callback before resolving, so the process cannot
 * end with the JSON line still buffered (the iter-84 truncation hazard). If the
 * callback never fires (stdout closed early) the write is abandoned and the
 * process still exits 0; Claude Code then sees no decision, which on this
 * event means the normal permission flow.
 */
export function emitPermissionDecisionAndDrainStdout(
  verdict: EditTimeOrchestratorVerdict,
): Promise<void> {
  const serializedJsonLine =
    JSON.stringify(buildPermissionDecisionResponse(verdict)) + "\n";

  // Diagnostic only: on exit 0 Claude Code sends stderr to the debug log.
  process.stderr.write(
    `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} ${verdict.kind.toUpperCase()} from subhook=${verdict.subhookName}: ${verdict.reason}\n`,
  );

  process.exitCode = 0;

  return new Promise<void>((resolve) => {
    process.stdout.write(serializedJsonLine, () => resolve());
  });
}

/**
 * Run every subhook against one input and fold their verdicts with Claude
 * Code's precedence, deny > ask > allow: the first deny returns at once; the
 * first ask is held while later subhooks are still checked for a deny.
 * Returns null when every subhook allowed (timeouts and throws fail open).
 */
export async function runEditTimeSubhookRegistry(
  input: PreToolUseInput,
  registry: readonly PreToolUseSubhookRegistryEntry[] = PRETOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY,
): Promise<EditTimeOrchestratorVerdict | null> {
  let heldAsk: EditTimeOrchestratorVerdict | null = null;

  for (const entry of registry) {
    const result = await executeSubhookWithCooperativeTimeoutAndCrashIsolation(
      entry,
      input,
    );

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

    const reason = result.decision.reason ?? "(no reason given)";
    if (result.decision.kind === "deny") {
      return { kind: "deny", subhookName: entry.name, reason };
    }
    if (result.decision.kind === "ask" && heldAsk === null) {
      heldAsk = { kind: "ask", subhookName: entry.name, reason };
    }
    // allow (or a second ask) → continue to next subhook
  }

  return heldAsk;
}

export async function main(
  registry: readonly PreToolUseSubhookRegistryEntry[] = PRETOOLUSE_EDIT_TIME_ORCHESTRATOR_SUBHOOK_REGISTRY,
): Promise<void> {
  const input = await parseStdinOrAllow("pretooluse-edit-time-orchestrator");
  if (!input) return;

  // Fastpath: only run the registry on Write/Edit. The hooks.json matcher is `Write|Edit`, the two
  // file-content tools Claude Code ships, so any other tool name reaching this line is outside every
  // classifier's scope and is allowed through unchecked. NotebookEdit is deliberately not matched: its
  // payload is a notebook cell, not file content.
  if (input.tool_name !== "Write" && input.tool_name !== "Edit") {
    return allow();
  }

  // deny > ask > allow (see runEditTimeSubhookRegistry).
  const verdict = await runEditTimeSubhookRegistry(input, registry);
  if (verdict !== null) {
    await emitPermissionDecisionAndDrainStdout(verdict);
    return;
  }

  // All subhooks returned allow (or fail-open allow).
  allow();
}

if (import.meta.main) {
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
    trackHookError(
      "pretooluse-edit-time-orchestrator/unhandledRejection",
      message,
    );
    // Don't allow() here — main() will still complete and emit allow normally.
    // Explicit allow() here would emit duplicate JSON to stdout.
  });

  main().catch((err) => {
    const message = err instanceof Error ? err.message : String(err);
    process.stderr.write(
      `${ORCHESTRATOR_DIAGNOSTIC_LOG_PREFIX} fatal: ${message}\n`,
    );
    trackHookError("pretooluse-edit-time-orchestrator", message);
    allow(); // Fail-open at the outermost layer
  });
}
