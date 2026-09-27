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
 * WHAT THIS MODULE DOES. It statically lexes a shell command (never executes or expands it), finds
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

export type ProcessMatcherProgram = "pkill" | "pgrep";

/** Where the offending invocation was found, for the deny message. */
export type InvocationContext =
  | "command"
  | "shell -c script"
  | "ssh remote command"
  | "pueue task"
  | "heredoc fed to a shell";

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

interface Word {
  /** Shell-decoded value (quotes removed; `$…` and `$(…)` NOT expanded). */
  readonly value: string;
  /** Exact source text of the word. */
  readonly raw: string;
}

interface HeredocBody {
  readonly commandWords: Word[];
  readonly body: string;
}

interface LexResult {
  readonly commands: Word[][];
  readonly heredocs: HeredocBody[];
}

type FrameKind = "top" | "substitution" | "backtick";

interface Frame {
  readonly kind: FrameKind;
  words: Word[];
  value: string | null;
  start: number;
  inDoubleQuotes: boolean;
  dropNextWord: boolean;
}

interface PendingHeredoc {
  readonly commandWords: Word[];
  readonly delimiter: string;
  readonly stripLeadingTabs: boolean;
}

const MAX_RECURSION_DEPTH = 4;

function newFrame(kind: FrameKind): Frame {
  return {
    kind,
    words: [],
    value: null,
    start: 0,
    inDoubleQuotes: false,
    dropNextWord: false,
  };
}

/**
 * Split a command string into simple commands (arrays of words). Handles single, double and
 * ANSI-C quotes, backslash escapes, comments, `;` `&` `|` `&&` `||` newlines and parentheses as
 * separators, `$(…)` / backticks / process substitution as nested commands, redirections (dropped,
 * together with their target), and heredocs (bodies collected separately, never lexed here).
 */
