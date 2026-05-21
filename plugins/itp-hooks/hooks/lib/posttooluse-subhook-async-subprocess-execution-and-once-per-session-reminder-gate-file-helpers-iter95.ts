/**
 * Iter-95 shared helpers for PostToolUse orchestrator-imported subhooks.
 *
 * Why this module exists (DRY motivation):
 *
 *   Iter-93 and iter-94 each defined their own copy of:
 *     - `drainBunSubprocessStreamToUtf8Text`
 *     - `executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndStreamDrain`
 *     - `tryAtomicallyClaim<X>InstallReminderOncePerSessionGateFile`
 *
 *   With iter-95 inlining oxlint + biome (3rd + 4th subhooks), there would
 *   be FOUR verbatim copies of these helpers. Drift between copies would
 *   undermine the iter-94 async-Bun.spawn invariant. Iter-95 hoists them
 *   into this lib module so:
 *
 *     1. Every subhook calls the SAME `executeBunSubprocessAsync...` (no
 *        spawnSync regression possible — there's only one place to change)
 *     2. Every subhook surfaces install-reminder ONCE-PER-SESSION via the
 *        SAME atomic O_EXCL gate-file pattern (consistent operator UX)
 *     3. The iter-94 static audit's job stays scoped: it only needs to
 *        check that the lib helper itself uses Bun.spawn (which it does);
 *        it doesn't have to chase down N classifier copies
 *
 *   Iter-95 also adds a `maxBuffer` safety net (8MB default) per Bun
 *   official docs guidance — bounds runaway subprocess output to prevent
 *   OOM if a misconfigured linter spits out hundreds of MB of diagnostics.
 *
 * Naming convention reminder: every helper name MUST encode the algorithm
 * AND the contract it enforces, not just describe what it does in
 * generic terms. The dual-export naming-drift pattern from iter-89/90/91/93/94
 * applies here too — these names are deliberately long.
 */

import { mkdirSync, openSync, closeSync, constants } from "node:fs";
import { join } from "node:path";

// ══════════════════════════════════════════════════════════════════════════
//  Constants
// ══════════════════════════════════════════════════════════════════════════

/**
 * Default maxBuffer (per Bun docs guidance — bounds runaway subprocess
 * output to prevent OOM). 256 KiB right-sized for type-checker/linter
 * output (iter-96 audit: 8 MiB Node-parity default was overkill; real-world
 * type-checker output is ≤50 KB typical, ≤200 KB even for pathological
 * cases like 1000-error projects). Tightening to 256 KiB surfaces
 * unexpected output growth (e.g., a misconfigured linter spamming
 * stack-traces) earlier as a hook diagnostic rather than silently
 * consuming orchestrator memory. Subhooks needing different bounds can
 * override via the optional `maxBufferBytes` option.
 */
export const DEFAULT_SUBPROCESS_OUTPUT_MAX_BUFFER_BYTES_PER_BUN_DOCS_SAFETY_NET = 256 * 1024;

// ══════════════════════════════════════════════════════════════════════════
//  Async stream drain (consume Bun ReadableStream to UTF-8 string)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Async drain of a Bun ReadableStream into a UTF-8 string. The
 * orchestrator-imported path must NEVER block on subprocess I/O, so we use
 * `Response(stream).text()` which is the idiomatic 2026 Bun pattern for
 * fully consuming a process stream without manual loop bookkeeping.
 * Mirrors the Bun docs example for `Bun.spawn` stdout reading.
 *
 * Returns "" if the stream is undefined (e.g., spawn-failed-to-start
 * case where there are no stdio handles) or if the drain throws.
 */
