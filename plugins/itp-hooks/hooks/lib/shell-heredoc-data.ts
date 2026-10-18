/**
 * Heredoc bodies that are DATA, removed from a command before a guard pattern-matches it.
 *
 * WHY. Several Bash guards match regexes against the whole command string. A heredoc body written
 * to a file is text the command is about to store, not commands the shell will run, yet it was
 * matched as if it were the command line (measured 2026-10-17):
 *
 *   - the review-round gate denied a commit whose message heredoc mentioned a `gh pr ready`;
 *   - the pueue auto-wrap guard rewrote a command that only WROTE a script containing a
 *     `for … do python …; done` loop, and the rewrite broke the shell's quoting.
 *
 * A body counts as data only when ALL of these hold, so a guard keeps seeing every body that will
 * be run (found in review: piping or writing-then-running a body hid it from the gate):
 *   - the program consuming it is not a shell (`bash <<'EOF'`, `ssh host sh <<EOF` stay);
 *   - its opening line has no pipe (`cat <<'EOF' | bash` stays);
 *   - if it is written to a file, that file is not named again later in the command
 *     (`cat > s.sh <<'EOF' … EOF; bash s.sh` stays).
 *
 * Pure and never throws: the lexer and the extractor are both total over arbitrary input.
 */

import { basename as pathBasename } from "node:path";

import { extractHeredocs } from "./shell-arg-extractor.ts";
import { lexShellCommands } from "./shell-command-quote-aware-static-lexer.ts";
import { basename, skipAssignmentsAndWrappers } from "./shell-command-invocation-walker.ts";

/** Programs that RUN their stdin: shells, and ssh (whose stdin feeds the remote command or shell). */
const SHELL_INTERPRETERS: ReadonlySet<string> = new Set(["bash", "sh", "zsh", "dash", "ksh", "ssh"]);

/** Bodies of heredocs whose consuming program is a shell interpreter. */
function bodiesFedToAShell(command: string): Set<string> {
  const kept = new Set<string>();
  try {
    for (const h of lexShellCommands(command).heredocs) {
      const k = skipAssignmentsAndWrappers(h.commandWords);
      if (k !== -1 && SHELL_INTERPRETERS.has(basename(h.commandWords[k]!.value))) kept.add(h.body.trim());
    }
  } catch {
    // A lexer failure adds nothing; the pipe and re-use checks below still apply.
  }
  return kept;
}

/** The opening line of the heredoc whose body starts at `bodyIndex`. */
function openingLineBefore(command: string, bodyIndex: number): string {
  const lineEnd = command.lastIndexOf("\n", bodyIndex - 1);
  const lineStart = command.lastIndexOf("\n", lineEnd - 1) + 1;
  return command.slice(lineStart, lineEnd === -1 ? bodyIndex : lineEnd);
}

/** A `|` pipe (not `||`) outside quotes. */
function hasPipe(line: string): boolean {
  const unquoted = line.replace(/'[^']*'/g, "").replace(/"(?:\\.|[^"\\])*"/g, "");
  return /(^|[^|])\|(?!\|)/.test(unquoted);
}

/**
 * `command` with every DATA heredoc body replaced by nothing. Bodies that may be executed keep
 * their text. The opening line and the terminator stay, so the command line itself is unchanged.
 */
export function stripDataHeredocBodies(command: string): string {
  const heredocs = extractHeredocs(command);
  if (heredocs.length === 0) return command;
  const fedToShell = bodiesFedToAShell(command);
  let stripped = command;
  for (const heredoc of heredocs) {
    if (heredoc.body === "" || fedToShell.has(heredoc.body.trim())) continue;
    const bodyIndex = command.indexOf(heredoc.body);
    if (bodyIndex === -1) continue;
    if (hasPipe(openingLineBefore(command, bodyIndex))) continue;
    if (heredoc.redirectTarget !== null) {
      const after = command.slice(bodyIndex + heredoc.body.length);
      if (after.includes(pathBasename(heredoc.redirectTarget))) continue;
    }
    stripped = stripped.split(heredoc.body).join("");
  }
  return stripped;
}
