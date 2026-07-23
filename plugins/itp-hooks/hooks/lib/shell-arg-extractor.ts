/**
 * Shell command argument extractor (SSoT) — pure, dependency-free.
 *
 * One home for "pull a flag's value out of a shell command string" — the
 * pattern several PreToolUse guards re-implement. It statically parses a
 * command WITHOUT executing it: command substitution (`$(…)`), variables
 * (`$VAR`), and backticks are treated as literal text inside an argument, never
 * expanded (callers detect those separately when they need to).
 *
 * Extracted 2026-07-22 and adopted by:
 *   - gmail-body-detector        (--body / --body-file)
 *   - release-notes-…-patterns   (--notes / -n / --notes-file / -F / -m / --message)
 *   - sred-commit-guard          (-m heredoc / -F / -m "…" / -m '…')
 *
 * Design note: `readShellArg` implements *shell-correct* quote decoding (single
 * quotes literal; double quotes only unescape `" \ $ ` `` ` ``; `$'…'` ANSI-C).
 * That single decoding serves every consumer: gmail wants the decoded value
 * directly; release-notes' inputs contain no escaped quotes so decoded == raw;
 * and sred layers its own `\n`/`\t` reconstruction on top, which composes to an
 * identical result because a double-quoted `\n` stays literal here.
 */

export type ShellQuoteKind = "single" | "double" | "ansi-c" | "none";

export interface ShellArgReadResult {
  /** Shell-decoded argument value. */
  readonly value: string;
  /** Index in the source string just past the consumed argument. */
  readonly endIndex: number;
  /** Which quoting form the argument used. */
  readonly quote: ShellQuoteKind;
}

/** Escape a literal string for safe interpolation into a RegExp. */
function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Characters a backslash may escape inside a double-quoted shell string. */
const DOUBLE_QUOTE_ESCAPABLES = new Set(['"', "\\", "$", "`"]);

/**
 * Read one shell argument starting at/after `start`, skipping leading blanks.
 * Returns null when only blanks remain. Handles single/double/`$'…'`/bare
 * tokens with shell-correct escaping. Does NOT expand `$(…)`/`$VAR`/backticks —
 * they are copied verbatim into the value.
 */
export function readShellArg(s: string, start = 0): ShellArgReadResult | null {
  let i = start;
  while (i < s.length && (s[i] === " " || s[i] === "\t")) i++;
  if (i >= s.length) return null;

  // ANSI-C quoting: $'…' with C-style escapes.
  if (s[i] === "$" && s[i + 1] === "'") {
    i += 2;
    let out = "";
    while (i < s.length && s[i] !== "'") {
      if (s[i] === "\\" && i + 1 < s.length) {
        const n = s[i + 1];
        out +=
          n === "n" ? "\n" : n === "t" ? "\t" : n === "r" ? "\r" : n === "\\" ? "\\" : n === "'" ? "'" : n;
        i += 2;
        continue;
      }
      out += s[i];
      i++;
    }
    if (i < s.length) i++; // consume closing '
    return { value: out, endIndex: i, quote: "ansi-c" };
  }

  const quote = s[i];

  if (quote === '"') {
    i++;
    let out = "";
    while (i < s.length && s[i] !== '"') {
      if (s[i] === "\\" && i + 1 < s.length && DOUBLE_QUOTE_ESCAPABLES.has(s[i + 1])) {
        out += s[i + 1]; // backslash escapes ONLY " \ $ ` in double quotes
        i += 2;
        continue;
      }
      out += s[i]; // every other char (incl. a literal `\n` two-char sequence) is verbatim
      i++;
    }
    if (i < s.length) i++; // consume closing "
    return { value: out, endIndex: i, quote: "double" };
  }

  if (quote === "'") {
    i++;
    let out = "";
    while (i < s.length && s[i] !== "'") {
      out += s[i]; // single quotes are fully literal
      i++;
    }
    if (i < s.length) i++; // consume closing '
    return { value: out, endIndex: i, quote: "single" };
  }

  // Bare token: read until whitespace. Backslash is kept literal (matches the
  // `\S+` semantics the existing regex-based extractors relied on).
  let out = "";
  while (i < s.length && !/\s/.test(s[i])) {
    out += s[i];
    i++;
  }
  return { value: out, endIndex: i, quote: "none" };
}

