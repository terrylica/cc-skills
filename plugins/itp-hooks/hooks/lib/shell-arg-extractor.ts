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

export interface Heredoc {
  /** The delimiter word, without quotes. */
  readonly delimiter: string;
  /** Body text between the opening line and the terminator, newlines intact. */
  readonly body: string;
  /**
   * The path this heredoc was redirected into on its opening line — the `f` in
   * `cat > f <<EOF`. Null when the heredoc was piped, consumed by a command, or
   * redirected somewhere this parser does not recognise.
   */
  readonly redirectTarget: string | null;
}

/**
 * A heredoc opener: `<<WORD`, `<<'WORD'`, `<<"WORD"`, `<<-WORD`, `<< WORD`.
 *
 * The negative lookahead on `<` is load-bearing: `<<<` is a here-STRING, which
 * has no terminator line, and treating it as a heredoc would swallow the rest
 * of the command as a body.
 */
const HEREDOC_OPENER = /<<-?\s*(?!<)(?:'([^']+)'|"([^"]+)"|([A-Za-z_][A-Za-z0-9_]*))/g;

/** `> path` or `>> path` on the opening line (the heredoc's write target). */
const REDIRECT_TARGET = /(?:^|\s)>>?\s*("([^"]+)"|'([^']+)'|([^\s|;&<>]+))/;

/**
 * Extract EVERY heredoc in a shell command, with the file each one is
 * redirected into.
 *
 * Why this exists, precisely. A PreToolUse hook is handed a command STRING, not
 * the filesystem the command is about to produce. The dominant way an agent
 * publishes prose is:
 *
 *     cat > /tmp/body.md <<'EOF'
 *     …prose…
 *     EOF
 *     gh issue comment 8 --body-file /tmp/body.md
 *
 * At hook time `/tmp/body.md` does not exist, so a guard that reads the path
 * finds nothing and fails open. Measured 2026-08-24: the github-hard-wrap-guard
 * returned `allow` for exactly this command and a hard-wrapped 88-line comment
 * was published. Reading the heredoc body out of the command string is the only
 * way to see that text before it is written.
 *
 * Conservative by construction: a `<<WORD` with no matching terminator line is
 * not reported at all, so prose that merely MENTIONS heredoc syntax cannot
 * manufacture a phantom body.
 */
export function extractHeredocs(command: string): Heredoc[] {
  const lines = command.replace(/\r\n/g, "\n").split("\n");
  const found: Heredoc[] = [];

  let lineIndex = 0;
  while (lineIndex < lines.length) {
    const line = lines[lineIndex];
    HEREDOC_OPENER.lastIndex = 0;
    const openers = [...line.matchAll(HEREDOC_OPENER)].map((m) => m[1] ?? m[2] ?? m[3] ?? "");

    if (openers.length === 0) {
      lineIndex++;
      continue;
    }

    // A redirect on the opening line names where this heredoc will be written.
    const redirectMatch = REDIRECT_TARGET.exec(line);
    const redirectTarget = redirectMatch
      ? (redirectMatch[2] ?? redirectMatch[3] ?? redirectMatch[4] ?? null)
      : null;

    // Consume each queued delimiter's body in order, starting the line after.
    let cursor = lineIndex + 1;
    openers.forEach((delimiter, openerPosition) => {
      if (cursor > lines.length) return;
      const bodyStart = cursor;
      let terminator = -1;
      while (cursor < lines.length && terminator === -1) {
        if (lines[cursor].trim() === delimiter) terminator = cursor;
        else cursor++;
      }
      if (terminator === -1) return; // unterminated → report nothing for it
      found.push({
        delimiter,
        body: lines.slice(bodyStart, terminator).join("\n"),
        // Only the FIRST heredoc on a line receives that line's redirect; a
        // second opener feeds a different descriptor and we do not guess.
        redirectTarget: openerPosition === 0 ? redirectTarget : null,
      });
      cursor = terminator + 1;
    });
    lineIndex = cursor > lineIndex ? cursor : lineIndex + 1;
  }

  return found;
}
