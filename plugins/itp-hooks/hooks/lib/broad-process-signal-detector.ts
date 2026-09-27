/**
 * Broad process-signal detector — pure, dependency-free, never executes or expands anything.
 *
 * THE HAZARD. A signal aimed by NAME or PATTERN instead of by the PID you started reaches every
 * matching process the user owns: other Claude Code sessions, the terminal hosting them, Electron
 * apps and their crash reporters. On 2026-09-27 one `pkill -f '<pattern>' -n` (a trailing option
 * that BSD getopt turned into a second, one-character pattern) did exactly that on the operator's
 * Mac. pkill-option-after-pattern-detector.ts catches that one spelling; this module catches the
 * rest of the family, each of which is broad by construction:
 *
 *   - `kill -1` as a TARGET (`kill -9 -1`, `kill -- -1`): every process you may signal;
 *   - `kill 0`: your whole process group, which under an agent harness is not just your command;
 *   - `pkill` / `killall` of a shared runtime or host program by name (`node`, `bun`, `python3`,
 *     `claude`, `iTerm2`, `tmux`, `Google Chrome`, …), or `kill $(pgrep node)`;
 *   - `pkill -u me` / `killall -u me` with no process name: every process of that user;
 *   - a `pkill` pattern whose literal text is under five characters (`pkill -f vite`, `pkill -f .`).
 *
 * WHAT IT DOES NOT FLAG: `kill <pid>` and `kill -1 <pid>` (there `-1` is SIGHUP), `kill -0` probes,
 * `pgrep` on its own (it only reports), patterns it cannot see (`pkill -f "$PAT"`), single-instance
 * relaunches (`killall Dock`, `killall Finder`, `killall SystemUIServer`), and anything that only
 * mentions such a command (quoted text, comments, heredocs fed to `cat`) — the shared walker never
 * visits those. Option-looking words after the first pkill pattern are left to the option-order
 * detector, so one mistake produces one explanation.
 */

import {
  isSignalArgument,
  optionWordSpan,
} from "./pkill-option-after-pattern-detector.ts";
import {
  type InvocationContext,
  walkShellInvocations,
  type Word,
} from "./shell-command-invocation-walker.ts";

export type BroadSignalProgram = "kill" | "pkill" | "killall";

export type BroadSignalKind =
  | "every-process"
  | "own-process-group"
  | "shared-program-name"
  | "user-wide"
  | "short-pattern";

export interface BroadProcessSignalFinding {
  readonly program: BroadSignalProgram;
  readonly kind: BroadSignalKind;
  readonly context: InvocationContext;
  /** The invocation as written (raw source text of each word), program first. */
  readonly invocationAsWritten: string;
  /** The target, name or pattern that makes it broad ("" for a user-wide call with no name). */
  readonly target: string;
}

/** Literal text shorter than this cannot single out one process on a busy workstation. */
export const MINIMUM_SPECIFIC_PATTERN_LITERAL_LENGTH = 5;

/**
 * Programs that run as many unrelated processes at once on an agent workstation, or that host
 * every agent session. Matched against the WHOLE name or pattern (optionally with a directory),
 * case-insensitively, so `bun server.ts --port 5198` stays specific while `bun` alone is not.
 */
const SHARED_PROGRAM_NAME =
  /^(?:.*\/)?(?:node|nodejs|bun|bunx|deno|npm|npx|pnpm|yarn|uv|uvx|python(?:\d+(?:\.\d+)?)?|ruby|perl|java|php|bash|sh|zsh|fish|dash|ksh|ssh|sshd|claude|codex|electron|chrome|google chrome(?: helper.*)?|chromium|code(?: helper.*)?|cursor|iterm2?|terminal|tmux(?:: server)?|screen|mosh-server|launchd|loginwindow|windowserver|systemd|sway|pueued|login)$/i;

const REGEX_METACHARACTERS = /[.*+?^$()[\]{}|\\]/g;

function literalTextOf(pattern: string): string {
  return pattern.replace(/\\(.)/g, "$1").replace(REGEX_METACHARACTERS, "").trim();
}

/** A pattern whose value is not known statically (`"$PAT"`, `$(cat f)`) cannot be judged. */
const isOpaque = (value: string): boolean => value.includes("$") || value.includes("`");

function judgeName(value: string, isPattern: boolean): BroadSignalKind | null {
  if (isOpaque(value)) return null;
  if (SHARED_PROGRAM_NAME.test(value.trim())) return "shared-program-name";
  if (isPattern && literalTextOf(value).length < MINIMUM_SPECIFIC_PATTERN_LITERAL_LENGTH) {
    return "short-pattern";
  }
  return null;
}

function rawOf(programWord: Word, args: Word[]): string {
  return [programWord, ...args].map((w) => w.raw).join(" ");
}

