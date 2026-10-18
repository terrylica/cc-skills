/**
 * Building a `pueue add` wrapper around a Bash command WITHOUT breaking it.
 *
 * WHY THIS EXISTS (2026-10-17). Both rewriting guards built their wrapper by pasting the command
 * after `pueue add ... --` with no quoting around it:
 *
 *   TASK_ID=$(pueue add --print-task-id -w '/dir' -- for f in a b; do python x.py "$f"; done ...)
 *
 * The outer shell then parsed the command's own `;`, `do`, `&&`, `|` and quotes as part of the
 * wrapper. Every compound command came out as a parse error ("parse error near `TASK_ID=$(pueue
 * add`", "unmatched '"), and the pueue-wrap guard additionally escaped single quotes as `'\''`
 * without the enclosing quotes that escape belongs inside. A rewrite that cannot run is worse than
 * no rewrite: the agent loses the command it wrote and gets an error that is not its own.
 *
 * The rules here:
 *   1. The task runs as `<shell> -c '<command>'`, where <shell> is the shell the Bash tool would
 *      have used (the user's bash or zsh, else bash). pueue's own `sh -c` (dash on Linux) would
 *      run the command under a different shell than it was written for, and `dash -n` accepts
 *      bashisms (`${arr[@]}`, `${x//a/b}`) that fail when dash runs them (found in review).
 *   2. Nothing is emitted unless it parses: the original under the task shell, and the wrapper
 *      under bash and the user's $SHELL. A failed or timed-out check means "do not rewrite".
 *   3. The wrapper ends with the TASK's exit code (see TASK_EXIT_CODE_SNIPPET).
 */

import { basename } from "node:path";

/** Per check. Normal checks take a few ms; this bounds a pathological one. */
const SYNTAX_CHECK_TIMEOUT_MS = 800;
/** All checks together, well inside the hook's 5 s timeout (past it the command runs unmodified). */
export const SYNTAX_CHECK_BUDGET_MS = 2500;

