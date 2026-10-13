/**
 * Pueue wrap transport: turn a Bash tool command into a synchronous pueue job
 * WITHOUT ever passing the command text through a shell quoting layer.
 *
 * Why this file exists (the defect it replaces, 2026-10-12):
 *   The old wrapper spliced the command into `pueue add -- <command>` UNQUOTED,
 *   after escaping single quotes as '\'' (an escape that is only valid INSIDE a
 *   single-quoted string). Three failures followed, all from that one splice:
 *     1. any command containing ' failed to parse ("unmatched '") — 22 times in
 *        9 sessions between 2026-09-27 and 2026-10-12;
 *     2. any `;` or newline ended the `pueue add`, so pueue queued only the first
 *        statement and the rest ran inside `$(...)` with its output swallowed;
 *     3. the wrapper ended on `pueue log`, and `pueue wait` exits 0 even for a
 *        failed task, so every wrapped failure reported exit 0.
 *   Excluding SSH commands (47ee35da) treated one symptom of (1); it came back.
 *
 * The design, which removes the class rather than the instance:
 *   - The command is written verbatim to a 0600 spool file. Nothing escapes it.
 *   - Pueue queues `<shell> <spool-file>`. The only strings this module quotes
 *     are paths it generated itself plus the working directory, all through one
 *     correct POSIX single-quote function (shQuote).
 *   - The payload runs under the same shell the Bash tool uses ($SHELL, zsh or
 *     bash), not pueue's `sh -c`, so the command means what Claude wrote.
 *   - The queued job records its own exit status; the wrapper re-raises it.
 *   - The caller validates the result with `<shell> -n` before emitting it, so
 *     a wrapper that does not parse is never handed to the Bash tool.
 */

import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { randomUUID } from "node:crypto";

/** POSIX single-quoting: the ONLY quoting this transport ever applies. */
export function shQuote(s: string): string {
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

/** Paths this module generates must be boring; anything else falls back to /tmp. */
const SAFE_PATH = /^[A-Za-z0-9/._-]+$/;

/** The shell the Bash tool runs commands in: $SHELL when it is zsh or bash, else bash. */
export function payloadShell(env: NodeJS.ProcessEnv = process.env): string {
  const s = env.SHELL ?? "";
  return /\/(ba|z)sh$/.test(s) && existsSync(s) ? s : "/bin/bash";
}

export interface SpoolPaths {
  script: string;
  rc: string;
}

/** Write the command verbatim to a private spool file; return its paths. */
export function spoolCommand(command: string): SpoolPaths {
  const base = tmpdir().replace(/\/+$/, "");
  const dir = `${SAFE_PATH.test(base) ? base : "/tmp"}/claude-pueue-wrap`;
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  const stem = `${dir}/${randomUUID()}`;
  const paths = { script: `${stem}.sh`, rc: `${stem}.rc` };
  writeFileSync(paths.script, command.endsWith("\n") ? command : `${command}\n`, { mode: 0o600 });
  return paths;
}

export interface WrapOptions {
  shell: string;
  cwd: string;
  paths: SpoolPaths;
  /** File that collects this session's pueue task IDs (read by the Stop cleanup hook). */
  taskLog: string;
}

/**
 * The command pueue stores and runs (under its own `sh -c`): run the spooled
 * script with the Bash tool's shell, delete it, record the exit status.
 */
export function buildQueuedCommand(o: WrapOptions): string {
  const sh = shQuote(o.shell);
  const s = shQuote(o.paths.script);
  const r = shQuote(o.paths.rc);
  return `${sh} ${s}; __pw_rc=$?; rm -f ${s}; printf '%s\\n' "$__pw_rc" > ${r}; exit "$__pw_rc"`;
}

/**
 * The command handed back to the Bash tool: queue, wait, print the log, and
 * finish with the job's real exit status. Ends on `(exit N)` rather than
 * `exit N`, so the tool's own shell is left running.
 */
export function buildWrappedCommand(o: WrapOptions): string {
  const s = shQuote(o.paths.script);
  const r = shQuote(o.paths.rc);
  const queued = shQuote(buildQueuedCommand(o));
  return [
    `__pw_id=$(pueue add --print-task-id -w ${shQuote(o.cwd)} -- ${queued} 2>/dev/null | grep -E '^[0-9]+$' | tail -n 1)`,
    `if [ -z "$__pw_id" ]; then`,
    `  echo >&2 "[pueue-wrap] could not queue the command; running it directly"`,
    `  ${shQuote(o.shell)} ${s}; __pw_rc=$?; rm -f ${s}`,
    `else`,
    `  echo "$__pw_id" >> ${shQuote(o.taskLog)}`,
    `  pueue wait "$__pw_id" --quiet >/dev/null 2>&1`,
    `  pueue log "$__pw_id" --full 2>/dev/null`,
    `  __pw_rc=$(cat ${r} 2>/dev/null); rm -f ${r}`,
    `  if [ -z "$__pw_rc" ]; then echo >&2 "[pueue-wrap] pueue task $__pw_id ended without an exit status (killed or removed?)"; __pw_rc=1; fi`,
    `fi`,
    `(exit "$__pw_rc")`,
  ].join("\n");
}

/** `<shell> -n`: true when the text parses. Used on both the payload and the wrapper. */
export function parses(shell: string, args: string[]): boolean {
  return Bun.spawnSync([shell, "-n", ...args], { stdout: "ignore", stderr: "ignore" }).exitCode === 0;
}