/** `kill`: flags a target of -1 or 0, and `$(pgrep …)` / backtick targets with a broad pattern. */
function checkKill(
  programWord: Word,
  args: Word[],
  context: InvocationContext,
  findings: BroadProcessSignalFinding[],
): void {
  let idx = 0;
  const first = args[0]?.value ?? "";
  if (first === "-l" || first === "-L") return; // listing signal names
  if (first === "-s" || first === "-n") idx = 2;
  else if (first !== "--" && first.length > 1 && first.startsWith("-") && !first.startsWith("--")) {
    idx = 1; // the signal spec: -9, -KILL, -SIGTERM, and -1 (SIGHUP) in this position
  }
  if (args[idx]?.value === "--") idx++;

  const invocation = rawOf(programWord, args);
  for (const target of args.slice(idx)) {
    const t = target.value;
    if (t === "-1") {
      findings.push({ program: "kill", kind: "every-process", context, invocationAsWritten: invocation, target: t });
    } else if (t === "0" || t === "-0") {
      findings.push({ program: "kill", kind: "own-process-group", context, invocationAsWritten: invocation, target: t });
    } else {
      const inner = /^\$\((.*)\)$/s.exec(target.raw)?.[1] ?? /^`(.*)`$/s.exec(target.raw)?.[1];
      if (inner === undefined) continue;
      walkShellInvocations(inner, /\bpgrep\b/, (nested) => {
        if (nested.program !== "pgrep") return;
        const judged = judgeProcessMatcher(nested.args);
        if (judged) {
          findings.push({ program: "kill", kind: judged.kind, context, invocationAsWritten: invocation, target: judged.target });
        }
      });
    }
  }
}

/** Shared by pkill and `kill $(pgrep …)`: the broadest thing about a matcher's arguments. */
function judgeProcessMatcher(args: Word[]): { kind: BroadSignalKind; target: string } | null {
  let idx = 0;
  if (idx < args.length && isSignalArgument(args[idx].value)) idx++;
  let userScoped = false;
  let afterDoubleDash = false;
  while (idx < args.length) {
    const t = args[idx].value;
    if (t === "--") {
      afterDoubleDash = true;
      idx++;
      break;
    }
    if (t.length > 1 && t.startsWith("-")) {
      if (/^-[A-Za-z]*[uUG]/.test(t) || /^--(?:euid|uid|group)\b/.test(t)) userScoped = true;
      const span = optionWordSpan(t, idx + 1 < args.length);
      if (isOpaque(args.slice(idx, idx + span).map((w) => w.value).join(" "))) return null;
      idx += span;
      continue;
    }
    break;
  }
  const rest = args.slice(idx);
  // Option-looking words after the first pattern belong to the option-order detector.
  const patterns = afterDoubleDash ? rest : rest.filter((w, i) => i === 0 || !w.value.startsWith("-"));
  if (patterns.length === 0) return userScoped ? { kind: "user-wide", target: "" } : null;
  for (const p of patterns) {
    const kind = judgeName(p.value, true);
    if (kind) return { kind, target: p.value };
  }
  return null;
}

/** killall, BSD/macOS and psmisc: names are exact unless -m / -r / --regexp makes them regexes. */
function checkKillall(
  programWord: Word,
  args: Word[],
  context: InvocationContext,
  findings: BroadProcessSignalFinding[],
): void {
  const names: string[] = [];
  let regexMode = false;
  let userScoped = false;
  let idx = 0;
  while (idx < args.length) {
    const t = args[idx].value;
    if (t === "--") {
      names.push(...args.slice(idx + 1).map((w) => w.value));
      break;
    }
    if (t.length > 1 && t.startsWith("-")) {
      idx++;
      if (isSignalArgument(t)) continue;
      if (t === "--regexp") regexMode = true;
      if (t === "--user") userScoped = true;
      if (t.startsWith("--")) continue;
      const letters = t.slice(1);
      if (/[mr]/.test(letters)) regexMode = true;
      if (letters.includes("u")) userScoped = true;
      const last = letters[letters.length - 1];
      const next = args[idx]?.value;
      if (next !== undefined && "utoyZn".includes(last)) idx++;
      else if (next !== undefined && last === "c") {
        names.push(next); // macOS -c procname
        idx++;
      } else if (next !== undefined && last === "s" && /^(?:\d+|(?:SIG)?[A-Z]{2,})$/.test(next)) idx++;
      continue;
    }
    names.push(t);
    idx++;
  }

  const invocation = rawOf(programWord, args);
  if (names.length === 0) {
    if (userScoped) findings.push({ program: "killall", kind: "user-wide", context, invocationAsWritten: invocation, target: "" });
    return;
  }
  for (const name of names) {
    const kind = judgeName(name, regexMode);
    if (kind) {
      findings.push({ program: "killall", kind, context, invocationAsWritten: invocation, target: name });
      return;
    }
  }
}

/**
 * Every broad kill / pkill / killall invocation in `command`, including those nested in `$(…)`,
 * `sh -c`, ssh remote commands, pueue tasks and heredocs fed to a shell. Empty when there is none.
 * Never throws on malformed input.
 */
export function findBroadProcessSignals(command: string): BroadProcessSignalFinding[] {
  const findings: BroadProcessSignalFinding[] = [];
  walkShellInvocations(command, /\b(?:kill|pkill|killall)\b/, ({ program, programWord, args, context }) => {
    if (program === "kill") checkKill(programWord, args, context, findings);
    else if (program === "killall") checkKillall(programWord, args, context, findings);
    else if (program === "pkill") {
      const judged = judgeProcessMatcher(args);
      if (judged) {
        findings.push({ program: "pkill", kind: judged.kind, context, invocationAsWritten: rawOf(programWord, args), target: judged.target });
      }
    }
  });
  return findings;
}
