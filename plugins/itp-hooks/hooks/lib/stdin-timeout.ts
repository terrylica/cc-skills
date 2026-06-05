/**
 * Shared stdin-read timeout guard for itp-hooks.
 *
 * Root cause this fixes: `await Bun.stdin.text()` (and `Bun.stdin.stream()`)
 * block FOREVER when the parent never closes stdin's write end. Observed under
 * heavy container load — a full fan-out of PreToolUse guards stuck in `Sl` sleep
 * for ~59min, each leaking ~31MB → memory pressure → fresh bun spawns SIGTRAP
 * (core dump). Bounding the read with a hard deadline lets the hook fail open
 * (hooks are advisory; a missed read must never hang the tool call).
 *
 * Tune via env: ITP_HOOK_STDIN_TIMEOUT_MS (default 2000).
 */

export const STDIN_READ_TIMEOUT_MS =
  Number(process.env.ITP_HOOK_STDIN_TIMEOUT_MS) || 2000;

/**
 * One-shot stdin read bounded by a deadline. Resolves with the full stdin text,
 * or rejects with a timeout Error if EOF never arrives. Callers decide fail-open
 * behaviour (allow / silent-exit) in their catch block.
 */
export async function readStdinTextWithTimeout(
  timeoutMs: number = STDIN_READ_TIMEOUT_MS,
): Promise<string> {
  return Promise.race([
    Bun.stdin.text(),
    new Promise<never>((_resolve, reject) =>
      setTimeout(
        () => reject(new Error(`stdin read timed out after ${timeoutMs}ms`)),
        timeoutMs,
      ).unref?.(),
    ),
  ]);
}