/** `'…'` with every `'` closed, escaped and reopened. Safe for any byte string. */
export function shellSingleQuote(text: string): string {
  return `'${text.replace(/'/g, `'\\''`)}'`;
}

/**
 * The shells that will parse the wrapper: bash, plus the user's login shell when it is another
 * Bourne-family shell (zsh on macOS and on el02). Claude Code's Bash tool runs commands in the
 * user's shell, so a wrapper that bash accepts but zsh rejects is still a broken wrapper.
 */
export function userShells(): string[] {
  const shells = ["bash"];
  const login = basename(process.env.SHELL ?? "");
  if (["zsh", "bash", "dash", "ksh", "sh"].includes(login) && !shells.includes(login)) shells.push(login);
  return shells;
}

/** The shell the task runs under: the user's bash or zsh when installed, else bash. */
export function taskShell(): string {
  const login = basename(process.env.SHELL ?? "");
  if ((login === "zsh" || login === "bash") && Bun.which(login) !== null) return login;
  return "bash";
}

/**
 * True when `shell -n -c script` accepts the script, and also when the shell is not installed (a
 * shell that is not there will not be the one parsing it). False on a syntax error or a timeout.
 */
export function parsesUnder(shell: string, script: string, timeoutMs: number = SYNTAX_CHECK_TIMEOUT_MS): boolean {
  const path = Bun.which(shell);
  if (path === null) return true;
  if (timeoutMs <= 0) return false;
  try {
    const result = Bun.spawnSync([path, "-n", "-c", script], {
      stdin: "ignore",
      stdout: "ignore",
      stderr: "ignore",
      timeout: timeoutMs,
    });
    return result.exitCode === 0;
  } catch {
    return false;
  }
}

export interface SafeWrapVerdict {
  readonly ok: boolean;
  /** Which check failed, for the hook's stderr log. */
  readonly reason: string;
}

/**
 * Whether `wrapped` may replace `original`.
 *
 * The original must parse first, under the shell that will run it: if the agent's own command is
 * already a syntax error, wrapping it would only move the error somewhere less recognisable, so it
 * is passed through untouched and fails in the agent's own terms.
 */
export function wrapIsSafe(
  original: string,
  wrapped: string,
  shells: readonly string[] = userShells(),
  runShell: string = taskShell(),
  budgetMs: number = SYNTAX_CHECK_BUDGET_MS,
): SafeWrapVerdict {
  const deadline = Date.now() + budgetMs;
  const remaining = () => Math.min(SYNTAX_CHECK_TIMEOUT_MS, deadline - Date.now());
  if (!parsesUnder(runShell, original, remaining())) {
    return { ok: false, reason: `original does not parse under ${runShell} (or the check timed out)` };
  }
  for (const shell of shells) {
    if (!parsesUnder(shell, wrapped, remaining())) {
      return { ok: false, reason: `wrapper does not parse under ${shell} (or the check timed out)` };
    }
  }
  return { ok: true, reason: "" };
}

/**
 * Reads the task's own exit status back out of `pueue status --json`.
 *
 * MEASURED 2026-10-17 on pueue 4.0.4: `pueue wait <id>` exits 0 when the task FAILED (a task ending
 * `exit 3` returned 0 from wait), so both earlier wrappers reported success for every failed job,
 * and `pueue wait … && pueue log …` also hid the log of exactly the runs that needed reading. pueue
 * 4 writes `"Done":{"result":"Success"|{"Failed":N}}`; older releases put the result directly under
 * `"Done"`, and both are read. Anything else (killed, unreadable) is 1, because an unknown outcome
 * must not look like success. It runs with the hook's own bun (`process.execPath`), so it does not
 * depend on bun being on the PATH of the shell that runs the wrapper. No single quote inside, so it
 * nests in the wrapper's quoting.
 */
const TASK_EXIT_CODE_SNIPPET =
  'const s=JSON.parse(await Bun.stdin.text());const d=s.tasks?.[process.env.TASK_ID]?.status?.Done;' +
  'const r=(d&&typeof d==="object"&&"result" in d)?d.result:d;' +
  'console.log(r==="Success"?0:(r&&typeof r==="object"&&typeof r.Failed==="number")?r.Failed:1)';

export interface PueueWrapperOptions {
  readonly command: string;
  readonly cwd: string;
  /** Appended with the task id, for the Stop hook's session-scoped cleanup. Omit to skip. */
  readonly taskLog?: string;
  /** What to do when pueue does not return a task id. */
  readonly onQueueFailure: "run-directly" | "fail";
  readonly label: string;
  /** The shell the task runs under; defaults to {@link taskShell}. */
  readonly shell?: string;
}

/**
 * queue → wait → full log → the task's own exit status. Multi-line on purpose: a trailing
 * `# comment` in the command can then never swallow the wrapper's `fi` (it sits inside the quoted
 * argument anyway, but the fallback `eval` line is kept on its own line for the same reason).
 */
export function buildPueueWrapper(options: PueueWrapperOptions): string {
  const shell = options.shell ?? taskShell();
  const task = `${shell} -c ${shellSingleQuote(options.command)}`;
  const quotedTask = shellSingleQuote(task);
  const quotedCommand = shellSingleQuote(options.command);
  const tag = `[${options.label}]`;
  const onFailure =
    options.onQueueFailure === "run-directly"
      ? [`  echo >&2 ${shellSingleQuote(`${tag} pueue did not queue the command; running it directly`)}`, `  eval ${quotedCommand}`]
      : [`  echo >&2 ${shellSingleQuote(`${tag} pueue did not queue the command; check \`pueue status\``)}`, "  false"];
  return [
    `TASK_ID=$(pueue add --print-task-id -w ${shellSingleQuote(options.cwd)} -- ${quotedTask} 2>&1 | grep -oE '^[0-9]+$' | tail -1)`,
    'if [ -z "$TASK_ID" ]; then',
    ...onFailure,
    "else",
    ...(options.taskLog === undefined ? [] : [`  echo "$TASK_ID" >> ${shellSingleQuote(options.taskLog)}`]),
    `  echo >&2 ${shellSingleQuote(`${tag} queued as pueue task`)} "$TASK_ID"`,
    '  pueue wait "$TASK_ID" --quiet',
    '  pueue log "$TASK_ID" --full',
    `  TASK_RC=$(pueue status --json 2>/dev/null | TASK_ID="$TASK_ID" ${shellSingleQuote(process.execPath)} -e ${shellSingleQuote(TASK_EXIT_CODE_SNIPPET)} 2>/dev/null)`,
    '  (exit "${TASK_RC:-1}")',
    "fi",
  ].join("\n");
}
