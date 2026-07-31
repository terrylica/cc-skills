/**
 * Pure detection logic for the headless `claude -p` guard.
 *
 * SPLIT OUT FROM THE HOOK ON PURPOSE. The hook itself reads stdin and calls `deny()`/`allow()`, which
 * makes it awkward to test. Everything decision-shaped lives here as pure functions so the test suite
 * can drive BOTH directions — firing on what must be refused, and staying silent on what must pass.
 * This repo has shipped two guards that were believed working and were not (a mojibake detector that
 * matched the CORRECT character, and a read-back verifier that read the wrong object path and passed
 * vacuously on every input). Both had been tested in one direction only.
 *
 * Knowledge SSoT — every rule below is justified there, and this file duplicates NO prose:
 *   plugins/itp-hooks/docs/headless-claude-p.md
 */

/** Levels `claude --effort` accepts. Anything else is silently ignored by the CLI (exit 0). */
export const VALID_EFFORT_LEVELS = ["low", "medium", "high", "xhigh", "max"] as const;

export type HeadlessViolationKind =
  | "stream-json-without-verbose"
  | "claude-effort-env-var"
  | "invalid-effort-level";

export interface HeadlessViolation {
  readonly kind: HeadlessViolationKind;
  /** Filled with the offending token where one exists (e.g. the bad effort level). */
  readonly detail?: string;
}

/**
 * Is this command actually INVOKING claude headlessly?
 *
 * Deliberately strict about command POSITION. A guard that fires on any appearance of the substring
 * "claude -p" would block writing documentation about `claude -p` — including this plugin's own docs —
 * and a guard people have to fight is a guard they disable. So the binary must sit at the start of a
 * command: line start, or after `;`, `&&`, `||`, `|`, `(`, `{`, or a newline; optionally behind an
 * `env`/`VAR=value` prefix, and optionally behind `timeout <n>`.
 */
export function isHeadlessClaudeInvocation(command: string): boolean {
  return findClaudeInvocations(command).length > 0;
}

/**
 * Remove heredoc BODIES before scanning.
 *
 * Caught by the test suite on first run: `cat <<'EOF' > notes.md` followed by a line reading
 * `claude -p "hi" --output-format stream-json` is DOCUMENTATION, not an invocation — but the line
 * starts at a command position, so the segmenter saw a real call and blocked it. That would have made
 * this guard refuse to let anyone write the very file it points people at, which is the fastest way to
 * get a guard disabled.
 *
 * Handles `<<WORD`, `<<-WORD`, `<<'WORD'` and `<<"WORD"`; the terminator is the marker alone on a line
 * (allowing leading whitespace, which `<<-` permits).
 */
export function stripHeredocBodies(command: string): string {
  const lines = command.split("\n");
  const kept: string[] = [];
  let terminator: string | null = null;
  for (const line of lines) {
    if (terminator !== null) {
      if (line.trim() === terminator) terminator = null;
      continue; // body line — never scanned
    }
    kept.push(line);
    const m = line.match(/<<-?\s*(?:'([^']+)'|"([^"]+)"|([A-Za-z_][A-Za-z0-9_]*))/);
    if (m) terminator = m[1] ?? m[2] ?? m[3] ?? null;
  }
  return kept.join("\n");
}

