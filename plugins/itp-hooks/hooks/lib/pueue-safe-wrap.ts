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
 *   1. The command reaches pueue as ONE single-quoted argument. pueue joins its arguments with
 *      spaces and runs the result with `sh -c` (its default `shell_command`), so one argument is
 *      the original text, byte for byte.
 *   2. Nothing is emitted unless it parses: the original under every shell that will run the
 *      wrapper (bash and the user's $SHELL) and under `sh` (pueue's shell), and the wrapper under
 *      the same user shells. A failed check means "do not rewrite", never "rewrite anyway".
 */

import { basename } from "node:path";

const SYNTAX_CHECK_TIMEOUT_MS = 1500;

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

/**
 * True when `shell -n -c script` accepts the script, and also when the shell is not installed (a
 * shell that is not there will not be the one parsing it). False on a syntax error or a timeout.
 */
export function parsesUnder(shell: string, script: string): boolean {
  const path = Bun.which(shell);
  if (path === null) return true;
  try {
    const result = Bun.spawnSync([path, "-n", "-c", script], {
      stdin: "ignore",
      stdout: "ignore",
      stderr: "ignore",
      timeout: SYNTAX_CHECK_TIMEOUT_MS,
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
 * The original must parse first: if the agent's own command is already a syntax error, wrapping
 * it would only move the error somewhere less recognisable, so it is passed through untouched and
 * fails in the agent's own terms.
 */
export function wrapIsSafe(original: string, wrapped: string, shells: readonly string[] = userShells()): SafeWrapVerdict {
  for (const shell of shells) {
    if (!parsesUnder(shell, original)) return { ok: false, reason: `original does not parse under ${shell}` };
  }
  if (!parsesUnder("sh", original)) return { ok: false, reason: "original does not parse under sh (pueue's shell)" };
  for (const shell of shells) {
    if (!parsesUnder(shell, wrapped)) return { ok: false, reason: `wrapper does not parse under ${shell}` };
  }
  return { ok: true, reason: "" };
}

/**
 * Reads the task's own exit status back out of `pueue status --json`.
 *
 * MEASURED 2026-10-17 on pueue 4.0.4: `pueue wait <id>` exits 0 when the task FAILED (a task ending
 * `exit 3` returned 0 from wait), so both earlier wrappers reported success for every failed job,
 * and `pueue wait … && pueue log …` also hid the log of exactly the runs that needed reading. The
 * status JSON carries `"result":"Success"` or `{"Failed":N}`; anything else (killed, unreadable)
 * reads as 1, because an unknown outcome must not look like success. bun is present wherever these
 * hooks run, and the snippet has no single quote, so it nests inside the wrapper's quoting.
 */
const TASK_EXIT_CODE_SNIPPET =
  'const s=JSON.parse(await Bun.stdin.text());const r=s.tasks?.[process.env.TASK_ID]?.status?.Done?.result;' +
  'console.log(r==="Success"?0:(r&&typeof r==="object"&&typeof r.Failed==="number")?r.Failed:1)';

export interface PueueWrapperOptions {
  readonly command: string;
  readonly cwd: string;
  /** Appended with the task id, for the Stop hook's session-scoped cleanup. Omit to skip. */
  readonly taskLog?: string;
  /** What to do when pueue does not return a task id. */
  readonly onQueueFailure: "run-directly" | "fail";
  readonly label: string;
}

/**
 * queue → wait → full log → the task's own exit status. Multi-line on purpose: a trailing
 * `# comment` in the command can then never swallow the wrapper's `fi` (it sits inside the quoted
 * argument anyway, but the fallback `eval` line is kept on its own line for the same reason).
 */
export function buildPueueWrapper(options: PueueWrapperOptions): string {
  const quoted = shellSingleQuote(options.command);
  const tag = `[${options.label}]`;
  const onFailure =
    options.onQueueFailure === "run-directly"
      ? [`  echo >&2 ${shellSingleQuote(`${tag} pueue did not queue the command; running it directly`)}`, `  eval ${quoted}`]
      : [`  echo >&2 ${shellSingleQuote(`${tag} pueue did not queue the command; check \`pueue status\``)}`, "  false"];
  return [
    `TASK_ID=$(pueue add --print-task-id -w ${shellSingleQuote(options.cwd)} -- ${quoted} 2>&1 | grep -oE '^[0-9]+$' | tail -1)`,
    'if [ -z "$TASK_ID" ]; then',
    ...onFailure,
    "else",
    ...(options.taskLog === undefined ? [] : [`  echo "$TASK_ID" >> ${shellSingleQuote(options.taskLog)}`]),
    `  echo >&2 ${shellSingleQuote(`${tag} queued as pueue task`)} "$TASK_ID"`,
    '  pueue wait "$TASK_ID" --quiet',
    '  pueue log "$TASK_ID" --full',
    `  TASK_RC=$(pueue status --json 2>/dev/null | TASK_ID="$TASK_ID" bun -e ${shellSingleQuote(TASK_EXIT_CODE_SNIPPET)} 2>/dev/null)`,
    '  (exit "${TASK_RC:-1}")',
    "fi",
  ].join("\n");
}
