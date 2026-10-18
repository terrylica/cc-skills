/**
 * The text a `printf FORMAT [ARG …] > FILE` will write, when it can be known from the command alone.
 *
 * WHY (2026-10-17). The GitHub hard-wrap guard reads a `--body-file` before the command runs. When
 * the same command creates that file, it can read a heredoc redirected into it, but a `printf … >
 * body.md` was "a form the guard cannot parse", so writing a body with printf and publishing it in
 * one command was denied outright, however well-formed the body. A printf whose format and arguments
 * are literal text has exactly one output, so the guard can measure it like any other body.
 *
 * Deliberately small and conservative: only `%s`, `%b`, `%%` and the common backslash escapes are
 * evaluated, and any `$` or backtick outside single quotes (an expansion), `printf -v`, an append
 * (`>>`), a width/precision or any other conversion returns null. Null keeps the guard's existing
 * answer for that command (the "write first, publish second" deny), so nothing is ever widened.
 */

import { splitShellWords } from "./shell-arg-extractor.ts";

const ESCAPES: Readonly<Record<string, string>> = {
  n: "\n",
  t: "\t",
  r: "\r",
  "\\": "\\",
  '"': '"',
  "'": "'",
  a: "\u0007",
  b: "\b",
  f: "\f",
  v: "\v",
};

/** Backslash escapes of a printf format or a `%b` argument; null for anything unmodelled. */
function unescape(text: string): string | null {
  let out = "";
  for (let i = 0; i < text.length; i += 1) {
    const c = text[i]!;
    if (c !== "\\") {
      out += c;
      continue;
    }
    const next = text[i + 1];
    if (next === undefined) return null;
    const mapped = ESCAPES[next];
    if (mapped === undefined) return null; // octal, \x, \c …: not modelled
    out += mapped;
    i += 1;
  }
  return out;
}

/** printf's output for a literal format and literal arguments, or null when not modelled. */
export function evaluatePrintf(format: string, args: readonly string[]): string | null {
  let out = "";
  let argIndex = 0;
  for (let pass = 0; pass < 1000; pass += 1) {
    let consumedThisPass = 0;
    for (let i = 0; i < format.length; i += 1) {
      const c = format[i]!;
      if (c === "\\") {
        const piece = unescape(format.slice(i, i + 2));
        if (piece === null) return null;
        out += piece;
        i += 1;
        continue;
      }
      if (c !== "%") {
        out += c;
        continue;
      }
      const conversion = format[i + 1];
      i += 1;
      if (conversion === "%") {
        out += "%";
      } else if (conversion === "s") {
        out += args[argIndex] ?? "";
        argIndex += 1;
        consumedThisPass += 1;
      } else if (conversion === "b") {
        const expanded = unescape(args[argIndex] ?? "");
        if (expanded === null) return null;
        out += expanded;
        argIndex += 1;
        consumedThisPass += 1;
      } else {
        return null; // %d, %5s, %-10s …
      }
    }
    // printf re-applies the format while arguments remain, and only if the format consumes any.
    if (consumedThisPass === 0 || argIndex >= args.length) return out;
  }
  return null;
}

/** A word is literal when it carries no expansion outside single quotes. */
function isLiteralWord(raw: string): boolean {
  const outsideSingleQuotes = raw.replace(/'[^']*'/g, "");
  return !/[$`]/.test(outsideSingleQuotes);
}

/**
 * Every `printf … > path` in the command whose output is statically known, as `{ path, text }`.
 * Paths are returned exactly as written (the caller resolves them against its cwd).
 */
export function staticPrintfWrites(command: string): Array<{ path: string; text: string }> {
  const words = splitShellWords(command);
  const found: Array<{ path: string; text: string }> = [];
  let atCommandPosition = true;

  for (let i = 0; i < words.length; i += 1) {
    const word = words[i]!;
    if (word.isOperator || word.precededByNewline) atCommandPosition = true;
    if (word.isOperator) continue;
    const wasAtCommandPosition = atCommandPosition;
    atCommandPosition = false;
    if (!wasAtCommandPosition || !word.firstSegmentBare || word.value !== "printf") continue;

    const args: string[] = [];
    let target: string | null = null;
    let modelled = true;
    let j = i + 1;
    for (; j < words.length; j += 1) {
      const w = words[j]!;
      if (w.isOperator || w.precededByNewline) break;
      const raw = command.slice(w.start, w.end);
      if (w.firstSegmentBare && (w.value === ">" || w.value === ">|")) {
        const next = words[j + 1];
        if (next === undefined || next.isOperator) {
          modelled = false;
          break;
        }
        target = next.value;
        j += 1;
        continue;
      }
      if (w.firstSegmentBare && /^>\|?[^>]/.test(w.value)) {
        target = w.value.replace(/^>\|?/, "");
        continue;
      }
      if (w.firstSegmentBare && (w.value.startsWith(">>") || /^\d*[<>]/.test(w.value))) {
        modelled = false; // append or another redirection: not modelled
        continue;
      }
      if (!isLiteralWord(raw)) {
        modelled = false;
        continue;
      }
      args.push(w.value);
    }
    i = j - 1;

    if (!modelled || target === null || args.length === 0) continue;
    if (args[0] === "-v" || args[0] === "--") continue;
    const text = evaluatePrintf(args[0]!, args.slice(1));
    if (text !== null) found.push({ path: target, text });
  }
  return found;
}
