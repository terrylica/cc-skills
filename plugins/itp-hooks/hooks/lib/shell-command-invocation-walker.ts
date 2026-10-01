/**
 * Shell-command invocation walker — pure, dependency-free, never executes or expands anything.
 *
 * Statically lexes a shell command into simple commands and calls a visitor with every program
 * invocation, looking through the wrappers an agent actually writes: assignments, `sudo`, `env`,
 * `nice`, `timeout`, `nohup`, `command`, `exec`, `time`, `caffeinate`, `xargs`, command substitution
 * (`kill $(pgrep -f x)`), `bash|sh|zsh -c '…'`, `ssh host '…'`, `pueue add -- …`, and heredoc bodies
 * fed to a shell (`bash <<'EOF'`).
 *
 * Text that merely MENTIONS a command is never visited: quoted arguments (`git commit -m "…"`),
 * comments, and heredoc bodies fed to anything other than a shell (`cat`, `python3 -`, `git commit
 * -F -`). Redirections and their targets are dropped, so they never look like arguments.
 *
 * Extracted 2026-09-27 from pkill-option-after-pattern-detector.ts so the broad-process-signal
 * detector shares one lexer instead of growing a second one with different blind spots.
 */

/** Where an invocation was found, for deny messages. */
export type InvocationContext =
  | "command"
  | "shell -c script"
  | "ssh remote command"
  | "pueue task"
  | "heredoc fed to a shell";

import {
  lexShellCommands,
  type Word,
} from "./shell-command-quote-aware-static-lexer.ts";

export type { Word } from "./shell-command-quote-aware-static-lexer.ts";

const MAX_RECURSION_DEPTH = 4;

const SHELL_INTERPRETERS = new Set(["bash", "sh", "zsh", "dash", "ksh"]);

export function basename(word: string): string {
  const slash = word.lastIndexOf("/");
  return slash === -1 ? word : word.slice(slash + 1);
}

const isAssignment = (w: string): boolean => /^[A-Za-z_][A-Za-z0-9_]*=/.test(w);

/** Index of the real program word after assignments and wrapper commands, or -1. */
export function skipAssignmentsAndWrappers(words: Word[]): number {
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

/** One program invocation, after assignments and wrappers are skipped. */
export interface ShellInvocation {
  /** Basename of the program word (`/usr/bin/pkill` → `pkill`). */
  readonly program: string;
  readonly programWord: Word;
  readonly args: Word[];
  readonly context: InvocationContext;
}

function walk(
  src: string,
  context: InvocationContext,
  depth: number,
  prefilter: RegExp,
  visit: (invocation: ShellInvocation) => void,
): void {
  if (depth > MAX_RECURSION_DEPTH || !src) return;
  // Cheap pre-filter: nothing to do unless a program the caller cares about appears at all.
  if (!prefilter.test(src)) return;

  const { commands, heredocs } = lexShellCommands(src);

  for (const words of commands) {
    const k = skipAssignmentsAndWrappers(words);
    if (k === -1) continue;
    const prog = basename(words[k].value);
    const args = words.slice(k + 1);

    visit({ program: prog, programWord: words[k], args, context });

    if (SHELL_INTERPRETERS.has(prog)) {
      for (let a = 0; a < args.length; a++) {
        const t = args[a].value;
        if (/^-[A-Za-z]*c[A-Za-z]*$/.test(t)) {
          if (a + 1 < args.length) walk(args[a + 1].value, "shell -c script", depth + 1, prefilter, visit);
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
      walk(remote, "ssh remote command", depth + 1, prefilter, visit);
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
      walk(task, "pueue task", depth + 1, prefilter, visit);
    }
  }

  for (const h of heredocs) {
    const k = skipAssignmentsAndWrappers(h.commandWords);
    if (k === -1) continue;
    if (SHELL_INTERPRETERS.has(basename(h.commandWords[k].value))) {
      walk(h.body, "heredoc fed to a shell", depth + 1, prefilter, visit);
    }
  }
}

/**
 * Call `visit` for every program invocation in `command`, including those nested in `$(…)`,
 * backticks, `sh -c`, ssh remote commands, `pueue add` tasks and heredocs fed to a shell.
 * `prefilter` is tested against each (sub)script before lexing it; pass a regex matching the
 * program names you care about. Never throws on malformed input.
 */
export function walkShellInvocations(
  command: string,
  prefilter: RegExp,
  visit: (invocation: ShellInvocation) => void,
): void {
  walk(command, "command", 0, prefilter, visit);
}
