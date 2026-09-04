#!/usr/bin/env bun
// # PROCESS-STORM-OK
/**
 * SIGPIPE-under-pipefail Detector — iter-125
 *
 * Detects a pipeline whose READER exits early, inside a script that enables
 * `pipefail`. The reader closes the pipe, the producer is killed by SIGPIPE and
 * exits 141, and under `pipefail` the PIPELINE takes the producer's status — so
 * the pipeline reports failure even though the reader did its job.
 *
 * TWO HARM MODES, BOTH SILENT:
 *   (A) FATAL ABORT  — unguarded pipeline under `set -e`: the script dies
 *                      mid-run with status 141 and no error line.
 *   (B) WRONG ANSWER — the pipeline sits in an `if`/`while` condition or behind
 *                      `|| fallback`: no abort, but the boolean INVERTS or the
 *                      captured value silently becomes the fallback.
 *
 * Harm mode B is the reason this is worth a hook. A measured instance: a
 * pre-push hook ran `moon query tasks | grep -q '"check-all-gates"'` to decide
 * whether a task existed. grep found it, exited, killed moon, and the condition
 * evaluated FALSE — so the hook reported that 40 gates had no runner while the
 * command ran fine by hand. It is a RACE, which is why it reads as flakiness:
 * if the producer finishes writing before the reader exits there is no SIGPIPE
 * and everything works. Small output usually wins that race, so this passes in
 * testing and starts failing as the data grows. Measured directly on that case:
 * `with pipefail -> exit 141`, `without pipefail -> exit 0`, same command.
 *
 * PROVENANCE — this is a PORT, not a fresh heuristic. The matchers below are
 * carried over from `terrylica/mql5` scripts/ci/sigpipe-pipefail-gate.sh, which
 * was built from five recorded in-tree encounters and calibrated against a
 * whole-tree census of 70 sites across 33 of 114 tracked pipefail scripts. The
 * awk rules in particular encode a bug that census found in the gate itself.
 *
 * WHY THIS IS ADVISORY AND NOT A BLOCK. That census is also why it must not
 * deny: the pattern is common, frequently harmless, and its own RCA records
 * three `git push --no-verify` bypasses caused by a gate that blocked too
 * eagerly — each bypass disabling all 40 gates at once, which is strictly worse
 * than the defect. A reminder that is read beats a block that is routed around.
 *
 * Escape hatch: `SIGPIPE-OK: <reason>` on any line of the pipeline's span, or
 * the file-wide `SHELL-SAFETY-OK` already honoured by the sibling detector.
 *
 * Entry point: detectSigpipeUnderPipefailSites(filePath, content)
 */

import { isShellScript } from "./shell-script-safety-detector-status-loss-and-masked-substitution-iter119.ts";

// ============================================================================
// Types
// ============================================================================

export interface SigpipeSite {
  /** 1-based line number of the pipeline's first line. */
  lineNumber: number;
  /** Which early-exiting reader was matched, e.g. "grep -q". */
  reader: string;
  /** The producer text immediately left of the offending `|`, trimmed. */
  producer: string;
  /** The pipeline source, trimmed and truncated for display. */
  statement: string;
}

// ============================================================================
// Configuration — ported verbatim in intent from the mql5 gate
// ============================================================================

/**
 * `set -o pipefail`, `set -euo pipefail`, `set -eo pipefail` ... The `-` and the
 * exclusion of `#` are what keep `set +o pipefail` (a DISABLE, and the gate's own
 * prescribed remediation) from reading as an enable.
 */
