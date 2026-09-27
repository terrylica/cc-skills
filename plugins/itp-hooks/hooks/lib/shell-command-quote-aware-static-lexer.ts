/**
 * Quote-aware static shell lexer — pure, dependency-free, never executes or expands anything.
 *
 * Splits a command string into simple commands (arrays of words) and collects heredoc bodies
 * separately. Consumers walk the result with shell-command-invocation-walker.ts; extracted there
 * from pkill-option-after-pattern-detector.ts on 2026-09-27.
 */

export interface Word {
  /** Shell-decoded value (quotes removed; `$…` and `$(…)` NOT expanded). */
  readonly value: string;
  /** Exact source text of the word. */
  readonly raw: string;
}

export interface HeredocBody {
  readonly commandWords: Word[];
  readonly body: string;
}

export interface LexResult {
  readonly commands: Word[][];
  readonly heredocs: HeredocBody[];
}

type FrameKind = "top" | "substitution" | "backtick";

interface Frame {
  readonly kind: FrameKind;
  words: Word[];
  value: string | null;
  start: number;
  inDoubleQuotes: boolean;
  dropNextWord: boolean;
}

interface PendingHeredoc {
  readonly commandWords: Word[];
  readonly delimiter: string;
  readonly stripLeadingTabs: boolean;
}

function newFrame(kind: FrameKind): Frame {
  return {
    kind,
    words: [],
    value: null,
    start: 0,
    inDoubleQuotes: false,
    dropNextWord: false,
  };
}

/**
 * Split a command string into simple commands (arrays of words). Handles single, double and
 * ANSI-C quotes, backslash escapes, comments, `;` `&` `|` `&&` `||` newlines and parentheses as
 * separators, `$(…)` / backticks / process substitution as nested commands, redirections (dropped,
 * together with their target), and heredocs (bodies collected separately, never lexed here).
 */
