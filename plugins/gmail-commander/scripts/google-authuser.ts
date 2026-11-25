/**
 * google-authuser — open the Google files a draft links to in the right signed-in Google account.
 *
 * Used by gmail-draft.ts (see GOOGLE ACCOUNT LINKS in its header). A recipient who reads mail in a
 * personal Google account but must open the organisation's files in a work account clicks a Docs or
 * Drive link, lands in the personal account, and asks for access from it. Google's own web apps honour
 * an `authuser=<email>` query parameter, which opens the link in that signed-in account, so
 * `addGoogleAuthuser` adds it to every Google web-app link in the body, on the RAW body before it is
 * split into the two parts, so the html href and the plain part's `text (URL)` carry the same address.
 *
 * Deliberately self-contained (no import from gmail-draft.ts, which imports this file, and no
 * package), so it runs with bare `bun`. The body-syntax rules it shares with gmail-draft.ts are small
 * copies, named as such below.
 */

/** Copy of gmail-draft.ts QUOTE_LINE_PATTERN: a `>` quotation line. */
const QUOTE_LINE_PATTERN = /^\s{0,3}>\s?/;

/** Copy of gmail-draft.ts splitUrlFromTrailingProse: prose punctuation and an unbalanced `)` are not part of a URL. */
function splitUrlFromTrailingProse(raw: string): { url: string; tail: string } {
  let url = raw;
  let tail = "";
  const punctuation = /[.,;:!?]+$/.exec(url);
  if (punctuation) {
    tail = punctuation[0];
    url = url.slice(0, -punctuation[0].length);
  }
  while (url.endsWith(")") && (url.match(/\)/g) ?? []).length > (url.match(/\(/g) ?? []).length) {
    url = url.slice(0, -1);
    tail = `)${tail}`;
  }
  return { url, tail };
}

/** An email address as `--google-authuser` takes it: one `@`, no spaces or address punctuation, a dotted domain. */
export const GOOGLE_AUTHUSER_EMAIL =
  /^[^\s@<>()[\]\\,;:"]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$/;

/**
 * The Google web apps that honour `authuser`. `mail.google.com` is deliberately absent: a mail link
 * already pins a mailbox (`/mail/u/N/`), and rewriting it would fight that.
 */
export const GOOGLE_AUTHUSER_HOSTS: ReadonlySet<string> = new Set([
  "docs.google.com", // documents, spreadsheets, presentations, forms, drawings
  "drive.google.com",
  "sheets.google.com",
  "slides.google.com",
  "forms.google.com",
  "sites.google.com",
  "script.google.com",
  "calendar.google.com",
  "meet.google.com",
]);

/** Is `url` an http(s) address on one of GOOGLE_AUTHUSER_HOSTS? */
export function isGoogleWebAppUrl(url: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  return (parsed.protocol === "https:" || parsed.protocol === "http:") && GOOGLE_AUTHUSER_HOSTS.has(parsed.hostname.toLowerCase());
}

/**
 * `authuser=<email>` in readable form: percent-encoded, except `@`, which RFC 3986 allows in a query
 * and Google accepts, so the reader of the plain part still sees the address. `+` is encoded (`%2B`),
 * because a form decoder would read a bare `+` as a space.
 */
const authuserParam = (email: string): string => `authuser=${encodeURIComponent(email).replaceAll("%40", "@")}`;

/**
 * `url` with `authuser=<email>`: an existing `authuser` (any case of the key) is replaced in place
 * and any repeat dropped; otherwise it is appended to the query. Everything else in the query and
 * the fragment is kept byte for byte; the parameter goes before the `#`.
 */
export function withGoogleAuthuser(url: string, email: string): string {
  const hashAt = url.indexOf("#");
  const fragment = hashAt >= 0 ? url.slice(hashAt) : "";
  const beforeHash = hashAt >= 0 ? url.slice(0, hashAt) : url;
  const queryAt = beforeHash.indexOf("?");
  const base = queryAt >= 0 ? beforeHash.slice(0, queryAt) : beforeHash;
  const pairs = queryAt >= 0 ? beforeHash.slice(queryAt + 1).split("&").filter((p) => p.length > 0) : [];
  const param = authuserParam(email);
  let placed = false;
  const kept = pairs.flatMap((pair) => {
    if (pair.split("=")[0]?.toLowerCase() !== "authuser") return [pair];
    if (placed) return [];
    placed = true;
    return [param];
  });
  if (!placed) kept.push(param);
  return `${base}?${kept.join("&")}${fragment}`;
}

/** Stretches of a line that are never rewritten: code spans. */
const CODE_SPAN = /(`[^`\n]+`)/g;
/**
 * One token per match: a named link `[text](target)` (copy of gmail-draft.ts MARKDOWN_LINK_PATTERN),
 * an autolink `<https://…>`, or a bare URL (copy of gmail-draft.ts URL_SPLIT_PATTERN). The named
 * link is tried first, so the address inside one is never also matched as a bare URL.
 */
const LINK_TOKEN = /\[([^[\]\n]+)\]\(((?:[^()\s]|\([^()\s]*\))+)\)|<(https?:\/\/[^\s<>]+)>|(https?:\/\/[^\s<>"'[\]]+)/g;

/**
 * Add `authuser=<email>` to every Google web-app link in the body (see GOOGLE_AUTHUSER_HOSTS):
 * bare URLs, `<…>` autolinks and named-link targets. A named link whose text IS its address gets
 * the new address in both places, so the plain part still collapses it to one URL.
 *
 * Never touched: `>` quotation lines (quotes are verbatim), lines inside a ``` fence, code spans,
 * `mail.google.com` and every non-Google address. `links` counts the addresses that now carry the
 * parameter. Pure and deterministic.
 */
export function addGoogleAuthuser(body: string, email: string): { body: string; links: number } {
  let links = 0;
  const rewrite = (url: string): string => {
    if (!isGoogleWebAppUrl(url)) return url;
    links++;
    return withGoogleAuthuser(url, email);
  };
  let inFence = false;
  const out = body
    .split("\n")
    .map((line) => {
      if (/^\s{0,3}```/.test(line)) {
        inFence = !inFence;
        return line;
      }
      if (inFence || QUOTE_LINE_PATTERN.test(line)) return line;
      return line
        .split(CODE_SPAN)
        .map((part, index) =>
          index % 2 === 1
            ? part
            : part.replace(LINK_TOKEN, (whole, label?: string, target?: string, autolink?: string, bare?: string) => {
                if (label !== undefined && target !== undefined) {
                  const next = rewrite(target);
                  return next === target ? whole : `[${label === target ? next : label}](${next})`;
                }
                if (autolink !== undefined) return `<${rewrite(autolink)}>`;
                const { url, tail } = splitUrlFromTrailingProse(bare ?? "");
                return url ? `${rewrite(url)}${tail}` : whole;
              }),
        )
        .join("");
    })
    .join("\n");
  return { body: out, links };
}