function lexShellCommands(src: string): LexResult {
  const commands: Word[][] = [];
  const heredocs: HeredocBody[] = [];
  const pending: PendingHeredoc[] = [];
  const stack: Frame[] = [newFrame("top")];
  const n = src.length;
  let i = 0;

  const top = (): Frame => stack[stack.length - 1];

  function append(text: string): void {
    const f = top();
    if (f.value === null) {
      f.value = "";
      f.start = i;
    }
    f.value += text;
  }

  function endWord(): void {
    const f = top();
    if (f.value === null) return;
    const word: Word = { value: f.value, raw: src.slice(f.start, i) };
    f.value = null;
    if (f.dropNextWord) {
      f.dropNextWord = false;
      return;
    }
    f.words.push(word);
  }

  function endCommand(): void {
    endWord();
    const f = top();
    f.dropNextWord = false;
    if (f.words.length > 0) commands.push(f.words);
    f.words = [];
  }

  function enterNested(kind: FrameKind): void {
    // The nested command contributes an opaque placeholder to the enclosing word.
    append(kind === "backtick" ? "`…`" : "$(…)");
    stack.push(newFrame(kind));
  }

  function exitNested(): void {
    endCommand();
    if (stack.length > 1) stack.pop();
  }

  function readHeredocDelimiter(): void {
    // Positioned just after `<<`.
    let stripLeadingTabs = false;
    if (src[i] === "-") {
      stripLeadingTabs = true;
      i++;
    }
    while (i < n && (src[i] === " " || src[i] === "\t")) i++;
    let delimiter = "";
    while (i < n && !/[\s;&|<>()]/.test(src[i])) {
      const c = src[i];
      if (c === "'" || c === '"') {
        const close = src.indexOf(c, i + 1);
        const end = close === -1 ? n : close;
        delimiter += src.slice(i + 1, end);
        i = end + 1;
      } else if (c === "\\" && i + 1 < n) {
        delimiter += src[i + 1];
        i += 2;
      } else {
        delimiter += c;
        i++;
      }
    }
    if (delimiter) {
      pending.push({ commandWords: top().words, delimiter, stripLeadingTabs });
    }
  }

  function consumeHeredocBodies(): void {
    // Positioned at the start of the line after the one that introduced the heredoc(s).
    while (pending.length > 0) {
      const h = pending.shift() as PendingHeredoc;
      const lines: string[] = [];
      let terminated = false;
      while (i < n) {
        const nl = src.indexOf("\n", i);
        const lineEnd = nl === -1 ? n : nl;
        const line = src.slice(i, lineEnd);
        i = nl === -1 ? n : nl + 1;
        const candidate = h.stripLeadingTabs ? line.replace(/^\t+/, "") : line;
        if (candidate === h.delimiter) {
          terminated = true;
          break;
        }
        lines.push(line);
      }
      heredocs.push({ commandWords: h.commandWords, body: lines.join("\n") });
      if (!terminated) break;
    }
  }

  function handleRedirection(): void {
    // Positioned at `<` or `>`. A pure-digit word just before it is an fd number, not an argument.
    const f = top();
    if (f.value !== null && /^\d+$/.test(f.value)) {
      f.value = null;
    } else {
      endWord();
    }
    const c = src[i];
    i++;
    if (src[i] === c || (c === "<" && src[i] === ">") || src[i] === "|") i++;
    if (src[i] === "&") {
      // `>&2`, `2>&1`, `<&-`: duplicating an fd has no filename word.
      i++;
      while (i < n && /[0-9-]/.test(src[i])) i++;
      return;
    }
    top().dropNextWord = true;
  }

  while (i < n) {
    const f = top();
    const c = src[i];

    if (f.inDoubleQuotes) {
      if (c === "\\") {
        const next = src[i + 1];
        if (next !== undefined && '$`"\\\n'.includes(next)) {
          if (next !== "\n") append(next);
          i += 2;
        } else {
          append("\\");
          i++;
        }
        continue;
      }
      if (c === '"') {
        f.inDoubleQuotes = false;
        i++;
        continue;
      }
      if (c === "$" && src[i + 1] === "(") {
        enterNested("substitution");
        i += 2;
        continue;
      }
      if (c === "`") {
        enterNested("backtick");
        i++;
        continue;
      }
      append(c);
      i++;
      continue;
    }

    if (c === "'") {
      const close = src.indexOf("'", i + 1);
      const end = close === -1 ? n : close;
      append(src.slice(i + 1, end));
      i = end + 1;
      continue;
    }
    if (c === "$" && src[i + 1] === "'") {
      let j = i + 2;
      let text = "";
      while (j < n && src[j] !== "'") {
        if (src[j] === "\\" && j + 1 < n) {
          text += src[j + 1];
          j += 2;
        } else {
          text += src[j];
          j++;
        }
      }
      append(text);
      i = j + 1;
      continue;
    }
    if (c === '"') {
      append("");
      f.inDoubleQuotes = true;
      i++;
      continue;
    }
    if (c === "\\") {
      const next = src[i + 1];
      if (next === "\n") {
        i += 2;
        continue;
      }
      if (next !== undefined) append(next);
      i += 2;
      continue;
    }
    if (c === "#" && f.value === null) {
      const nl = src.indexOf("\n", i);
      i = nl === -1 ? n : nl;
      continue;
    }
    if (c === "$" && src[i + 1] === "(") {
      enterNested("substitution");
      i += 2;
      continue;
    }
    if (c === "`") {
      if (f.kind === "backtick") {
        exitNested();
      } else {
        enterNested("backtick");
      }
      i++;
      continue;
    }
    if ((c === "<" || c === ">") && src[i + 1] === "(") {
      // Process substitution <(…) / >(…): a nested command.
      endWord();
      stack.push(newFrame("substitution"));
      i += 2;
      continue;
    }
    if (c === "<" && src[i + 1] === "<" && src[i + 2] !== "<") {
      endWord();
      i += 2;
      readHeredocDelimiter();
      continue;
    }
    if (c === "<" && src[i + 1] === "<" && src[i + 2] === "<") {
      // Here-string: its operand is stdin, not an argument.
      endWord();
      i += 3;
      top().dropNextWord = true;
      continue;
    }
    if (c === "<" || c === ">") {
      handleRedirection();
      continue;
    }
    if (c === "&" && src[i + 1] === ">") {
      endWord();
      i += 2;
      if (src[i] === ">") i++;
      top().dropNextWord = true;
      continue;
    }
    if (c === ")") {
      if (f.kind === "substitution") {
        exitNested();
      } else {
        endCommand();
      }
      i++;
      continue;
    }
    if (c === "(" || c === ";" || c === "&" || c === "|") {
      endCommand();
      i++;
      continue;
    }
    if (c === "\n") {
      endCommand();
      i++;
      if (pending.length > 0) consumeHeredocBodies();
      continue;
    }
    if (c === " " || c === "\t" || c === "\r") {
      endWord();
      i++;
      continue;
    }
    append(c);
    i++;
  }

  while (stack.length > 1) exitNested();
  endCommand();
  return { commands, heredocs };
}

const SHELL_INTERPRETERS = new Set(["bash", "sh", "zsh", "dash", "ksh"]);

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
function isSignalArgument(word: string): boolean {
  if (!word.startsWith("-") || word.length < 2) return false;
  const body = word.slice(1);
  if (/^\d+$/.test(body)) return true;
  const name = body.toUpperCase().replace(/^SIG/, "");
  return SIGNAL_NAMES.has(name);
}

function basename(word: string): string {
  const slash = word.lastIndexOf("/");
  return slash === -1 ? word : word.slice(slash + 1);
}

const isAssignment = (w: string): boolean => /^[A-Za-z_][A-Za-z0-9_]*=/.test(w);

