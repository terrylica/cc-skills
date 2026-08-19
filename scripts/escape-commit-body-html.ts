/**
 * Escape angle brackets in commit-body prose before it becomes a GitHub release body.
 *
 * WHY. GitHub renders a release body as GFM, which INTERPRETS raw HTML. A commit body is
 * plain text written by a human, so every angle bracket in it is prose or a CLI
 * placeholder — and each one is silently corrupted on the published page:
 *
 *     "generic Vec<T> type"        renders as   "generic Vec type"     <- deleted
 *     "type Foo<Bar> thing"        renders as   "type Foo thing"       <- deleted
 *     "a literal <br> here"        renders as   a real line break
 *     "compare a<b and c>d"        renders as   "compare a" + bold     <- mangled
 *     "a <details> block"          opens a collapsible section that swallows what follows
 *
 * Verified against GitHub's own /markdown API, not assumed.
 *
 * THE EVIDENCE THAT THIS IS SAFE. Every angle-bracket occurrence in the last 400 commit
 * bodies of this repo is prose or a placeholder — `<br>`, `<script>`, `<table>` discussed
 * AS TAGS, and `<uuid>`, `<path>`, `<slug>`, `<account>`, `<Command,Handler>`,
 * `<verify|probe|bench>` as syntax placeholders. NONE is intentional markup. There is
 * therefore no working HTML to break, and a great deal of silently-deleted content to
 * recover. If someone later wants real HTML in a release body, the path is a notes file
 * through `mise run release:augment`, not a commit message.
 *
 * WHAT IS DELIBERATELY NOT ESCAPED.
 *  - Anything inside a fenced code block or an inline code span. Those already render
 *    literally, and escaping them would publish a visible `&lt;`.
 *  - Markdown autolinks (`<https://…>`, `<user@host>`), which are real markdown syntax
 *    rather than HTML and would break if escaped.
 *
 * Only `<` is escaped. A bare `>` renders as itself, and escaping it would corrupt the
 * `->` arrows that fill this repo's aligned mapping tables.
 */

/** `<https://…>` / `<mailto:…>` / `<user@host>` — markdown autolinks, not HTML. */
const AUTOLINK = /^<(?:[A-Za-z][A-Za-z0-9+.-]*:[^\s<>]*|[^\s<>@]+@[^\s<>@]+)>/;

/** Escape `<` outside code spans on a single line that is not inside a fence. */
function escapeOutsideInlineCode(line: string): string {
  let out = "";
  let i = 0;
  while (i < line.length) {
    const char = line[i] as string;

    // An inline code span: copy it through verbatim, backticks and all. Uses the same
    // run-length rule as CommonMark — a span opened by N backticks closes on N backticks.
    if (char === "`") {
      let fence = 0;
      while (line[i + fence] === "`") fence++;
      const delimiter = "`".repeat(fence);
      const close = line.indexOf(delimiter, i + fence);
      if (close === -1) {
        // Unterminated: not a code span, so treat the backticks as ordinary text.
        out += delimiter;
        i += fence;
        continue;
      }
      out += line.slice(i, close + fence);
      i = close + fence;
      continue;
    }

    if (char === "<") {
      const rest = line.slice(i);
      const autolink = AUTOLINK.exec(rest);
      if (autolink) {
        out += autolink[0];
        i += autolink[0].length;
        continue;
      }
      out += "&lt;";
      i++;
      continue;
    }

    out += char;
    i++;
  }
  return out;
}

/** Escape a whole commit body, leaving fenced code blocks untouched. */
export function escapeCommitBodyHtml(body: string): string {
  if (!body) return body;
  let fenced = false;
  return body
    .split("\n")
    .map((line) => {
      if (/^\s*(```|~~~)/.test(line)) {
        fenced = !fenced;
        return line;
      }
      return fenced ? line : escapeOutsideInlineCode(line);
    })
    .join("\n");
}
