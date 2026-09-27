/**
 * pkill / pgrep option-after-pattern detector — pure, dependency-free.
 *
 * THE HAZARD. macOS (and every BSD) `pkill` and `pgrep` read their options with BSD getopt, which
 * STOPS at the first non-option argument. Every argument after the first pattern is therefore
 * another PATTERN, even when it looks like a flag. So
 *
 *     pkill -f 'bun server.ts --build build-preview' -n
 *
 * does not mean "newest match only". It means "signal every process whose command line matches
 * `bun server.ts --build build-preview` OR contains `-n`" — and with `-f` the command line is the
 * whole argv, so `--no-sandbox`, `--no-rate-limit`, `--no-chrome` and `--num-raster-threads` all
 * match. Linux procps permutes arguments, so the same line happens to work there, which is why it
 * reads as correct.
 *
 * Measured 2026-09-27 on the operator's Mac: exactly that line SIGTERMed eight Claude Code sessions,
 * every Electron app's crash reporter (each app then crash-looped its respawned reporter through
 * "<App> quit unexpectedly" dialogs), an agent Chrome and Orca's terminals. `pgrep -f <nonsense> -n`
 * matched 64 live processes; with `-n` moved first it matched 0.
 *
 * WHAT THIS MODULE DOES. Through shell-command-invocation-walker.ts it statically lexes a shell command (never executes or expands it), finds
 * every `pkill`/`pgrep` invocation, and reports one whose arguments contain an option-looking token
 * after the first pattern. It looks through the wrappers an agent actually writes: `sudo`, `env`,
 * `nice`, `timeout`, `nohup`, `command`, `exec`, `time`, `caffeinate`, `xargs`, command substitution
 * (`kill $(pgrep -f x -n)`), `bash|sh|zsh -c '…'`, `ssh host '…'`, `pueue add -- …`, and heredoc
 * bodies fed to a shell (`bash <<'EOF'`).
 *
 * WHAT IT DELIBERATELY DOES NOT FLAG, because a noisy guard gets disabled and a disabled guard is
 * worse than none:
 *   - text that merely MENTIONS such a command: quoted arguments (`git commit -m "pkill -f x -n"`),
 *     comments, and heredoc bodies fed to anything other than a shell (`cat`, `python3 -`, `git
 *     commit -F -`);
 *   - a pattern after `--`, which is how a pattern that really begins with "-" is written;
 *   - redirections after the pattern (`2>/dev/null`, `>&2`), which are not arguments;
 *   - `-n` and friends that belong to a DIFFERENT command in the same line (`pgrep x | head -n 1`).
 */

import {
  type InvocationContext,
  walkShellInvocations,
  type Word,
} from "./shell-command-invocation-walker.ts";

export type { InvocationContext } from "./shell-command-invocation-walker.ts";

export type ProcessMatcherProgram = "pkill" | "pgrep";

export interface OptionAfterPatternFinding {
  readonly program: ProcessMatcherProgram;
  readonly context: InvocationContext;
  /** The invocation as written (raw source text of each word), program first. */
  readonly invocationAsWritten: string;
  /** The first pattern: where BSD getopt stopped reading options. */
  readonly firstPattern: string;
  /** Every argument after the first pattern that begins with "-" — each is really a pattern. */
  readonly optionLikeArgumentsAfterPattern: readonly string[];
  /** The same invocation with signal first, options next, patterns last. */
  readonly correctedInvocation: string;
}

/** BSD + procps short options of pgrep/pkill that take a value. */
const SHORT_OPTIONS_TAKING_A_VALUE = new Set([
  "F", "G", "M", "N", "O", "P", "U", "c", "d", "g", "r", "s", "t", "u",
]);

/** procps long options that take a value in the next word when not written `--name=value`. */
const LONG_OPTIONS_TAKING_A_VALUE = new Set([
  "signal", "delimiter", "parent", "pgroup", "session", "terminal", "euid", "uid", "group",
  "pidfile", "ns", "nslist", "runstates", "cgroup", "env", "older",
]);

const SIGNAL_NAMES = new Set([
  "HUP", "INT", "QUIT", "ILL", "TRAP", "ABRT", "IOT", "EMT", "FPE", "KILL", "BUS", "SEGV", "SYS",
  "PIPE", "ALRM", "TERM", "URG", "STOP", "TSTP", "CONT", "CHLD", "TTIN", "TTOU", "IO", "XCPU",
  "XFSZ", "VTALRM", "PROF", "WINCH", "INFO", "USR1", "USR2",
]);