/** How many words an option token consumes (1, or 2 when its value is the next word). */
function optionWordSpan(token: string, hasNext: boolean): number {
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

/** Index of the real program word after assignments and wrapper commands, or -1. */
function skipAssignmentsAndWrappers(words: Word[]): number {
  let k = 0;
  const len = words.length;
  const isOpt = (idx: number): boolean => idx < len && words[idx].value.startsWith("-");
  while (k < len && isAssignment(words[k].value)) k++;
  for (;;) {
    if (k >= len) return -1;
    const prog = basename(words[k].value);
    if (prog === "sudo") {
      k++;
      while (isOpt(k)) {
        const o = words[k].value;
        k++;
        if (/^-[ugpCDhrtTU]$/.test(o)) k++;
      }
      continue;
    }
    if (prog === "env") {
      k++;
      while (k < len && (isOpt(k) || isAssignment(words[k].value))) {
        const o = words[k].value;
        k++;
        if (o === "-u" || o === "-C" || o === "-P") k++;
      }
      continue;
    }
    if (prog === "nice") {
      k++;
      while (isOpt(k)) {
        const o = words[k].value;
        k++;
        if (o === "-n") k++;
      }
      continue;
    }
    if (prog === "timeout" || prog === "gtimeout") {
      k++;
      while (isOpt(k)) {
        const o = words[k].value;
        k++;
        if (o === "-s" || o === "-k" || o === "--signal" || o === "--kill-after") k++;
      }
      k++; // the duration
      continue;
    }
    if (prog === "xargs") {
      k++;
      while (isOpt(k)) {
        const o = words[k].value;
        k++;
        if (/^-[IJLnPRsES]$/.test(o)) k++;
      }
      continue;
    }
    if (prog === "caffeinate") {
      k++;
      while (isOpt(k)) {
        const o = words[k].value;
        k++;
        if (o === "-t" || o === "-w") k++;
      }
      continue;
    }
    if (["command", "exec", "nohup", "time", "builtin", "noglob"].includes(prog)) {
      k++;
      while (isOpt(k)) k++;
      continue;
    }
    return k;
  }
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

function analyze(
  src: string,
  context: InvocationContext,
  depth: number,
  findings: OptionAfterPatternFinding[],
): void {
  if (depth > MAX_RECURSION_DEPTH || !src) return;
  // Cheap pre-filter: nothing to do unless one of the two program names appears at all.
  if (!/\bp(?:kill|grep)\b/.test(src)) return;

  const { commands, heredocs } = lexShellCommands(src);

  for (const words of commands) {
    const k = skipAssignmentsAndWrappers(words);
    if (k === -1) continue;
    const prog = basename(words[k].value);
    const args = words.slice(k + 1);

    if (prog === "pkill" || prog === "pgrep") {
      const finding = checkProcessMatcher(prog, args, words[k], context);
      if (finding) findings.push(finding);
      continue;
    }

    if (SHELL_INTERPRETERS.has(prog)) {
      for (let a = 0; a < args.length; a++) {
        const t = args[a].value;
        if (/^-[A-Za-z]*c[A-Za-z]*$/.test(t)) {
          if (a + 1 < args.length) analyze(args[a + 1].value, "shell -c script", depth + 1, findings);
          break;
        }
        if (!t.startsWith("-") && !t.startsWith("+")) break; // a script file, not -c
      }
      continue;
    }

    if (prog === "ssh") {
      const withValue = new Set("BbcDEeFIiJLlmOoPpQRSWw".split(""));
      let a = 0;
      while (a < args.length && args[a].value.startsWith("-")) {
        const t = args[a].value;
        a++;
        if (t === "--") break;
        const letters = t.slice(1);
        for (let li = 0; li < letters.length; li++) {
          if (withValue.has(letters[li])) {
            if (li === letters.length - 1) a++;
            break;
          }
        }
      }
      a++; // the destination host
      const remote = args
        .slice(a)
        .map((w) => w.value)
        .join(" ");
      analyze(remote, "ssh remote command", depth + 1, findings);
      continue;
    }

    if (prog === "pueue" && args[0]?.value === "add") {
      let a = 1;
      while (a < args.length && args[a].value.startsWith("-") && args[a].value !== "--") {
        const t = args[a].value;
        a++;
        if (/^-[wdgalo]$/.test(t) || /^--(working-directory|delay|group|after|label|priority)$/.test(t)) a++;
      }
      if (args[a]?.value === "--") a++;
      const task = args
        .slice(a)
        .map((w) => w.value)
        .join(" ");
      analyze(task, "pueue task", depth + 1, findings);
    }
  }

  for (const h of heredocs) {
    const k = skipAssignmentsAndWrappers(h.commandWords);
    if (k === -1) continue;
    if (SHELL_INTERPRETERS.has(basename(h.commandWords[k].value))) {
      analyze(h.body, "heredoc fed to a shell", depth + 1, findings);
    }
  }
}

/**
 * Every pkill/pgrep invocation in `command` that carries an option-looking argument after its first
 * pattern. Empty when there is none. Never throws on malformed input (unterminated quotes and
 * substitutions are closed at end of input).
 */
export function findPkillOptionAfterPattern(command: string): OptionAfterPatternFinding[] {
  const findings: OptionAfterPatternFinding[] = [];
  analyze(command, "command", 0, findings);
  return findings;
}
