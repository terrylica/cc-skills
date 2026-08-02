#!/usr/bin/env bun
// # PROCESS-STORM-OK
/**
 * Shell Script Safety Detector — iter-119
 *
 * Detects two always-wrong, mechanically-decidable shell defects:
 *
 * RULE 1 — STATUS-LOSS-AFTER-IF
 *   Flags `$?` on a line when the nearest preceding code line (before it)
 *   ends with `fi` and the corresponding `if` block contains NO `else`/`elif`
 *   at the same nesting depth. With no else branch, the condition-failed
 *   path runs no branch, so `$?` is 0 — masking the real failure.
 *
 * RULE 2 — MASKED-COMMAND-SUBSTITUTION
 *   Flags `local|export|readonly|declare|typeset NAME=$(...)` and
 *   `local NAME=\`...\`` forms. The declaration keyword silences errexit
 *   (the command substitution's exit code is LOST). Exception: arithmetic
 *   expansion `$((...))` is safe and must NOT be flagged.
 *
 * Escape hatch: `SHELL-SAFETY-OK: <reason ≥ 8 chars>` (FILE_WIDE)
 *
 * Entry points:
 *   - detectShellStatusLossDefects(filePath, content)
 *   - detectShellMaskedCommandSubstitutionDefects(filePath, content)
 *   - detectAllShellSafetyDefects(filePath, content) — both rules
 *
 * Empirical facts enforced:
 *   A. `rc=$?` after `fi` with NO else → loses status (BUG — flag)
 *   B. `rc=$?` INSIDE an `else` branch → real status (OK — do not flag)
 *   C. `local rc=$?` → real status via early expansion (OK — do not flag)
 *   D. `local out=$(cmd)` → always 0, silently defeats errexit (BUG — flag)
 *   E. `local i=$((n-1))` → arithmetic, safe (OK — do not flag)
 *   F. `$?` after `done`/`esac`/`}` → legitimate (OK — do not flag)
 *
 * Applies to: .sh/.bash/.zsh files or files with bash/sh/zsh shebang.
 * Skips: /fixtures/, /tests/fixtures/, .bak files (test counter-examples).
 */

import {
  hasFileWideEscapeHatchMarkerInContent,
  type EscapeHatchMarkerDetectionConfiguration,
} from "./shared-escape-hatch-marker-detection-helper-cross-pretooluse-and-posttooluse-iter107.ts";

// ============================================================================
// Configuration
// ============================================================================

const SHELL_EXTENSIONS = new Set([".sh", ".bash", ".zsh"]);

const SHELL_SAFETY_ESCAPE_HATCH_CONFIGURATION: EscapeHatchMarkerDetectionConfiguration = {
  markerNameTokenIncludingSuffix: "SHELL-SAFETY-OK",
  windowSemanticsMode: "FILE_WIDE",
  requireMinimumReasonCharacterCountAfterColonOrZeroForOptional: 8,
};

// ============================================================================
// Types
// ============================================================================

export interface ShellSafetyDefect {
  rule: "STATUS-LOSS-AFTER-IF" | "MASKED-COMMAND-SUBSTITUTION";
  lineNumber: number;
  statement: string;
  explanation: string;
  correctedForm: string;
}

// ============================================================================
// Utilities
// ============================================================================

function getFileExtension(filePath: string): string {
  const lastDot = filePath.lastIndexOf(".");
  return lastDot === -1 ? "" : filePath.slice(lastDot);
}

function hasShellShebang(content: string): boolean {
  const firstLine = content.split("\n")[0] ?? "";
  return /^#!.*\b(bash|sh|zsh)\b/.test(firstLine);
}

/**
 * Paths whose shell scripts are not ours to police. Vendored dependency checkouts are
 * upstream code: a corpus scan surfaced a real masked substitution in swift-collections'
 * `Utils/generate-docs.sh` under `.build/checkouts/`, which is a true defect but one we
 * can neither fix nor keep fixed across a re-resolve.
 */
