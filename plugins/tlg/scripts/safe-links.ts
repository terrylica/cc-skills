/**
 * safe-links.ts — links in Telegram messages that end exactly where the URL ends.
 *
 * Telegram's server linkifies a bare URL greedily: measured on 2026-11-22, the
 * text `打开 github.com/login/device，用你自己的账号` was stored with a
 * MessageEntityUrl over `github.com/login/device，用你自己的账号` — the
 * full-width comma and the Chinese after it became part of the link, up to the
 * next whitespace. The same text sent with an explicit
 * `<a href="https://github.com/login/device">github.com/login/device</a>` was
 * stored with a TextUrl over exactly the URL, and the server added no Url
 * entity of its own. Greedy linkifiers elsewhere stop only at whitespace or
 * ASCII punctuation too (openai/codex#55722, NousResearch/hermes-agent#144736,
 * earendil-works/pi#10933, egoist/mygo#980, eight04/linkify-plus-plus#78).
 *
 * So every bare link is given an explicit, exact link before sending:
 * `exactLinks` (HTML in, or plain text in, HTML out) and `linkSpans` (offsets in
 * a raw text, for callers that send entities rather than HTML). A link ends at
 * the first whitespace or non-ASCII character — which covers every full-width and
 * CJK punctuation mark (U+3000–U+303F, U+FF00–U+FF65, “”‘’（）《》「」【】、。，：；！？)
 * and every ideograph — and loses trailing ASCII punctuation (.,;:!?'" and an
 * unbalanced ) ] }). URLs that really contain ideographs are not supported; send
 * them percent-encoded. `badLinks` checks what the server stored.
 *
 * Dependency-free on purpose: importable from any Bun/TS code through
 * `$(cc-plugin-root tlg)/scripts/safe-links.ts`.
 */

/** One link found in a text. Offsets are UTF-16 code units, as Telegram counts them. */
export interface LinkSpan {
  readonly offset: number;
  readonly length: number;
  /** The text as it appears (and stays visible) in the message. */
  readonly visible: string;
  /** The link target: `visible` when it has a scheme, else `https://` + `visible`. */
  readonly url: string;
}

/** A stored link entity that covers more (or other) text than its URL. */
export interface BadLink {
  readonly type: "MessageEntityUrl" | "MessageEntityTextUrl" | "MessageEntityEmail";
  readonly offset: number;
  readonly length: number;
  /** The message text the entity covers. */
  readonly text: string;
  readonly url: string;
  readonly reason: string;
}

export interface ExactLinksOptions {
  /** true: `text` is Telegram HTML (as sent with parseMode "html"); false: plain text, escaped on output. */
  readonly html: boolean;
}

// Top-level domains a bare `name.tld` (no scheme, no path, no port) must end in to count as a link,
// so file names such as `tg-cli.ts` or `README.md` are left alone. With a scheme, a path or a port,
// any alphabetic TLD counts.
const BARE_TLDS = new Set([
  "com", "org", "net", "edu", "gov", "mil", "int", "info", "biz", "io", "dev", "app", "ai", "co", "me",
  "tv", "cc", "xyz", "cloud", "page", "site", "online", "tech", "link", "email", "pro", "store", "shop",
  "ca", "us", "uk", "cn", "hk", "tw", "sg", "jp", "kr", "de", "fr", "nl", "eu", "au", "nz", "in", "ru",
]);