export interface FlagValueDetailed {
  /** True when any alias appeared (even as a bare flag with no value). */
  readonly present: boolean;
  /** The decoded argument value, when the flag carried one. */
  readonly value?: string;
  /** Quoting form of the value, when present. */
  readonly quote?: ShellQuoteKind;
}

/**
 * Look up the FIRST occurrence of any alias in `aliases` (alias order = priority)
 * and return its value with quoting detail. A flag joined by `=` or whitespace
 * takes the next shell token as its value (greedily, like the prior regex — even
 * if that token looks like another flag). A flag at end-of-string, or with no
 * following token, is reported `{ present: true }` with no value.
 */
export function extractFlagValueDetailed(text: string, aliases: readonly string[]): FlagValueDetailed {
  for (const alias of aliases) {
    const esc = escapeRegExp(alias);
    const m = text.match(new RegExp(`(?:^|\\s)${esc}(=|\\s|$)`));
    if (!m) continue;
    const joiner = m[1];
    const afterJoiner = (m.index ?? 0) + m[0].length;
    if (joiner === "=") {
      const arg = readShellArg(text, afterJoiner);
      return { present: true, value: arg?.value ?? "", quote: arg?.quote };
    }
    // Whitespace- or end-joined: read the next token; none → bare flag.
    const arg = readShellArg(text, afterJoiner);
    if (arg) return { present: true, value: arg.value, quote: arg.quote };
    return { present: true };
  }
  return { present: false };
}

/** Convenience: first-occurrence value without quoting detail. */
export function extractFlagValue(
  text: string,
  aliases: readonly string[],
): { present: boolean; value?: string } {
  const d = extractFlagValueDetailed(text, aliases);
  return d.value === undefined ? { present: d.present } : { present: d.present, value: d.value };
}

/**
 * Collect the values of EVERY occurrence of any alias, in position order. Only
 * occurrences that carry a value token are collected (a bare flag is skipped),
 * matching the prior `extractAllMessageFlags` valued-only semantics.
 */
export function extractFlagValues(text: string, aliases: readonly string[]): string[] {
  const escaped = aliases.map(escapeRegExp).join("|");
  const re = new RegExp(`(?:^|\\s)(?:${escaped})(=|\\s|$)`, "g");
  const out: string[] = [];
  for (const m of text.matchAll(re)) {
    const afterJoiner = (m.index ?? 0) + m[0].length;
    const arg = readShellArg(text, afterJoiner);
    if (arg) out.push(arg.value);
  }
  return out;
}

export interface CatHeredoc {
  readonly delimiter: string;
  /** Heredoc body with one leading and one trailing newline stripped. */
  readonly body: string;
}

/**
 * Parse a `-m "$(cat <<DELIM … DELIM)"` command-substitution heredoc (quoted or
 * bare delimiter). Returns null when the command is not a (fully parseable)
 * cat-heredoc. Strips exactly one leading and one trailing newline from the body
 * — the convention git users rely on for readable multi-paragraph messages.
 */
export function extractCatHeredoc(command: string, flag = "-m"): CatHeredoc | null {
  const esc = escapeRegExp(flag);
  const m = command.match(
    new RegExp(`${esc}\\s+["']\\$\\(cat\\s+<<['"]?(\\w+)['"]?\\s*([\\s\\S]*?)\\1\\s*\\)["']`),
  );
  if (!m) return null;
  const body = m[2].replace(/^\n/, "").replace(/\n$/, "");
  return { delimiter: m[1], body };
}

/** True when the command carries a cat-heredoc that this module cannot fully parse. */
export function hasUnparseableCatHeredoc(command: string, flag = "-m"): boolean {
  const esc = escapeRegExp(flag);
  return new RegExp(`${esc}\\s+["']\\$\\(cat\\s+<<`).test(command) && extractCatHeredoc(command, flag) === null;
}