const NON_AUTHORED_PATH_FRAGMENTS: readonly string[] = [
  "/fixtures/",
  "/tests/fixtures/",
  "/node_modules/",
  "/.build/",
  "/vendor/",
  "/third_party/",
  "/site-packages/",
];

export function isShellScript(filePath: string, content: string): boolean {
  // Skip fixtures, test counter-examples, and vendored upstream code
  if (
    NON_AUTHORED_PATH_FRAGMENTS.some((fragment) => filePath.includes(fragment)) ||
    filePath.endsWith(".bak")
  ) {
    return false;
  }

  const ext = getFileExtension(filePath);
  if (SHELL_EXTENSIONS.has(ext)) {
    return true;
  }

  // Check shebang for extensionless scripts
  return hasShellShebang(content);
}

// ============================================================================
// RULE 1: STATUS-LOSS-AFTER-IF Detection
// ============================================================================

/**
 * Find the nearest preceding line that contains actual code (not blank/comment).
 * Return the line index and the line content.
 * A line is considered code if it's non-empty and doesn't start with '#'.
 * Crucially, we only look at the non-comment part of a line (e.g., "cmd; fi # comment")
 * is considered code ending with "fi" even if there's a trailing comment.
 */
/**
 * Strip trailing comment from a line (naive: everything after first # that's
 * not inside quotes). We use a simple approach: if the line starts with #,
 * it's a comment. Otherwise, we strip from the first # onward.
 * This doesn't handle quotes perfectly, but it's conservative.
 */
function stripTrailingComment(line: string): string {
  // If entire line is a comment, return empty
  if (line.trim().startsWith("#")) {
    return "";
  }

  // Simple heuristic: find the first # that's likely a comment
  // (not inside a string). For now, just find # and strip.
  // A full parser would be better, but this is defensive enough.
  const hashIndex = line.indexOf("#");
  if (hashIndex === -1) return line;

  return line.slice(0, hashIndex);
}

function findNearestPrecedingCodeLine(
  lines: readonly string[],
  beforeLineIndex: number,
): { index: number; line: string } | null {
  for (let i = beforeLineIndex - 1; i >= 0; i--) {
    const rawLine = lines[i] ?? "";
    const withoutComment = stripTrailingComment(rawLine);
    const trimmed = withoutComment.trim();

    if (trimmed) {
      return { index: i, line: rawLine };
    }
  }
  return null;
}

/**
 * Check if a line ends with the token `fi` (possibly followed by whitespace or inline comment).
 */