/** Every headless claude invocation in a (possibly compound) command line, as raw substrings. */
export function findClaudeInvocations(command: string): string[] {
  const found: string[] = [];
  // Segment on shell separators so each candidate is examined at a command position.
  for (const rawSegment of stripHeredocBodies(command).split(/(?:\n|;|&&|\|\||\||&(?!&))+/)) {
    let segment = rawSegment.trim();
    if (segment === "") continue;
    // Peel leading `(`/`{`, `env`, `VAR=value` assignments, and `timeout <n>` / `nohup`.
    // The assignments are peeled rather than rejected because CLAUDE_EFFORT=... is itself a violation
    // we want to REPORT, not a reason to stop recognising the invocation.
    let previous: string | null = null;
    while (previous !== segment) {
      previous = segment;
      segment = segment
        .replace(/^[({]\s*/, "")
        .replace(/^env\s+/, "")
        .replace(/^[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|\S*)\s+/, "")
        .replace(/^(?:timeout|nohup|command)\s+(?:-\S+\s+)*(?:\d+(?:\.\d+)?[smhd]?\s+)?/, "");
    }
    if (!/^(?:\S*\/)?(?:ccmax-)?claude\b/.test(segment)) continue;
    // Must be headless: -p or --print (but NOT --print-something-else).
    if (!/(?:^|\s)(?:-p|--print)(?:\s|=|$)/.test(segment)) continue;
    found.push(rawSegment.trim());
  }
  return found;
}

/** Read the value of a flag written as `--flag value` or `--flag=value`. */
function flagValue(segment: string, flag: string): string | null {
  const eq = segment.match(new RegExp(`${flag}=("[^"]*"|'[^']*'|\\S+)`));
  if (eq?.[1] != null) return eq[1].replace(/^["']|["']$/g, "");
  const spaced = segment.match(new RegExp(`${flag}\\s+("[^"]*"|'[^']*'|[^\\s-]\\S*)`));
  if (spaced?.[1] != null) return spaced[1].replace(/^["']|["']$/g, "");
  return null;
}

/**
 * Every PROVABLY-BROKEN thing in this command — never style, never "you probably meant".
 *
 * The bar for inclusion is that the invocation CANNOT do what its author is asking for:
 *   - stream-json without --verbose: the CLI refuses and emits nothing at all.
 *   - CLAUDE_EFFORT=...: not an input the CLI reads; it looks like reasoning control and is a no-op.
 *   - --effort <not in enum>: accepted with exit 0 and silently ignored, so the intent is discarded.
 * Calling WITHOUT --effort is deliberately NOT here: it defaults to `high`, which is often what you
 * want. Blocking it would make the guard noise, and noisy guards get disabled.
 */
export function findHeadlessViolations(command: string): HeadlessViolation[] {
  const violations: HeadlessViolation[] = [];
  for (const segment of findClaudeInvocations(command)) {
    const outputFormat = flagValue(segment, "--output-format");
    if (outputFormat === "stream-json" && !/(?:^|\s)--verbose(?:\s|=|$)/.test(segment)) {
      violations.push({ kind: "stream-json-without-verbose" });
    }
    const effort = flagValue(segment, "--effort");
    if (effort !== null && !(VALID_EFFORT_LEVELS as readonly string[]).includes(effort)) {
      violations.push({ kind: "invalid-effort-level", detail: effort });
    }
  }
  if (violations.length === 0 && !isHeadlessClaudeInvocation(command)) return violations;
  // The env-var check is command-wide: `CLAUDE_EFFORT=x foo && claude -p ...` still misleads.
  if (isHeadlessClaudeInvocation(command) && /(?:^|\s)CLAUDE_EFFORT=/.test(stripHeredocBodies(command))) {
    violations.push({ kind: "claude-effort-env-var" });
  }
  return violations;
}

const SSOT = "itp-hooks/docs/headless-claude-p.md";

/** Human-facing explanation. Short, states the fix, and points at the SSoT rather than restating it. */
export function explainViolations(violations: readonly HeadlessViolation[]): string {
  const lines = ["🛡️  headless `claude -p` guard — this invocation cannot do what it is asking for:\n"];
  for (const v of violations) {
    if (v.kind === "stream-json-without-verbose") {
      lines.push(
        "  • `--output-format stream-json` with `-p` requires `--verbose`.",
        "    Without it the CLI errors to STDERR and emits NOTHING on stdout — a probe that reads",
        "    only stdout sees an empty stream and misreads it as 'no results'.",
        "    Fix: add `--verbose`.\n",
      );
    } else if (v.kind === "claude-effort-env-var") {
      lines.push(
        "  • `CLAUDE_EFFORT=...` is NOT an input the CLI reads (measured: 8 calls, no separation,",
        "    Welch p ≈ 0.53). It reads like reasoning control and does nothing.",
        "    Fix: use the flag — `--effort low|medium|high|xhigh|max`.\n",
      );
    } else {
      lines.push(
        `  • \`--effort ${v.detail}\` is not a valid level. The CLI accepts it with exit 0 and`,
        "    SILENTLY ignores it, so the run happens at the default (`high`) and looks fine.",
        `    Fix: one of ${VALID_EFFORT_LEVELS.join(", ")}.\n`,
      );
    }
  }
  lines.push(
    `  Full reference (defaults, the ~59k preamble, probing pitfalls): ${SSOT}`,
    "  Escape hatch: add `HEADLESS-P-OK` to the command.",
  );
  return lines.join("\n");
}