/** `-9`, `-KILL`, `-SIGTERM`: the one position (argv[1]) where BSD pkill reads a signal. */
export function isSignalArgument(word: string): boolean {
  if (!word.startsWith("-") || word.length < 2) return false;
  const body = word.slice(1);
  if (/^\d+$/.test(body)) return true;
  const name = body.toUpperCase().replace(/^SIG/, "");
  return SIGNAL_NAMES.has(name);
}

/** How many words an option token consumes (1, or 2 when its value is the next word). */
export function optionWordSpan(token: string, hasNext: boolean): number {
  if (!hasNext) return 1;
  if (token.startsWith("--")) {
    const name = token.slice(2);
    return !name.includes("=") && LONG_OPTIONS_TAKING_A_VALUE.has(name) ? 2 : 1;
  }
  const letters = token.slice(1);
  for (let k = 0; k < letters.length; k++) {
    if (SHORT_OPTIONS_TAKING_A_VALUE.has(letters[k])) {
      return k === letters.length - 1 ? 2 : 1;
    }
  }
  return 1;
}

function checkProcessMatcher(
  program: ProcessMatcherProgram,
  argumentsAfterProgram: Word[],
  programWord: Word,
  context: InvocationContext,
): OptionAfterPatternFinding | null {
  const args = argumentsAfterProgram;
  const leading: Word[] = [];
  const signals: Word[] = [];
  let idx = 0;

  if (program === "pkill" && idx < args.length && isSignalArgument(args[idx].value)) {
    signals.push(args[idx]);
    idx++;
  }
  while (idx < args.length) {
    const t = args[idx].value;
    if (t === "--") return null; // everything after `--` is a pattern by the author's explicit choice
    if (t.length > 1 && t.startsWith("-")) {
      const span = optionWordSpan(t, idx + 1 < args.length);
      for (let s = 0; s < span; s++) leading.push(args[idx + s]);
      idx += span;
      continue;
    }
    break;
  }

  const rest = args.slice(idx);
  if (rest.length < 2) return null;

  const stray: string[] = [];
  const moved: Word[] = [];
  const patterns: Word[] = [rest[0]];
  for (let r = 1; r < rest.length; r++) {
    const t = rest[r].value;
    if (!t.startsWith("-")) {
      patterns.push(rest[r]);
      continue;
    }
    stray.push(t);
    if (t === "-" || t === "--") continue; // dropped from the suggestion: meant as end-of-options
    if (program === "pkill" && isSignalArgument(t) && !/^-[A-Za-z]$/.test(t)) {
      signals.push(rest[r]);
      continue;
    }
    const span = optionWordSpan(t, r + 1 < rest.length);
    for (let s = 0; s < span; s++) moved.push(rest[r + s]);
    r += span - 1;
  }
  if (stray.length === 0) return null;

  // Raw source text is reused verbatim, so quoting and `$$`-style expansion stay exactly as written.
  // BSD pkill reads a signal only as the very first argument, hence at most one, placed first.
  const corrected = [programWord, ...signals.slice(0, 1), ...leading, ...moved, ...patterns];
  return {
    program,
    context,
    invocationAsWritten: [programWord, ...args].map((w) => w.raw).join(" "),
    firstPattern: rest[0].value,
    optionLikeArgumentsAfterPattern: stray,
    correctedInvocation: corrected.map((w) => w.raw).join(" "),
  };
}

/**
 * Every pkill/pgrep invocation in `command` that carries an option-looking argument after its first
 * pattern. Empty when there is none. Never throws on malformed input (unterminated quotes and
 * substitutions are closed at end of input).
 */
export function findPkillOptionAfterPattern(command: string): OptionAfterPatternFinding[] {
  const findings: OptionAfterPatternFinding[] = [];
  walkShellInvocations(command, /\bp(?:kill|grep)\b/, ({ program, programWord, args, context }) => {
    if (program !== "pkill" && program !== "pgrep") return;
    const finding = checkProcessMatcher(program, args, programWord, context);
    if (finding) findings.push(finding);
  });
  return findings;
}