function lineEndsWithFi(line: string): boolean {
  const trimmed = line.trim();
  if (trimmed === "fi") return true;
  if (/; fi\s*(?:#.*)?$/.test(trimmed)) return true;
  if (/^fi\s*(?:#.*)?$/.test(trimmed)) return true;
  return false;
}

const HEREDOC_OPENER_PATTERN =
  /<<(-?)\s*(?:'([A-Za-z_][A-Za-z0-9_]*)'|"([A-Za-z_][A-Za-z0-9_]*)"|([A-Za-z_][A-Za-z0-9_]*))/;

/**
 * Mark every line that sits INSIDE a heredoc body.
 *
 * A heredoc body is DATA, not code. `cat <<'EOF' ... export X=$(op read …) ... EOF`
 * is a template being printed for a human to copy, not an assignment this script runs.
 * Two such templates live in devops-tools/session-chronicle; flagging them would block
 * edits to files that contain no defect at all — and a guard that blocks correct code
 * is the one thing that guarantees the guard gets switched off.
 */
function computeHeredocBodyLineFlags(lines: readonly string[]): boolean[] {
  const inside: boolean[] = Array.from({ length: lines.length }, () => false);
  let delimiter: string | null = null;
  let allowIndentedTerminator = false;

  for (const [index, raw] of lines.entries()) {
    if (delimiter !== null) {
      // `<<-` (and only `<<-`) permits a tab-indented terminator.
      const candidate = allowIndentedTerminator ? raw.trim() : raw.replace(/\s+$/, "");
      if (candidate === delimiter) {
        delimiter = null;
        continue;
      }
      inside[index] = true;
      continue;
    }

    // `<<` or `<<-` followed by an optionally quoted word. `<<<` is a herestring and
    // `$(( x << 2 ))` is a bit shift — neither opens a body, so strip `<<<` first and
    // require a word (not a digit or paren) after the operator.
    const opener = stripTrailingComment(raw).replaceAll("<<<", "").match(HEREDOC_OPENER_PATTERN);
    if (opener) {
      allowIndentedTerminator = opener[1] === "-";
      delimiter = opener[2] ?? opener[3] ?? opener[4] ?? null;
    }
  }

  return inside;
}

type ShellConditionalTokenKind = "if" | "fi" | "else" | "elif";
interface ShellConditionalToken {
  lineIndex: number;
  kind: ShellConditionalTokenKind;
}

/**
 * Every if/fi/else/elif token in source order, comments and heredoc bodies removed.
 *
 * Token-level rather than line-level because `if cmd; then exit 0; fi` carries BOTH
 * the `if` and its `fi` on ONE line — see the note on the consumer below.
 */
function collectShellConditionalTokens(
  lines: readonly string[],
  heredocBody: readonly boolean[],
): ShellConditionalToken[] {
  const tokens: ShellConditionalToken[] = [];

  for (const [index, raw] of lines.entries()) {
    if (heredocBody[index]) continue;

    // `elif` before `if` in the alternation so the longer keyword wins. The `\b`
    // anchors already stop `fi` matching inside `fifo` and `if` inside `elif`/`notify`.
    for (const match of stripTrailingComment(raw).matchAll(/\b(elif|else|if|fi)\b/g)) {
      tokens.push({ lineIndex: index, kind: match[1] as ShellConditionalTokenKind });
    }
  }

  return tokens;
}

/**
 * True iff the `if` block closed by the `fi` on `fiLineIndex` HAS an `else`/`elif`
 * — in which case the following `$?` carries that branch's real status and must NOT
 * be flagged (verified fact B).
 *
 * The previous implementation scanned line by line and, on seeing `fi`, immediately
 * `continue`d. For the single-line form `if cmd; then exit 0; fi` that skipped past
 * the `if` sitting on the SAME line, so it never found a match, concluded "unresolved"
 * and declined to flag — silently missing the most common spelling of the bug.
 *
 * Fails SAFE: anything it cannot resolve returns true (do not flag).
 */
function ifBlockClosedAtLineHasElseOrElif(
  lines: readonly string[],
  fiLineIndex: number,
  heredocBody: readonly boolean[],
): boolean {
  const tokens = collectShellConditionalTokens(lines, heredocBody);

  // The LAST `fi` on the closing line is the one immediately preceding our `$?`.
  let fiTokenIndex = -1;
  for (let t = tokens.length - 1; t >= 0; t--) {
    if (tokens[t]?.kind === "fi" && tokens[t]?.lineIndex === fiLineIndex) {
      fiTokenIndex = t;
      break;
    }
  }
  if (fiTokenIndex === -1) return true;

  let depth = 0;
  for (let t = fiTokenIndex; t >= 0; t--) {
    const kind = tokens[t]?.kind;
    if (kind === "fi") {
      depth++;
      continue;
    }
    if (kind !== "if") continue;

    depth--;
    if (depth !== 0) continue;

    // Matching `if` found. An else/elif belongs to THIS block only at nesting depth 0
    // relative to it — an else inside a NESTED if must not exempt the outer one.
    let nestedDepth = 0;
    for (let u = t + 1; u < fiTokenIndex; u++) {
      const inner = tokens[u]?.kind;
      if (inner === "if") nestedDepth++;
      else if (inner === "fi") nestedDepth--;
      else if ((inner === "else" || inner === "elif") && nestedDepth === 0) return true;
    }
    return false;
  }

  return true;
}

export function detectShellStatusLossDefects(
  filePath: string,
  content: string,
): ShellSafetyDefect[] {
  if (!isShellScript(filePath, content)) {
    return [];
  }

  // Check for file-wide escape hatch
  if (hasFileWideEscapeHatchMarkerInContent(content, SHELL_SAFETY_ESCAPE_HATCH_CONFIGURATION)) {
    return [];
  }

  const defects: ShellSafetyDefect[] = [];
  const lines = content.split("\n");
  const heredocBody = computeHeredocBodyLineFlags(lines);

  for (const [i, line] of lines.entries()) {
    // Heredoc bodies are printed data, not executed code.
    if (heredocBody[i]) continue;

    // Look for `$?` on this line
    const statusRefIndex = line.indexOf("$?");
    if (statusRefIndex === -1) continue;

    // If a command separator appears BEFORE the `$?` on this same line, the `$?`
    // binds to that command, not to the preceding `fi`. Real example that made this
    // necessary (install-workspace-launcher:258):
    //
    //     if [ $ec -eq 0 ]; then wl_phase_bootstrap || ec=$?; fi
    //     if [ $ec -eq 0 ]; then wl_phase_fetch     || ec=$?; fi
    //
    // The second line's `$?` is `wl_phase_fetch`'s status -- correct code -- even
    // though the nearest preceding code line ends in `fi`. Note this deliberately
    // does NOT skip the whole line on merely CONTAINING `||`: the css incident line
    // `log_info "Exact resume FAILED (exit $?)"` has a command before the `$?` too,
    // but no separator, so the expansion still carries the dead `fi` status.
    if (/[;&|]/.test(line.slice(0, statusRefIndex))) continue;

    // Find the nearest preceding code line
    const precedingCodeLine = findNearestPrecedingCodeLine(lines, i);
    if (!precedingCodeLine) continue; // No preceding code

    // Check if it ends with `fi` and has no `else`/`elif`
    if (!lineEndsWithFi(precedingCodeLine.line)) continue;

    // Found `$?` after `fi` — check for else/elif
    const hasElse = ifBlockClosedAtLineHasElseOrElif(lines, precedingCodeLine.index, heredocBody);
    if (hasElse) continue; // Has else/elif, so this is OK

    // DEFECT: `$?` after `fi` with no `else`
    const statement = line.trim();
    const correctedForm =
      "Place `local rc=$?` (or similar) as the FIRST statement INSIDE the else branch, " +
      "or refactor the if/else to have an else clause that captures the exit status.";

    defects.push({
      rule: "STATUS-LOSS-AFTER-IF",
      lineNumber: i + 1,
      statement,
      explanation:
        "With no else branch, the condition-failed path runs no code, so $? is 0 " +
        "(success). This masks the real failure. Use `local rc=$?` inside an else " +
        "branch to capture the actual exit status.",
      correctedForm,
    });
  }

  return defects;
}

// ============================================================================
// RULE 2: MASKED-COMMAND-SUBSTITUTION Detection
// ============================================================================

/**
 * Regex that matches declaration keywords FOLLOWED BY variable assignment
 * with command substitution. This pattern ensures we only flag actual
 * declarations like `local var=$(cmd)`, not global assignments like `var=$(cmd)`.
 *
 * Pattern breakdown:
 *   \b(local|export|readonly|declare|typeset)\b  — declaration keyword
 *   \s+                                          — whitespace
 *   [a-zA-Z_][a-zA-Z0-9_]*                       — variable name
 *   \s*=\s*                                      — assignment operator
 *   \$\((?!\()                                   — start of $(... but NOT $((...)
 *   or `                                         — backtick substitution
 */
const DECLARATION_WITH_SUBSTITUTION_PATTERN =
  /\b(local|export|readonly|declare|typeset)\b\s+(?:-[A-Za-z]+\s+)*[a-zA-Z_][a-zA-Z0-9_]*\s*=\s*"?(?:\$\((?!\()|`)/;

/**
 * Body of the first `$( … )` on the line, with balanced parentheses.
 * Null when the line has no `$(`-style substitution (e.g. the backtick form).
 */
function extractFirstCommandSubstitutionBody(line: string): string | null {
  const start = line.indexOf("$(");
  if (start === -1) return null;

  let depth = 0;
  for (let i = start + 1; i < line.length; i++) {
    const ch = line[i];
    if (ch === "(") depth++;
    else if (ch === ")") {
      depth--;
      if (depth === 0) return line.slice(start + 2, i);
    }
  }
  return null;
}

/**
 * Regex that matches command substitution `$(...)` but NOT arithmetic `$((...))`
 */
function isCommandSubstitution(text: string): boolean {
  // Reject arithmetic expansion $((... ))
  if (/\$\(\(.*\)\)/.test(text)) {
    return false;
  }

  // Match command substitution $(...)
  return /\$\([^)]*\)/.test(text);
}

/**
 * Regex that matches backtick command substitution
 */
function isBacktickSubstitution(text: string): boolean {
  return /`[^`]*`/.test(text);
}

export function detectShellMaskedCommandSubstitutionDefects(
  filePath: string,
  content: string,
): ShellSafetyDefect[] {
  if (!isShellScript(filePath, content)) {
    return [];
  }

  // Check for file-wide escape hatch
  if (hasFileWideEscapeHatchMarkerInContent(content, SHELL_SAFETY_ESCAPE_HATCH_CONFIGURATION)) {
    return [];
  }

  const defects: ShellSafetyDefect[] = [];
  const lines = content.split("\n");
  const heredocBody = computeHeredocBodyLineFlags(lines);

  for (const [i, rawLine] of lines.entries()) {
    // Heredoc bodies are printed data, not executed code — see
    // computeHeredocBodyLineFlags for the real-world templates this protects.
    if (heredocBody[i]) continue;

    const line = stripTrailingComment(rawLine);

    // NOTE: an earlier revision skipped any line containing `||` or `&&`, to quash
    // false positives. That suppressed genuine defects instead of fixing the regex:
    // `local out=$(cmd) || true` is STILL masked (the `||` tests `local`'s status,
    // which is always 0, so the handler can never fire), and `local x=$(a && b)`
    // was skipped merely for containing `&&` inside the substitution. The real fix
    // is anchoring on the declaration keyword, which is what the pattern now does.
    const declMatch = line.match(DECLARATION_WITH_SUBSTITUTION_PATTERN);
    if (!declMatch) continue;

    // `local x="$(cmd || fallback)"` — the author already handled failure INSIDE the
    // substitution, so its status is the fallback's (0) by construction and there is
    // nothing left for the declaration to mask. Five such lines live in
    // cns-remote-client; flagging them would be pedantry, not a defect report.
    //
    // The `||` must be INSIDE the parentheses. `local out=$(cmd) || true` stays
    // flagged, because there the `||` tests `local`'s status — always 0 — so the
    // handler can never fire and the failure is still swallowed.
    const substitutionBody = extractFirstCommandSubstitutionBody(line);
    if (substitutionBody?.includes("||")) continue;

    const declKeyword = declMatch[1];

    // At this point, we know:
    // - A declaration keyword (local/export/readonly/declare/typeset) is present
    // - It's directly followed by a variable name and `=`
    // - The assignment starts with `$` or `` ` ``
    // This is the masked-substitution defect.

    const statement = rawLine.trim();
    const correctedForm = `Split into two lines:\n  ${declKeyword} VAR_NAME\n  VAR_NAME=$(cmd)`;

    defects.push({
      rule: "MASKED-COMMAND-SUBSTITUTION",
      lineNumber: i + 1,
      statement,
      explanation:
        `The '${declKeyword}' keyword is itself a command, and its exit status ` +
        `(always 0) overwrites the substitution's exit status. This silently ` +
        `defeats 'set -e' errexit.`,
      correctedForm,
    });
  }

  return defects;
}

// ============================================================================
// Combined detection (both rules)
// ============================================================================

export function detectAllShellSafetyDefects(
  filePath: string,
  content: string,
): ShellSafetyDefect[] {
  const rule1Defects = detectShellStatusLossDefects(filePath, content);
  const rule2Defects = detectShellMaskedCommandSubstitutionDefects(filePath, content);

  // Merge and sort by line number
  return [...rule1Defects, ...rule2Defects].toSorted((a, b) => a.lineNumber - b.lineNumber);
}