export function lexShellCommands(src: string): LexResult {
  const commands: Word[][] = [];
  const heredocs: HeredocBody[] = [];
  const pending: PendingHeredoc[] = [];
  const stack: Frame[] = [newFrame("top")];
  const n = src.length;
  let i = 0;

  const top = (): Frame => stack[stack.length - 1];

  function append(text: string): void {
    const f = top();
    if (f.value === null) {
      f.value = "";
      f.start = i;
    }
    f.value += text;
  }

  function endWord(): void {
    const f = top();
    if (f.value === null) return;
    const word: Word = { value: f.value, raw: src.slice(f.start, i) };
    f.value = null;
    if (f.dropNextWord) {
      f.dropNextWord = false;
      return;
    }
    f.words.push(word);
  }

  function endCommand(): void {
    endWord();
    const f = top();
    f.dropNextWord = false;
    if (f.words.length > 0) commands.push(f.words);
    f.words = [];
  }

  function enterNested(kind: FrameKind): void {
    // The nested command contributes an opaque placeholder to the enclosing word.
    append(kind === "backtick" ? "`…`" : "$(…)");
    stack.push(newFrame(kind));
  }

  function exitNested(): void {
    endCommand();
    if (stack.length > 1) stack.pop();
  }

  function readHeredocDelimiter(): void {
    // Positioned just after `<<`.
    let stripLeadingTabs = false;
    if (src[i] === "-") {
      stripLeadingTabs = true;
      i++;
    }
    while (i < n && (src[i] === " " || src[i] === "\t")) i++;
    let delimiter = "";
    while (i < n && !/[\s;&|<>()]/.test(src[i])) {
      const c = src[i];
      if (c === "'" || c === '"') {
        const close = src.indexOf(c, i + 1);
        const end = close === -1 ? n : close;
        delimiter += src.slice(i + 1, end);
        i = end + 1;
      } else if (c === "\\" && i + 1 < n) {
        delimiter += src[i + 1];
        i += 2;
      } else {
        delimiter += c;
        i++;
      }
    }
    if (delimiter) {
      pending.push({ commandWords: top().words, delimiter, stripLeadingTabs });
    }
  }

  function consumeHeredocBodies(): void {
    // Positioned at the start of the line after the one that introduced the heredoc(s).
    while (pending.length > 0) {
      const h = pending.shift() as PendingHeredoc;
      const lines: string[] = [];
      let terminated = false;
      while (i < n) {
        const nl = src.indexOf("\n", i);
        const lineEnd = nl === -1 ? n : nl;
        const line = src.slice(i, lineEnd);
        i = nl === -1 ? n : nl + 1;
        const candidate = h.stripLeadingTabs ? line.replace(/^\t+/, "") : line;
        if (candidate === h.delimiter) {
          terminated = true;
          break;
        }
        lines.push(line);
      }
      heredocs.push({ commandWords: h.commandWords, body: lines.join("\n") });
      if (!terminated) break;
    }
  }

  function handleRedirection(): void {
    // Positioned at `<` or `>`. A pure-digit word just before it is an fd number, not an argument.
    const f = top();
    if (f.value !== null && /^\d+$/.test(f.value)) {
      f.value = null;
    } else {
      endWord();
    }
    const c = src[i];
    i++;
    if (src[i] === c || (c === "<" && src[i] === ">") || src[i] === "|") i++;
    if (src[i] === "&") {
      // `>&2`, `2>&1`, `<&-`: duplicating an fd has no filename word.
      i++;
      while (i < n && /[0-9-]/.test(src[i])) i++;
      return;
    }
    top().dropNextWord = true;
  }

  while (i < n) {
    const f = top();
    const c = src[i];

    if (f.inDoubleQuotes) {
      if (c === "\\") {
        const next = src[i + 1];
        if (next !== undefined && '$`"\\\n'.includes(next)) {
          if (next !== "\n") append(next);
          i += 2;
        } else {
          append("\\");
          i++;
        }
        continue;
      }
      if (c === '"') {
        f.inDoubleQuotes = false;
        i++;
        continue;
      }
      if (c === "$" && src[i + 1] === "(") {
        enterNested("substitution");
        i += 2;
        continue;
      }
      if (c === "`") {
        enterNested("backtick");
        i++;
        continue;
      }
      append(c);
      i++;
      continue;
    }

    if (c === "'") {
      const close = src.indexOf("'", i + 1);
      const end = close === -1 ? n : close;
      append(src.slice(i + 1, end));
      i = end + 1;
      continue;
    }
    if (c === "$" && src[i + 1] === "'") {
      let j = i + 2;
      let text = "";
      while (j < n && src[j] !== "'") {
        if (src[j] === "\\" && j + 1 < n) {
          text += src[j + 1];
          j += 2;
        } else {
          text += src[j];
          j++;
        }
      }
      append(text);
      i = j + 1;
      continue;
    }
    if (c === '"') {
      append("");
      f.inDoubleQuotes = true;
      i++;
      continue;
    }
    if (c === "\\") {
      const next = src[i + 1];
      if (next === "\n") {
        i += 2;
        continue;
      }
      if (next !== undefined) append(next);
      i += 2;
      continue;
    }
    if (c === "#" && f.value === null) {
      const nl = src.indexOf("\n", i);
      i = nl === -1 ? n : nl;
      continue;
    }
    if (c === "$" && src[i + 1] === "(") {
      enterNested("substitution");
      i += 2;
      continue;
    }
    if (c === "`") {
      if (f.kind === "backtick") {
        exitNested();
      } else {
        enterNested("backtick");
      }
      i++;
      continue;
    }
    if ((c === "<" || c === ">") && src[i + 1] === "(") {
      // Process substitution <(…) / >(…): a nested command.
      endWord();
      stack.push(newFrame("substitution"));
      i += 2;
      continue;
    }
    if (c === "<" && src[i + 1] === "<" && src[i + 2] !== "<") {
      endWord();
      i += 2;
      readHeredocDelimiter();
      continue;
    }
    if (c === "<" && src[i + 1] === "<" && src[i + 2] === "<") {
      // Here-string: its operand is stdin, not an argument.
      endWord();
      i += 3;
      top().dropNextWord = true;
      continue;
    }
    if (c === "<" || c === ">") {
      handleRedirection();
      continue;
    }
    if (c === "&" && src[i + 1] === ">") {
      endWord();
      i += 2;
      if (src[i] === ">") i++;
      top().dropNextWord = true;
      continue;
    }
    if (c === ")") {
      if (f.kind === "substitution") {
        exitNested();
      } else {
        endCommand();
      }
      i++;
      continue;
    }
    if (c === "(" || c === ";" || c === "&" || c === "|") {
      endCommand();
      i++;
      continue;
    }
    if (c === "\n") {
      endCommand();
      i++;
      if (pending.length > 0) consumeHeredocBodies();
      continue;
    }
    if (c === " " || c === "\t" || c === "\r") {
      endWord();
      i++;
      continue;
    }
    append(c);
    i++;
  }

  while (stack.length > 1) exitNested();
  endCommand();
  return { commands, heredocs };
}
