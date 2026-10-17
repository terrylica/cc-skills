/**
 * Heredoc bodies that are DATA, removed from a command before a guard pattern-matches it.
 *
 * WHY. Several Bash guards match regexes against the whole command string. A heredoc body written
 * to a file is text the command is about to store, not commands the shell will run, yet it was
 * matched as if it were the command line (measured 2026-10-17):
 *
 *   - the review-round gate denied `cat > notes.txt <<'EOF'` because the body mentioned a
 *     `gh pr ready` command;
 *   - the pueue auto-wrap guard rewrote a command that only WROTE a script containing a
 *     `for … do python …; done` loop, and the rewrite broke the shell's quoting.
 *
 * A body fed to a shell (`bash <<'EOF'`, `ssh host sh <<EOF`) IS a script and is kept, so a guard
 * still sees what that shell will run. Everything else (`cat`, `tee`, `python3 -`, `git commit -F -`)
 * is data and is replaced by an empty line.
 *
 * Pure and never throws: the lexer and the extractor are both total over arbitrary input.
 */

import { extractHeredocs } from "./shell-arg-extractor.ts";
import { lexShellCommands } from "./shell-command-quote-aware-static-lexer.ts";
import { basename, skipAssignmentsAndWrappers } from "./shell-command-invocation-walker.ts";

const SHELL_INTERPRETERS: ReadonlySet<string> = new Set(["bash", "sh", "zsh", "dash", "ksh"]);

/** Bodies of heredocs whose consuming program is a shell interpreter. */
function bodiesFedToAShell(command: string): Set<string> {
  const kept = new Set<string>();
  try {
    for (const h of lexShellCommands(command).heredocs) {
      const k = skipAssignmentsAndWrappers(h.commandWords);
      if (k !== -1 && SHELL_INTERPRETERS.has(basename(h.commandWords[k]!.value))) kept.add(h.body.trim());
    }
  } catch {
    // A lexer failure keeps nothing extra: bodies are then treated as data, the common case.
  }
  return kept;
}

/**
 * `command` with every DATA heredoc body replaced by an empty line. Heredocs fed to a shell keep
 * their bodies. The opening line and the terminator stay, so the command line itself is unchanged.
 */
export function stripDataHeredocBodies(command: string): string {
  const heredocs = extractHeredocs(command);
  if (heredocs.length === 0) return command;
  const keep = bodiesFedToAShell(command);
  let stripped = command;
  for (const heredoc of heredocs) {
    if (heredoc.body === "" || keep.has(heredoc.body.trim())) continue;
    stripped = stripped.split(heredoc.body).join("");
  }
  return stripped;
}