const PIPEFAIL_ENABLED = /^[ \t]*set[ \t]+-[^#\n]*pipefail/m;

/** `$( set +o pipefail; producer | head -1 )` is the fix, not the bug. */
const PIPEFAIL_DISABLED_INLINE = /set[ \t]+\+o[ \t]+pipefail/;

const ESCAPE_MARKER = "SIGPIPE-OK";
const FILE_WIDE_SHELL_SAFETY_MARKER = "SHELL-SAFETY-OK";

/**
 * Readers that close the pipe before the producer is done writing.
 *
 * NOT readers, deliberately — they all drain to EOF, and flagging them would be
 * the noise that gets a hook disabled: `tail`, `tail -n +N`, `sort`, `wc`,
 * `while read`, `grep` without -q/-m, `awk` without `exit`.
 */
const EARLY_EXITING_READERS: readonly (readonly [RegExp, string])[] = [
  // `head -n -N` / `head -c -N` print all-but-last-N and so must read to EOF.
  [/^head\b(?![^|;&]*[ \t]-[nc][ \t]*-)/, "head"],
  [/^(?:e|f|z)?grep\b[^|;&]*(?:[ \t]-[A-Za-z]*q|--quiet|--silent)/, "grep -q"],
  [/^(?:e|f|z)?grep\b[^|;&]*(?:[ \t]-[A-Za-z]*m[ \t]*[0-9]|--max-count)/, "grep -m N"],
  [/^g?sed\b[^|;&]*(?:^|[;{/'"0-9 \t])q(?:[;}'"[ \t]|$)/, "sed ... q"],
  [/^read\b[^|]*$/, "read (final stage)"],
];

/**
 * `awk` is handled by a small quote-aware scan rather than a regex, because
 * BOTH regexes carried over from the mql5 gate produce false positives that its
 * own test suite did not cover. Measured while porting:
 *
 *   `awk -v x="exit" '{print}'`  — matched by the gate's rule (i)
 *       `^g?awk\b[^|;&]*\bexit\b` has no quote awareness at all, so the `exit`
 *       inside a `-v` VALUE reads as awk's own. The gate's comment attributes
 *       quote-safety to the `['"]` group, but that group is in rule (ii) and
 *       does not protect rule (i).
 *
 *   `awk '{print}'; exit 1`      — matched by the gate's rule (ii)
 *       `^g?awk\b[^|]*?(['"])[^'"]*[{;\t ][ \t]*exit\b` can bind `(['"])` to the
 *       CLOSING quote of the program and then scan the shell code after it, so a
 *       shell `exit` following the pipeline is credited to awk. Rule (i)
 *       correctly declines this one; rule (ii) undoes that.
 *
 * The actual semantics are simpler than either regex: awk exits early iff its
 * PROGRAM contains a bare `exit`. So extract the program and look in it.
 */
export function awkProgramExitsEarly(segment: string): boolean {
  if (!/^g?awk\b/.test(segment)) return false;
  let rest = segment.replace(/^g?awk\b/, "");

  // Drop option arguments that can carry an arbitrary VALUE (`-v x="exit"`,
  // `-F '|'`), so their contents are never mistaken for the program.
  rest = rest.replace(/[ \t]+-(?:v|F|f)(?:[ \t]*|=)(?:'[^']*'|"[^"]*"|[^ \t]+)/g, " ");

  const bareExit = /(?:^|[{};&\s])exit\b/;

  // The program is conventionally the first quoted argument.
  const quoted = /'([^']*)'|"([^"]*)"/.exec(rest);
  if (quoted) {
    return bareExit.test(quoted[1] ?? quoted[2] ?? "");
  }

  // Unquoted program: it ends at the first shell separator.
  const untilSeparator = rest.split(/[;&|]/)[0] ?? "";
  return bareExit.test(untilSeparator);
}

// ============================================================================
// Lexing helpers
// ============================================================================

/**
 * Indices of every UNQUOTED single `|` — not `||` (logical or) and not `|&`.
 * Quote-aware, because a `|` inside an awk program or a grep pattern is data.
 */
export function findUnquotedPipePositions(code: string): number[] {
  const positions: number[] = [];
  let quote: string | null = null;
  let i = 0;
  while (i < code.length) {
    const c = code[i] as string;
    if (quote) {
      if (c === "\\" && quote === '"') {
        i += 2;
        continue;
      }
      if (c === quote) quote = null;
      i += 1;
      continue;
    }
    if (c === "'" || c === '"') {
      quote = c;
      i += 1;
      continue;
    }
    if (c === "|") {
      const next = code[i + 1];
      if (next === "|" || next === "&") {
        i += 2;
        continue;
      }
      if (i > 0 && code[i - 1] === "|") {
        i += 1;
        continue;
      }
      positions.push(i);
    }
    i += 1;
  }
  return positions;
}

/**
 * Line indices (0-based) that are inside a heredoc BODY. A heredoc body is data,
 * not code: `cat <<EOF ... a | head ... EOF` contains no pipeline.
 */
function computeHeredocBodyFlags(lines: readonly string[]): boolean[] {
  const flags: boolean[] = Array.from({ length: lines.length }, () => false);
  let terminator: string | null = null;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i] as string;
    if (terminator !== null) {
      flags[i] = true;
      if (line.trim() === terminator) {
        flags[i] = false; // the terminator line itself is not body
        terminator = null;
      }
      continue;
    }
    const open = /<<-?[ \t]*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1/.exec(line);
    if (open) terminator = open[2] as string;
  }
  return flags;
}

/** Remove a single trailing `\` line-continuation, if present. */
function dropLineContinuationBackslash(line: string): string {
  return line.endsWith("\\") ? line.slice(0, -1) : line;
}

/**
 * True when a line ends with `|` plus optional trailing blanks — the shell's
 * other way of continuing a pipeline onto the next physical line.
 */
function endsWithTrailingPipe(line: string): boolean {
  const trimmed = line.trimEnd();
  return trimmed.endsWith("|") && !trimmed.endsWith("||");
}

/**
 * Fold physical lines into logical ones: backslash continuations and a trailing
 * `|` both continue a pipeline onto the next line, and a pipeline split that way
 * is exactly as dangerous as one on a single line.
 *
 * Returns [startLineNumber (1-based), endLineNumber (1-based), joinedCode].
 */
export function foldLogicalLines(lines: readonly string[]): [number, number, string][] {
  const heredoc = computeHeredocBodyFlags(lines);
  const out: [number, number, string][] = [];
  let i = 0;
  while (i < lines.length) {
    if (heredoc[i]) {
      i += 1;
      continue;
    }
    const start = i;
    let joined = dropLineContinuationBackslash(lines[i] as string);
    while (
      i < lines.length - 1 &&
      ((lines[i] as string).endsWith("\\") ||
        endsWithTrailingPipe(stripTrailingComment(lines[i] as string)))
    ) {
      i += 1;
      if (heredoc[i]) break;
      joined += " " + dropLineContinuationBackslash(lines[i] as string).trim();
    }
    out.push([start + 1, i + 1, joined]);
    i += 1;
  }
  return out;
}

/** Drop a trailing `# ...` comment, respecting single and double quotes. */
export function stripTrailingComment(line: string): string {
  let quote: string | null = null;
  let i = 0;
  while (i < line.length) {
    const c = line[i] as string;
    if (quote) {
      if (c === "\\" && quote === '"') {
        i += 2;
        continue;
      }
      if (c === quote) quote = null;
      i += 1;
      continue;
    }
    if (c === "'" || c === '"') {
      quote = c;
      i += 1;
      continue;
    }
    if (c === "#") return line.slice(0, i);
    i += 1;
  }
  return line;
}

// ============================================================================
// Detection
// ============================================================================

export function detectSigpipeUnderPipefailSites(
  filePath: string,
  content: string,
): SigpipeSite[] {
  if (!isShellScript(filePath, content)) return [];

  // `pipefail` is what turns a harmless broken pipe into a failed pipeline.
  // Without it the producer's 141 is discarded and only the reader's status
  // counts, which is why this detector is scoped to files that enable it.
  if (!PIPEFAIL_ENABLED.test(content)) return [];

  if (content.includes(FILE_WIDE_SHELL_SAFETY_MARKER)) return [];

  const lines = content.split("\n");
  const sites: SigpipeSite[] = [];

  for (const [start, end, rawCode] of foldLogicalLines(lines)) {
    // An escape marker anywhere in the pipeline's span suppresses it.
    let escaped = false;
    for (let n = start; n <= Math.min(end, lines.length); n += 1) {
      if ((lines[n - 1] as string).includes(ESCAPE_MARKER)) {
        escaped = true;
        break;
      }
    }
    if (escaped) continue;

    const code = stripTrailingComment(rawCode);

    // Remediation, not defect: the author already turned pipefail off here.
    if (PIPEFAIL_DISABLED_INLINE.test(code)) continue;

    const positions = findUnquotedPipePositions(code);
    for (let idx = 0; idx < positions.length; idx += 1) {
      const p = positions[idx] as number;
      // Strip leading `VAR=value ` assignment prefixes so `FOO=1 head -1` matches.
      const segment = code
        .slice(p + 1)
        .replace(/^[ \t]+/, "")
        // `[^ \t]*` stopped at the first space, so `FOO="a b" head -1` left `b" head -1` as the
        // segment and the reader was not recognised. Same defect as the citation guard's `\S*`,
        // spelled differently — which is why a grep for `\S*` alone did not find it.
        .replace(/^(?:[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|[^ \t]*)[ \t]+)*/, "");

      const regexMatch = EARLY_EXITING_READERS.find(([rx]) => rx.test(segment));
      const reader = regexMatch
        ? regexMatch[1]
        : awkProgramExitsEarly(segment)
          ? "awk ... exit"
          : null;
      if (reader === null) continue;

      const prev = idx > 0 ? (positions[idx - 1] as number) + 1 : 0;
      const producer = code
        .slice(prev, p)
        .replace(/^.*?\$\(/, "")
        .replace(/^[ \t]*(?:if|while|until|elif|!)[ \t]+/, "")
        .trim()
        .replace(/^[({ \t]+/, "")
        .trim();

      sites.push({
        lineNumber: start,
        reader,
        producer: producer.slice(0, 70),
        statement: code.trim().slice(0, 140),
      });
    }
  }

  return sites;
}