export async function drainBunSubprocessReadableStreamToUtf8TextSwallowingErrors(
  stream: ReadableStream<Uint8Array> | undefined,
): Promise<string> {
  if (!stream) return "";
  try {
    return await new Response(stream).text();
  } catch {
    return "";
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Async subprocess execution with cooperative timeout + crash isolation
// ══════════════════════════════════════════════════════════════════════════

export interface AsyncSubprocessExecutionResult {
  exitCode: number | null;
  stdoutText: string;
  stderrText: string;
  /**
   * `true` when posix_spawn() returned ENOENT (binary not in PATH). The
   * caller typically surfaces an install reminder once per session in
   * this case.
   */
  spawnFailed: boolean;
  /**
   * `true` when the AbortSignal aborted the subprocess (timeout fired).
   * The caller typically falls back to a `noop` decision so the
   * orchestrator's wall-clock doesn't get held hostage by a runaway tool.
   */
  timedOut: boolean;
}

export interface AsyncSubprocessExecutionOptions {
  /** Working directory for the subprocess. */
  cwd?: string;
  /** Hard wall-clock deadline in milliseconds (AbortSignal.timeout-driven). */
  timeoutMs: number;
  /**
   * Maximum bytes of stdout+stderr the subprocess may emit before being
   * killed. Defaults to 8MiB per Bun docs guidance. Bounds runaway output.
   */
  maxBufferBytes?: number;
}

/**
 * Spawn a subprocess asynchronously with AbortSignal-driven cooperative
 * cancellation and a maxBuffer-bounded output guardrail. Returns ONE
 * structured result object capturing the four possible outcomes (clean
 * exit, non-zero exit, spawn-failed-to-start, timed-out). Never throws —
 * every error path collapses to a flagged result.
 *
 * Iter-95 hoist from ty/tsgo classifiers — every PostToolUse type-checker
 * + linter classifier shares this exact spawn pattern (run external
 * binary, capture stdout/stderr, respect orchestrator timeout, fail-open
 * on every error). Centralizing prevents drift between sibling subhooks.
 *
 * Why we drain stdout+stderr CONCURRENTLY with `.exited`: if a subprocess
 * blocks on a full stdout pipe (it produces more output than the pipe
 * buffer can hold and nobody reads it), `.exited` never resolves and we
 * deadlock. Reading the streams concurrently keeps the pipe drained as
 * the subprocess writes.
 *
 * Iter-95 enhancement: `maxBufferBytes` (default 8MiB per Bun docs) is
 * passed to `Bun.spawn` so a runaway linter producing hundreds of MB of
 * diagnostics is killed before exhausting orchestrator memory.
 */
export async function executeBunSubprocessAsyncWithAbortSignalCooperativeTimeoutAndConcurrentStreamDrainAndMaxBufferGuardrail(
  argv: readonly string[],
  options: AsyncSubprocessExecutionOptions,
): Promise<AsyncSubprocessExecutionResult> {
  const abortSignal = AbortSignal.timeout(options.timeoutMs);
  const maxBufferBytes =
    options.maxBufferBytes ?? DEFAULT_SUBPROCESS_OUTPUT_MAX_BUFFER_BYTES_PER_BUN_DOCS_SAFETY_NET;
  try {
    const subprocess = Bun.spawn(argv, {
      cwd: options.cwd,
      stdout: "pipe",
      stderr: "pipe",
      signal: abortSignal,
      // Bun docs: "The maximum number of bytes the process may output. If
      // the process goes over this limit, it is killed with signal
      // killSignal (defaults to SIGTERM)." Iter-95 safety-net add.
      maxBuffer: maxBufferBytes,
    });

    const [stdoutText, stderrText] = await Promise.all([
      drainBunSubprocessReadableStreamToUtf8TextSwallowingErrors(
        subprocess.stdout as ReadableStream<Uint8Array> | undefined,
      ),
      drainBunSubprocessReadableStreamToUtf8TextSwallowingErrors(
        subprocess.stderr as ReadableStream<Uint8Array> | undefined,
      ),
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
    // Two failure modes collapse here:
    //   1. Binary not in PATH — Bun.spawn throws on posix_spawn ENOENT
    //   2. AbortSignal.timeout() fired — subprocess was killed mid-execution
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

// ══════════════════════════════════════════════════════════════════════════
//  Atomic once-per-session install-reminder gate file
// ══════════════════════════════════════════════════════════════════════════

/**
 * Atomically create the install-reminder gate file. Returns `true` if THIS
 * call won the create race (we should surface the reminder), `false`
 * if the reminder was already surfaced this session OR the filesystem
 * operation failed.
 *
 * Race-safe because `O_CREAT | O_EXCL` is atomic at the POSIX layer — if
 * multiple PostToolUse subhooks all detect missing-binary at once (e.g.,
 * ty + tsgo + oxlint + biome all uninstalled when the orchestrator fires
 * on a .ts file), each calls this with their own `toolName` so each gets
 * an independent once-per-session reminder. Within a single tool, only
 * ONE classifier-invocation wins the race; the losers see EEXIST and
 * treat as "already reminded".
 *
 * @param toolName e.g. "ty", "tsgo", "oxlint", "biome" — used as the
 *                 unique-per-tool gate-file prefix
 * @param sessionId Claude session ID (or "unknown" if absent)
 */
export function tryAtomicallyClaimOncePerSessionInstallReminderGateFileForToolByName(
  toolName: string,
  sessionId: string,
): boolean {
  const gateDirectory = `/tmp/.claude-${toolName}-install-reminder`;
  try {
    mkdirSync(gateDirectory, { recursive: true });
  } catch {
    return false;
  }
  const gateFile = join(gateDirectory, `${sessionId}-${toolName}-install.reminded`);
  try {
    const fd = openSync(gateFile, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL);
    closeSync(fd);
    return true;
  } catch {
    return false; // Lost the race or filesystem error; either way, no reminder
  }
}

// ══════════════════════════════════════════════════════════════════════════
//  Atomic once-per-session GENERIC reminder gate file (iter-98 hoist)
// ══════════════════════════════════════════════════════════════════════════

/**
 * Atomically create a once-per-session GENERIC reminder gate file
 * (non-install-reminder — for "principle" / "practice" / "convention"
 * reminders fired once per Claude session). Returns `true` if THIS call
 * won the create race (we should surface the reminder), `false` if the
 * reminder was already surfaced this session OR the filesystem operation
 * failed.
 *
 * Distinct from the iter-95 install-reminder helper because the gate-file
 * namespace differs:
 *
 *   - INSTALL reminder:  /tmp/.claude-${tool}-install-reminder/${sid}-${tool}-install.reminded
 *   - GENERIC reminder:  /tmp/.claude-${reminder}-reminder/${sid}.reminded
 *
 * The install-reminder shape is preserved verbatim for backward-compat with
 * existing ty/tsgo/oxlint/biome classifiers (and their forensic gate-file
 * paths). The generic shape is what ssot-principles + memory-efficiency-
 * reminder + any future "once per session, fire a static reminder" classifier
 * needs.
 *
 * Iter-98 motivation: ssot-principles (iter-97) carried this gate logic
 * inlined in its classifier file as a per-classifier helper, with a TODO
 * comment noting "hoist when iter-98 inlines memory-efficiency-reminder".
 * Iter-98 cashes that TODO in — both classifiers now call the same
 * implementation, ensuring the atomic invariant (mkdirSync + O_EXCL openSync)
 * never drifts between sibling reminder-style subhooks.
 *
 * @param reminderName e.g. "ssot-principles", "memory-efficiency",
 *                     "rust-sota" — used as the unique gate-dir namespace
 *                     suffix. Must be a stable string per reminder; renaming
 *                     this string will silently re-fire the reminder for
 *                     existing sessions because the gate file lives at a
 *                     new path.
 * @param sessionId Claude session ID (or "unknown" if absent)
 */
export function tryAtomicallyClaimOncePerSessionGenericReminderGateFileForReminderByName(
  reminderName: string,
  sessionId: string,
): boolean {
  const gateDirectory = `/tmp/.claude-${reminderName}-reminder`;
  try {
    mkdirSync(gateDirectory, { recursive: true });
  } catch {
    return false;
  }
  const gateFile = join(gateDirectory, `${sessionId}.reminded`);
  try {
    const fd = openSync(gateFile, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL);
    closeSync(fd);
    return true;
  } catch {
    return false; // Lost the race or filesystem error; either way, no reminder
  }
}