const SCHEME_RE = /^https?:\/\//i;
const HOST_RE = /^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+/;
const PORT_RE = /^:\d{1,5}/;
// A character that, just before a bare host, means the host is part of something else
// (a longer word, an e-mail address, a path, a file name).
const GLUED_BEFORE_RE = /[A-Za-z0-9._%+\-@/\\]/;
// Characters that may continue a URL after its host: printable ASCII minus space and the
// characters that never appear unescaped in a URL we would send.
const URL_BODY_RE = /[!#$%&'()*+,\-./0-9:;=?@A-Z[\]_a-z~]/;
const TRAILING_PUNCT = new Set([".", ",", ";", ":", "!", "?", "'", '"', "*", "_", "~"]);
const CLOSERS: Record<string, string> = { ")": "(", "]": "[", "}": "{" };
// In Telegram HTML, these entities stand for characters that end a URL.
const HTML_STOP_ENTITY_RE = /^&(?:lt|gt|quot|apos|nbsp|#0*(?:34|39|60|62|160)|#x0*(?:22|27|3c|3e|a0));/i;

function lastLabel(host: string): string {
  const dot = host.lastIndexOf(".");
  return dot === -1 ? "" : host.slice(dot + 1);
}

function count(s: string, ch: string): number {
  let n = 0;
  for (const c of s) {
    if (c === ch) {
      n += 1;
    }
  }
  return n;
}

/** Remove trailing punctuation that ends a sentence rather than the URL. */
function trimTrailing(candidate: string, minLength: number): string {
  let s = candidate;
  while (s.length > minLength) {
    const last = s[s.length - 1] ?? "";
    const opener = CLOSERS[last];
    if (TRAILING_PUNCT.has(last)) {
      s = s.slice(0, -1);
    } else if (opener !== undefined && count(s, last) > count(s, opener)) {
      s = s.slice(0, -1);
    } else if (s.endsWith("&amp;")) {
      s = s.slice(0, -"&amp;".length);
    } else {
      break;
    }
  }
  return s;
}

/** Length of the URL body starting at `start` (after the host), stopping at the first non-URL character. */
function bodyLength(text: string, start: number, html: boolean): number {
  let i = start;
  while (i < text.length) {
    const ch = text[i] ?? "";
    if (!URL_BODY_RE.test(ch)) {
      break;
    }
    if (html && ch === "&" && HTML_STOP_ENTITY_RE.test(text.slice(i))) {
      break;
    }
    i += 1;
  }
  return i - start;
}

/** The link starting at `i`, or undefined. `html`: the text is escaped HTML (affects `&` handling). */
function linkAt(text: string, i: number, html: boolean): LinkSpan | undefined {
  const prev = i > 0 ? (text[i - 1] ?? "") : "";
  if (prev !== "" && /[A-Za-z0-9]/.test(prev)) {
    return undefined;
  }
  const rest = text.slice(i);
  const scheme = SCHEME_RE.exec(rest)?.[0];
  let hostStart = i;
  if (scheme !== undefined) {
    hostStart = i + scheme.length;
  } else if (prev !== "" && GLUED_BEFORE_RE.test(prev)) {
    return undefined;
  }
  const hostMatch = HOST_RE.exec(text.slice(hostStart));
  let host = hostMatch?.[0];
  if (host === undefined) {
    // With a scheme, a single-label host (http://localhost:8787) is still a link.
    if (scheme === undefined) {
      return undefined;
    }
    host = /^[A-Za-z0-9-]+/.exec(text.slice(hostStart))?.[0];
    if (host === undefined) {
      return undefined;
    }
  }
  const tld = lastLabel(host);
  if (scheme === undefined && !/^[A-Za-z]{2,24}$/.test(tld)) {
    return undefined;
  }
  let end = hostStart + host.length;
  const port = PORT_RE.exec(text.slice(end))?.[0];
  if (port !== undefined) {
    end += port.length;
  }
  const next = text[end] ?? "";
  const hasBody = next === "/" || next === "?" || next === "#";
  if (hasBody) {
    end += bodyLength(text, end, html);
  }
  const minLength = hostStart - i + host.length + (port?.length ?? 0);
  const visible = trimTrailing(text.slice(i, end), minLength);
  const hasPath = visible.length > minLength;
  if (scheme === undefined && !hasPath && port === undefined && !BARE_TLDS.has(tld.toLowerCase())) {
    return undefined;
  }
  // A bare host glued to a following word character is not a host (e.g. `example.community-x`
  // already stopped at the hyphen rule; `a.com_b` stops here).
  const after = text[i + visible.length] ?? "";
  if (!hasPath && port === undefined && /[A-Za-z0-9_@-]/.test(after)) {
    return undefined;
  }
  return {
    offset: i,
    length: visible.length,
    visible,
    url: scheme === undefined ? `https://${visible}` : visible,
  };
}

/**
 * Every bare link in `text`, each cut where its URL ends. `html`: `text` is a Telegram-HTML text
 * segment (no tags), so `&amp;` stays inside a URL and `&lt;`/`&gt;`/`&quot;` end one.
 */
export function linkSpans(text: string, html = false): LinkSpan[] {
  const spans: LinkSpan[] = [];
  let i = 0;
  while (i < text.length) {
    const span = /[A-Za-z0-9]/.test(text[i] ?? "") ? linkAt(text, i, html) : undefined;
    if (span !== undefined) {
      spans.push(span);
      i += span.length;
    } else {
      i += 1;
    }
  }
  return spans;
}

export function escapeHtml(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function escapeAttr(text: string): string {
  return escapeHtml(text).replace(/"/g, "&quot;");
}

function anchor(span: LinkSpan, html: boolean): string {
  // In HTML input the visible text is already escaped, and `&amp;` in an attribute decodes to `&`.
  const href = html ? span.url.replace(/"/g, "&quot;") : escapeAttr(span.url);
  const visible = html ? span.visible : escapeHtml(span.visible);
  return `<a href="${href}">${visible}</a>`;
}

/** Wrap each link of one text segment; the text between links is kept (and escaped when plain). */
function linkSegment(segment: string, html: boolean): string {
  const spans = linkSpans(segment, html);
  if (spans.length === 0) {
    return html ? segment : escapeHtml(segment);
  }
  let out = "";
  let at = 0;
  for (const span of spans) {
    const between = segment.slice(at, span.offset);
    out += html ? between : escapeHtml(between);
    out += anchor(span, html);
    at = span.offset + span.length;
  }
  const tail = segment.slice(at);
  return out + (html ? tail : escapeHtml(tail));
}

// Elements whose content is never linkified: an existing link, and code.
const PROTECTED_TAGS = new Set(["a", "code", "pre"]);
const TAG_RE = /<\/?([A-Za-z][A-Za-z0-9-]*)\b[^>]*>/g;

/**
 * Return Telegram HTML in which every bare link (http(s)://… or host/path such as github.com/x,
 * t.me/x, docs.example.org/…) is an explicit `<a href="https://…">visible</a>` that ends exactly
 * where the URL ends. Text inside `<a>`, `<code>` and `<pre>` is left alone. With `{ html: false }`
 * the input is plain text and the rest of it is HTML-escaped, so the result is sent with parseMode
 * "html" and reads exactly like the input.
 */
export function exactLinks(text: string, { html }: ExactLinksOptions): string {
  if (!html) {
    return linkSegment(text, false);
  }
  let out = "";
  let at = 0;
  let protectedDepth = 0;
  for (const m of text.matchAll(TAG_RE)) {
    const index = m.index ?? 0;
    const segment = text.slice(at, index);
    out += protectedDepth > 0 ? segment : linkSegment(segment, true);
    out += m[0];
    at = index + m[0].length;
    const name = (m[1] ?? "").toLowerCase();
    if (PROTECTED_TAGS.has(name) && !m[0].endsWith("/>")) {
      protectedDepth = Math.max(0, protectedDepth + (m[0].startsWith("</") ? -1 : 1));
    }
  }
  const tail = text.slice(at);
  return out + (protectedDepth > 0 ? tail : linkSegment(tail, true));
}

/** Host of a URL or URL-shaped text, lower-cased, without scheme, port or path. */
export function hostOf(urlOrText: string): string {
  const noScheme = urlOrText.replace(/^[A-Za-z][A-Za-z0-9+.-]*:\/\//, "");
  const host = /^[^/?#:\s]*/.exec(noScheme)?.[0] ?? "";
  return host.replace(/^[^@]*@/, "").toLowerCase();
}

// A Telegram message as GramJS reads it back: text plus entities carrying className/offset/length/url.
interface EntityLike {
  readonly className?: string;
  readonly offset?: number;
  readonly length?: number;
  readonly url?: string;
}
interface MessageLike {
  readonly message?: string;
  readonly entities?: readonly EntityLike[] | null;
}

// Anything outside printable ASCII without the space (`!` U+0021 to `~` U+007E).
const NOT_URL_TEXT_RE = /[^!-~]/;

/**
 * Every MessageEntityUrl or MessageEntityTextUrl of a read-back message that covers more than its URL:
 * a Url whose text holds whitespace or a non-ASCII character (the server swallowed the following text),
 * or a TextUrl whose visible text shows a URL with a different host, or a URL plus non-ASCII text.
 * A TextUrl whose visible text is a plain label with no URL in it (`<a href="…">打开</a>`) is fine, as
 * are mention and tg:// links.
 *
 * A MessageEntityEmail is checked like a Url: the server's e-mail linkifier is greedy too. Measured on
 * 2026-11-23 (a group message, found by another harness's read-back check): an e-mail entity ran from the
 * Chinese 是 before the address to its `.com`. `relink` replaces such an entity with one over the address
 * alone (`emailSpan`); deleting and resending the message works too.
 */
export function badLinks(message: MessageLike): BadLink[] {
  const text = message.message ?? "";
  const bad: BadLink[] = [];
  for (const e of message.entities ?? []) {
    const type = e.className;
    if (type !== "MessageEntityUrl" && type !== "MessageEntityTextUrl" && type !== "MessageEntityEmail") {
      continue;
    }
    const offset = Number(e.offset ?? 0);
    const length = Number(e.length ?? 0);
    const covered = text.slice(offset, offset + length);
    const url = type === "MessageEntityTextUrl" ? String(e.url ?? "") : covered;
    let reason: string | undefined;
    if (type === "MessageEntityUrl") {
      if (NOT_URL_TEXT_RE.test(covered)) {
        reason = "the link covers whitespace or non-ASCII text after the URL";
      }
    } else if (type === "MessageEntityEmail") {
      if (NOT_URL_TEXT_RE.test(covered)) {
        reason = "the e-mail link covers whitespace or non-ASCII text next to the address";
      }
    } else if (/^https?:\/\//i.test(url)) {
      const shown = linkSpans(covered);
      const hrefHost = hostOf(url);
      const other = shown.find((s) => hostOf(s.url) !== hrefHost);
      if (other !== undefined) {
        reason = `the visible text shows ${hostOf(other.url)} but the link opens ${hrefHost}`;
      } else if (shown.length > 0 && NOT_URL_TEXT_RE.test(covered.replace(/ /g, ""))) {
        reason = "the link covers non-ASCII text next to the URL";
      }
    }
    if (reason !== undefined) {
      bad.push({ type, offset, length, text: covered, url, reason });
    }
  }
  return bad;
}

const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,24}/;

/** The address inside a text an e-mail entity covered (offsets relative to `covered`), or undefined. */
export function emailSpan(covered: string): { offset: number; length: number } | undefined {
  const m = EMAIL_RE.exec(covered);
  return m ? { offset: m.index, length: m[0].length } : undefined;
}

/** One line per bad link, for an error message. */
export function describeBadLinks(bad: readonly BadLink[]): string {
  return bad
    .map((b) => `  ${b.type} at ${b.offset}+${b.length} over ${JSON.stringify(b.text)} → ${b.url}: ${b.reason}`)
    .join("\n");
}
