#!/usr/bin/env bun
/**
 * gmail-draft — the CANONICAL Gmail draft builder (create/replace, reply-threaded, wrap-immune).
 *
 * WHY THIS EXISTS (regression 2026-07-23): Gmail's drafts API RE-ENCODES ingested raw messages and
 * HARD-FOLDS long text/plain lines at ~72-76 cols — so any draft built from prose (especially prose
 * a markdown formatter hook has wrapped) shows forced mid-paragraph line breaks in the compose
 * window. The cure is structural, not cosmetic: build the draft the way Gmail's own composer does —
 * multipart/alternative with a text/html part (source newlines never render; paragraphs reflow).
 * Enforced by the global PreToolUse guard `../hooks/gmail-draft-guard.sh` (ad-hoc drafts API calls are blocked).
 *
 * USAGE
 *   bun ~/.claude/plugins/marketplaces/cc-skills/plugins/gmail-commander/scripts/gmail-draft.ts \
 *     --account <tokenbase>                   # token base name in ~/.claude/tools/gmail-tokens/ (or GMAIL_DRAFT_ACCOUNT)
 *     --body /path/to/body.md                 # the body text (markdown-ish; see conversion rules)
 *     --from 'Jane Doe <alias@example.com>' \
 *     [--reply-to <messageId>]                # thread as a reply to this Gmail message id
 *     [--to a@b] [--cc c@d] [--subject '…']   # required unless --reply-to supplies them
 *     [--replace <draftId>]                   # delete this stale draft after creating the new one
 *
 * BODY CONVERSION (deliberately minimal + predictable, not a full markdown renderer):
 *   - Blank-line-separated blocks become paragraphs; single newlines INSIDE a block are unwrapped
 *     to spaces (this is what defeats formatter-wrapped sources).
 *   - HTML part: paragraphs → <p>; lists → <ul>; http(s) URLs auto-linked; **bold**, *italic* or _italic_, and `code`
 *     → real rich text (identifier-safe, see renderInlineEmphasis); everything entity-escaped first.
 *   - text/plain part: the same text with the emphasis markers dropped.
 *   - text/plain part: the same unwrapped paragraphs (long lines — Gmail may fold THAT part, but
 *     Gmail's editor uses the HTML part, so the visible draft reflows correctly).
 *
 * OUTPUT: one JSON line {draftId, threadId, account} — machine-readable per CLI-first doctrine.
 */

interface Args {
  account: string;
  body: string;
  from: string;
  replyTo?: string | undefined;
  // `| undefined` is REQUIRED, not noise: tsconfig sets exactOptionalPropertyTypes, under which
  // `to?: string` accepts an ABSENT key but rejects an explicit `undefined`. parseArgs() always
  // supplies every key (get() returns undefined for a missing flag), so the explicit form is the
  // honest type. Latent since the file was written; surfaced 2026-07-29.
  to?: string | undefined;
  cc?: string | undefined;
  subject?: string | undefined;
  replace?: string | undefined;
}

const get = (name: string): string | undefined => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
};

function parseArgs(): Args {
  const account = get("account") ?? process.env.GMAIL_DRAFT_ACCOUNT;
  const body = get("body");
  const from = get("from");
  if (!account || !body || !from) {
    console.error("usage: gmail-draft.ts --account <tokenbase> --body <file> --from '<Name <addr>>' [--reply-to <msgId>] [--to …] [--cc …] [--subject …] [--replace <draftId>]");
    process.exit(1);
  }
  return { account, body, from, replyTo: get("reply-to"), to: get("to"), cc: get("cc"), subject: get("subject"), replace: get("replace") };
}

const TOKENS_DIR = `${process.env.HOME}/.claude/tools/gmail-tokens`;

async function accessToken(account: string): Promise<string> {
  const tok = await Bun.file(`${TOKENS_DIR}/${account}.json`).json();
  const app = await Bun.file(`${TOKENS_DIR}/${account}.app-credentials.json`).json().catch(() => ({}));
  const clientId = tok.client_id ?? app.client_id;
  const clientSecret = tok.client_secret ?? app.client_secret;
  if (!clientId || !clientSecret || !tok.refresh_token) throw new Error(`token files for '${account}' missing client_id/client_secret/refresh_token`);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret, refresh_token: tok.refresh_token, grant_type: "refresh_token" }),
  });
  if (!res.ok) throw new Error(`token refresh failed (${res.status}): ${(await res.text()).slice(0, 200)}`);
  return ((await res.json()) as { access_token: string }).access_token;
}

async function api(at: string, path: string, method = "GET", body?: unknown): Promise<Record<string, unknown>> {
  const init: RequestInit = { method, headers: { Authorization: `Bearer ${at}`, "content-type": "application/json" } };
  if (body !== undefined) init.body = JSON.stringify(body);
  const res = await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/${path}`, init);
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${(await res.text()).slice(0, 300)}`);
  return method === "DELETE" ? {} : ((await res.json()) as Record<string, unknown>);
}

// ── body conversion ──

/**
 * A list item marker: `-`, `*`, `+`, `\u2022`, or an ordered form like `1.` `2)` `a.` `iv.`.
 *
 * Deliberately anchored and requiring trailing whitespace, so a sentence beginning "- " is a list
 * item but an em-dash aside or a negative number mid-prose is not.
 */
const LIST_ITEM_MARKER_PATTERN = /^\s{0,3}(?:[-*+\u2022]|\d{1,2}[.)]|[a-z]{1,3}[.)])\s+/i;

/** One rendered block: reflowed prose, or a list whose items must each keep their own line. */
export type BodyBlock =
  | { kind: "prose"; text: string }
  | { kind: "list"; leadIn: string | null; items: string[] };

/**
 * Split the body into blocks, unwrapping prose but PRESERVING list structure.
 *
 * WHY THIS IS NOT JUST "unwrap every newline" (regression found 2026-07-29)
 * ------------------------------------------------------------------------
 * It used to be. Every blank-line block had its internal newlines replaced with spaces, which is
 * correct and necessary for prose — it is what makes the draft immune to a formatter having
 * hard-wrapped the source. But it silently destroyed every list. A nine-item question checklist,
 * written one item per line, arrived in the recipient's inbox as a single run-on paragraph:
 *
 *     - Q1 - OWNER - Do you want... - Q2 - EITHER - "second phase"... - Q3 - EITHER - ...
 *
 * That is worse than ugly. The whole point of that checklist was to let two busy clients answer by
 * number without reading the message twice, and collapsing it removed exactly the structure that made
 * it usable. Five separate lists in one client email were affected, including the explanation of the
 * five-stage model the message is organised around.
 *
 * THE LEAD-IN CASE, which is the one that is easy to get wrong: a block may begin with a sentence and
 * then continue into a list. Classifying the block by its FIRST line alone would treat the whole thing
 * as prose and fold the items back in. So the block is split at the FIRST line matching the marker
 * pattern: everything before it reflows as prose, everything from it on renders per item. (The
 * notes-commander engine hit precisely this bug on 2026-07-27 and fixed it the same way; the rule is
 * duplicated here rather than shared because these two engines have no common package.)
 *
 * A wrapped continuation line — indented, no marker — is joined back onto its item, so a long item
 * that a formatter wrapped stays one item.
 */
export function splitBodyIntoBlocks(md: string): BodyBlock[] {
  const blocks: BodyBlock[] = [];
  for (const rawBlock of md.replaceAll("\r\n", "\n").split(/\n{2,}/)) {
    const lines = rawBlock.split("\n").filter((l) => l.trim().length > 0);
    if (lines.length === 0) continue;

    const firstMarkerIndex = lines.findIndex((l) => LIST_ITEM_MARKER_PATTERN.test(l));
    if (firstMarkerIndex === -1) {
      const text = lines.join(" ").replaceAll(/\s+/g, " ").trim();
      if (text) blocks.push({ kind: "prose", text });
      continue;
    }

    const leadInLines = lines.slice(0, firstMarkerIndex);
    const leadIn = leadInLines.join(" ").replaceAll(/\s+/g, " ").trim() || null;

    const items: string[] = [];
    for (const line of lines.slice(firstMarkerIndex)) {
      if (LIST_ITEM_MARKER_PATTERN.test(line)) {
        items.push(line.trim());
      } else if (items.length > 0) {
        // A wrapped continuation of the previous item, not a new one.
        items[items.length - 1] = `${items[items.length - 1]} ${line.trim()}`.replaceAll(/\s+/g, " ");
      }
    }
    blocks.push({ kind: "list", leadIn, items });
  }
  return blocks;
}

/** Back-compat shim: the flat paragraph list, for callers that only need prose. */
function paragraphs(md: string): string[] {
  return splitBodyIntoBlocks(md).flatMap((b) => (b.kind === "prose" ? [b.text] : b.items));
}

/** Render blocks as the text/plain part: prose reflowed, list items one per line. */
export function blocksToPlainText(blocks: BodyBlock[]): string {
  return `${blocks
    .map((b) => (b.kind === "prose" ? b.text : [b.leadIn, ...b.items].filter(Boolean).join("\n")))
    .map(stripInlineEmphasis)
    .join("\n\n")}\n`;
}

const escapeHtml = (s: string): string => s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
/**
 * A bare http(s) URL, as a SPLIT pattern so the surrounding prose can be escaped separately.
 *
 * Parentheses are deliberately ALLOWED inside the match. RFC 3986 permits them in a path, and the
 * previous character class excluded them, so `https://en.wikipedia.org/wiki/Parser_(software)` linked
 * only as far as `…/Parser` and left `_(software)` as loose text beside a broken link. Where the URL
 * genuinely ends before a paren — prose like "(see https://x.dev/a)" — the trailing paren is removed
 * afterwards by a BALANCE test, which is the only way to tell those two cases apart.
 */
const URL_SPLIT_PATTERN = /(https?:\/\/[^\s<>"'[\]]+)/g;

/** Sentence punctuation that trails a URL in prose and is not part of the address. */
const URL_TRAILING_PUNCTUATION = /[.,;:!?]+$/;

/**
 * Split a matched URL into the address and whatever prose punctuation trailed it.
 *
 * Two passes, because they interact: "…/Foo_(bar)." must lose the full stop and KEEP the paren,
 * while "(see …/a)." must lose both.
 */
function splitUrlFromTrailingProse(raw: string): { url: string; tail: string } {
  let url = raw;
  let tail = "";
  const punctuation = URL_TRAILING_PUNCTUATION.exec(url);
  if (punctuation) {
    tail = punctuation[0];
    url = url.slice(0, -punctuation[0].length);
  }
  // An unbalanced ")" closes a bracket the PROSE opened, not one the URL did.
  while (url.endsWith(")") && (url.match(/\)/g) ?? []).length > (url.match(/\(/g) ?? []).length) {
    url = url.slice(0, -1);
    tail = `)${tail}`;
  }
  return { url, tail };
}

/**
 * Inline markdown emphasis on ALREADY-ESCAPED prose: `**bold**` → <b>, `*italic*` / `_italic_` → <i>,
 * `` `code` `` → <code>.
 *
 * WHY: recipients read the HTML part, so the author's emphasis must arrive as real rich text rather
 * than as literal asterisks.
 *
 * Anchoring keeps technical prose literal: an identifier can never open or close emphasis, so
 * `snake_case_name`, `2*3*4` and `a * b` survive; code spans are lifted out first so markers inside
 * backticks stay verbatim. Same rules as notes-commander's renderMarkup.
 */
export function renderInlineEmphasis(escaped: string): string {
  const codes: string[] = [];
  let s = escaped.replace(/`([^`\n]+)`/g, (_m, c: string) => {
    codes.push(c);
    return `\uE000${codes.length - 1}\uE000`;
  });
  s = s.replace(/(^|[^\w*])\*\*(?=\S)([^*]+?)(?<=\S)\*\*(?![\w*])/g, "$1<b>$2</b>");
  s = s.replace(/(^|[^\w*])\*(?=\S)([^*]+?)(?<=\S)\*(?![\w*])/g, "$1<i>$2</i>");
  s = s.replace(/(^|[^\w])_(?=\S)([^_]+?)(?<=\S)_(?!\w)/g, "$1<i>$2</i>");
  return s.replace(/\uE000(\d+)\uE000/g, (_m, i: string) => `<code>${codes[Number(i)]}</code>`);
}

/** The text/plain twin of renderInlineEmphasis: the markers are dropped, the words kept. */
export function stripInlineEmphasis(text: string): string {
  return text
    .replace(/`([^`\n]+)`/g, "$1")
    .replace(/(^|[^\w*])\*\*(?=\S)([^*]+?)(?<=\S)\*\*(?![\w*])/g, "$1$2")
    .replace(/(^|[^\w*])\*(?=\S)([^*]+?)(?<=\S)\*(?![\w*])/g, "$1$2")
    .replace(/(^|[^\w])_(?=\S)([^_]+?)(?<=\S)_(?!\w)/g, "$1$2");
}

/**
 * Escape text and linkify bare URLs in ONE pass over the RAW string.
 *
 * Escaping first and linkifying after runs the matcher over "&amp;" and "&gt;", so a URL written
 * inside angle brackets absorbs a trailing "&gt" into its href. Splitting the raw text and escaping
 * each side separately avoids that class entirely.
 */
export function escapeAndLinkify(text: string): string {
  // Odd indices are the captured URLs; even indices are the prose between them.
  return text
    .split(URL_SPLIT_PATTERN)
    .map((part, index) => {
      if (index % 2 === 0) return renderInlineEmphasis(escapeHtml(part));
      const { url, tail } = splitUrlFromTrailingProse(part);
      if (!url) return escapeHtml(part);
      const safe = escapeHtml(url);
      return `<a href="${safe}">${safe}</a>${escapeHtml(tail)}`;
    })
    .join("");
}

/**
 * Render blocks as the text/html part.
 *
 * Lists become real `<ul><li>` so the recipient's client lays them out as a list; the leading marker
 * character is stripped because the `<li>` supplies its own bullet. Ordered markers are kept as text
 * inside the item, since the author's numbering (Q1, Q9, (a), (b)) is meaningful and must not be
 * renumbered by the client.
 */
export function blocksToHtml(blocks: BodyBlock[]): string {
  const render = (s: string): string => escapeAndLinkify(s);
  const body = blocks
    .map((b) => {
      if (b.kind === "prose") return `<p>${render(b.text)}</p>`;
      const lead = b.leadIn ? `<p>${render(b.leadIn)}</p>\n` : "";
      const items = b.items
        .map((item) => `<li>${render(item.replace(/^\s{0,3}[-*+\u2022]\s+/, ""))}</li>`)
        .join("\n");
      return `${lead}<ul>\n${items}\n</ul>`;
    })
    .join("\n");
  return `<div dir="ltr">\n${body}\n</div>`;
}

/**
 * Find forced line breaks in the rendered HTML — the defect this whole tool exists to prevent.
 *
 * WHY THIS EXISTS (2026-08-07). Every guard around this builder is PREVENTIVE: use the right tool,
 * from the right copy, with green tests. Not one of them ever looked at the draft that came out. So
 * a correct invocation was trusted and never verified, and the one failure mode the tool is named
 * for — a paragraph arriving with hard breaks mid-sentence — had no detector anywhere in the stack.
 * On 2026-08-07 a client email was staged three times with exactly that defect; each time it was
 * caught by a human reading the compose window, which is not a control.
 *
 * THE INVARIANT, from `blocksToHtml`: newlines separate TAGS (`</p>\n<ul>`, `</li>\n<li>`) and never
 * appear INSIDE a `<p>` or `<li>` text run, because prose blocks are reflowed to a single line
 * before rendering. So a newline inside a text run means the source's hard wrapping survived, and a
 * `<br>` means something injected an explicit break. Either is the bug.
 *
 * Pure and exported so the suite can exercise it in both directions without touching the network.
 */
const snippetForViolation = (s: string): string => {
  const flat = s.replace(/\n/g, "\\n");
  return flat.length > 90 ? `${flat.slice(0, 90)}…` : flat;
};

export function findForcedLineBreaksInRenderedHtml(html: string): string[] {
  const violations: string[] = [];

  if (/<br\b/i.test(html)) {
    violations.push(`explicit <br> in rendered HTML — this builder never emits one: ${snippetForViolation(/.{0,40}<br\b.{0,40}/is.exec(html)?.[0] ?? "")}`);
  }
  for (const tag of ["p", "li"] as const) {
    const re = new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`, "gi");
    for (const m of html.matchAll(re)) {
      if (m[1]?.includes("\n")) {
        violations.push(`newline inside <${tag}> — source hard-wrapping survived into the render: ${snippetForViolation(m[1])}`);
      }
    }
  }
  return violations;
}

function toHtml(paras: string[]): string {
  const body = paras.map((p) => `<p>${escapeAndLinkify(p)}</p>`).join("\n");
  return `<div dir="ltr">\n${body}\n</div>`;
}

// ── MIME (multipart/alternative, the shape Gmail's own composer produces) ──

const b64url = (s: string): string => Buffer.from(s).toString("base64url");
const b64wrap = (s: string): string => (Buffer.from(s, "utf-8").toString("base64").match(/.{1,76}/g) ?? []).join("\r\n");

/**
 * RFC 2047 encoded-word for any header value containing non-ASCII.
 *
 * WHY (regression 2026-07-29, and why the earlier body fix did not cover it):
 * RFC 5322 headers are 7-bit ASCII ONLY. The BODY of this message is already correct — it declares
 * `charset="UTF-8"` and base64-encodes, which is why body prose renders fine. The Subject header was
 * emitted RAW, so its UTF-8 bytes travelled unlabelled and Gmail rendered them as Latin-1:
 *
 *     "Charting update — privacy matter"   →   "Charting update â€" privacy matter"
 *
 * An em dash is `e2 80 94`; read as Latin-1 that is exactly `â`, `€`, `"`. Any non-ASCII character
 * hits this — em dash, curly quotes, accented names, CJK.
 *
 * This was NOT a regression of the earlier hard-fold fix. That fix addressed body WRAPPING. Subject
 * encoding is an adjacent surface on the same message that was never covered — which is the more
 * useful lesson: a message has several independently-encoded parts, and fixing one proves nothing
 * about its siblings.
 *
 * Base64 (`B`) rather than quoted-printable (`Q`) because the payload is usually punctuation-dense
 * prose where Q-encoding is barely shorter and far harder to eyeball. Encoded-words are capped at 75
 * chars each per the RFC, so long subjects are split into multiple whitespace-separated words, which
 * every mail client re-joins.
 */
export function encodeHeaderValueAsRfc2047EncodedWordIfNonAscii(headerValue: string): string {
  // UTF-8 byte length exceeds JS string length if and only if some character is outside ASCII:
  // every code point below 0x80 encodes to exactly one byte, and everything above needs two or more.
  // Preferred over a `[^\x00-\x7F]` regex, which smuggles control characters into the source.
  const containsNonAscii = Buffer.byteLength(headerValue, "utf-8") !== headerValue.length;
  if (!containsNonAscii) return headerValue;

  // 75 = RFC 2047 limit for a whole encoded-word, minus the `=?UTF-8?B?` prefix and `?=` suffix.
  const maxBase64PayloadLength = 75 - "=?UTF-8?B?".length - "?=".length;
  // Base64 expands 3 bytes -> 4 chars, so chunk the SOURCE BYTES to stay under the char budget.
  const maxSourceBytesPerWord = Math.floor(maxBase64PayloadLength / 4) * 3;

  const sourceBytes = Buffer.from(headerValue, "utf-8");
  const encodedWords: string[] = [];
  for (let offset = 0; offset < sourceBytes.length; offset += maxSourceBytesPerWord) {
    // Slicing BYTES can split a multi-byte character; Buffer.toString("base64") is byte-exact, and
    // the decoder concatenates the decoded bytes of adjacent words before interpreting them as
    // UTF-8, so a character split across two words still reassembles correctly.
    const chunk = sourceBytes.subarray(offset, offset + maxSourceBytesPerWord);
    encodedWords.push(`=?UTF-8?B?${chunk.toString("base64")}?=`);
  }
  // Adjacent encoded-words are joined with a space, which RFC 2047 defines as non-significant.
  return encodedWords.join(" ");
}

/**
 * Headers whose ENTIRE value is free text and may therefore be encoded wholesale.
 *
 * Address headers (From/To/Cc/Bcc/Reply-To) are deliberately EXCLUDED. RFC 2047 forbids an
 * encoded-word inside an address specification: encoding `Jane Doe <alias@example.com>` wholesale
 * would produce `=?UTF-8?B?...?=` where a parser expects an addr-spec, and the message would become
 * undeliverable rather than merely ugly. Only the display-name PART of an address may be encoded,
 * which needs a real address parser — out of scope here, and unnecessary while every sender identity
 * in this repo is ASCII. If a non-ASCII display name is ever needed, encode just that token; do not
 * add address headers to this set.
 */
const FREE_TEXT_HEADERS_SAFE_TO_ENCODE = new Set(["Subject"]);

/**
 * Assemble the multipart/alternative message.
 *
 * EXPORTED FOR TESTS (2026-07-30). The suite covered every piece — block splitting, plain-text
 * rendering, HTML rendering, header encoding — and never once assembled a whole message, so the two
 * defects that actually reached the client (welded list bullets, and a mojibake em-dash Subject) were
 * both caught by a human reading Gmail rather than by a test. A builder whose output is never
 * assembled in a test is a builder whose output is never checked.
 */
export function buildMime(headers: Record<string, string>, plain: string, html: string): string {
  const boundary = `b${crypto.randomUUID().replaceAll("-", "")}`;
  const head = Object.entries(headers)
    .filter(([, v]) => v)
    .map(([k, v]) => `${k}: ${FREE_TEXT_HEADERS_SAFE_TO_ENCODE.has(k) ? encodeHeaderValueAsRfc2047EncodedWordIfNonAscii(v) : v}`)
    .join("\r\n");
  return [
    head,
    "MIME-Version: 1.0",
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
    "",
    `--${boundary}`,
    'Content-Type: text/plain; charset="UTF-8"',
    "Content-Transfer-Encoding: base64",
    "",
    b64wrap(plain),
    `--${boundary}`,
    'Content-Type: text/html; charset="UTF-8"',
    "Content-Transfer-Encoding: base64",
    "",
    b64wrap(html),
    `--${boundary}--`,
    "",
  ].join("\r\n");
}

// ── round-trip verification (Layer 1: the builder verifies its own output) ──
//
// After creating a draft, immediately read it back from the Gmail API and assert that what Gmail
// reports matches what we sent. This is the strongest defense against encoding regressions because
// it checks the RESULT, not pattern-matching known bad outputs — so it catches encoding surfaces
// nobody has thought of yet, which is exactly how both the 2026-07-23 and 2026-07-29 bugs escaped.
//
// WHY THIS IS ESSENTIAL: when a message has multiple MIME parts and headers, fixing one part can
// leave sibling parts broken. The earlier 2026-07-23 fix addressed body HARD-FOLDING. The 2026-07-29
// regression was on Subject HEADER ENCODING — an adjacent surface that was never covered. A guard
// never seen to fire is not known to work.

interface VerificationFailure {
  headerName?: string;
  detail: string;
}

/**
 * Read the draft back from Gmail and assert it round-trips correctly.
 * Fail loudly and non-zero on any mismatch, naming the header or MIME part that differs.
 *
 * This is Layer 1 verification: the builder checks its own output. A round-trip mismatch
 * indicates a structural encoding bug (like Subject header mojibake, or a corrupted MIME
 * part) that might evade pattern-based checkers. This check catches regressions nobody
 * anticipated, as both 2026-07-23 and 2026-07-29 regressions did.
 */
async function assertCreatedDraftMatchesWhatWeSent(
  at: string,
  draftId: string,
  originalSubject: string,
): Promise<void> {
  // Fetch the draft we just created, fully decoded (format=full).
  //
  // NOTE the shape: the drafts endpoint returns `{ id, message: { payload } }` — the payload is
  // nested under `message`, NOT at the top level. Reading `fetchedDraft.payload` yields undefined and
  // this verifier then throws on every single draft, which is exactly what it did when first written
  // (2026-07-29): a verification layer that fails closed on correct input blocks all mail and teaches
  // people to delete it.
  const fetchedDraft = await api(at, `drafts/${draftId}?format=full`);
  const draftMessage = (fetchedDraft.message ?? {}) as Record<string, unknown>;
  const payload = draftMessage.payload as {
    headers?: Array<{ name: string; value: string }>;
    mimeType?: string;
    parts?: Array<{ mimeType?: string; body?: { data?: string } }>;
  };
  const headers = Object.fromEntries((payload.headers ?? []).map((h) => [h.name.toLowerCase(), h.value]));

  // ── verify Subject round-trips exactly ──
  // Gmail returns the Subject header as-is (either raw ASCII, or RFC 2047 encoded-word if it was sent
  // that way). It is ALWAYS safe to decode — a raw ASCII string just passes through unchanged.
  // We verify that what Gmail returns, when decoded, matches the original subject EXACTLY.
  // A mismatch indicates the subject was corrupted in transit: either our encoder is broken (returns
  // raw UTF-8 → mojibake), or the Gmail API mangled the transmission (network/API regression).
  const fetchedSubject = headers.subject ?? "";
  const decodedSubject = decodeRfc2047EncodedWordSequence(fetchedSubject);
  if (decodedSubject !== originalSubject) {
    // Report the full chain: input → sent → received → decoded.
    // This surfaces WHICH surface failed (encoding, transmission, or Gmail's re-encoding).
    throw new Error(
      `Subject round-trip FAILED:\n` +
        `  Original:    "${originalSubject}"\n` +
        `  Sent as:     (RFC 2047 encoded if needed)\n` +
        `  Gmail:       "${fetchedSubject}"\n` +
        `  Decoded:     "${decodedSubject}"`,
    );
  }

  // ── sanity-check the text/plain part is non-empty ──
  // If the MIME structure is corrupted (malformed boundary, missing part, empty body),
  // text/plain might be missing or empty. This catches structural corruption.
  const parts = (payload.parts ?? []);
  const textPlainPart = parts.find((p) => p.mimeType === "text/plain");
  if (!textPlainPart?.body?.data) {
    throw new Error(
      `MIME structure broken in draft ${draftId}: text/plain part missing or empty ` +
        `(mimeType: ${payload.mimeType}, parts: ${parts.length})`,
    );
  }

  // ── the draft must actually RENDER as reflowed paragraphs ──
  //
  // This is the detective half of the wrap guarantee. Everything else in this stack is preventive
  // (right tool, right copy, green tests), and preventive controls verify the INPUT. Until
  // 2026-08-07 nothing ever read the produced draft to confirm the one property the tool is named
  // for, so three client emails were staged with forced mid-sentence breaks and each was caught by
  // a human squinting at the compose window. Gmail's editor renders the text/html part, so that is
  // the part whose rendering has to be asserted.
  const textHtmlPart = parts.find((p) => p.mimeType === "text/html");
  if (!textHtmlPart?.body?.data) {
    throw new Error(
      `MIME structure broken in draft ${draftId}: text/html part missing or empty. Gmail's compose ` +
        `window renders this part; without it the draft falls back to text/plain, which Gmail ` +
        `hard-folds at ~72 cols — the exact defect this builder exists to prevent.`,
    );
  }
  const renderedHtml = Buffer.from(textHtmlPart.body.data, "base64url").toString("utf8");
  const forcedBreaks = findForcedLineBreaksInRenderedHtml(renderedHtml);
  if (forcedBreaks.length > 0) {
    throw new Error(
      `Rendered HTML contains ${forcedBreaks.length} forced line break(s) in draft ${draftId} — the ` +
        `recipient would see hard breaks mid-sentence:\n  ${forcedBreaks.join("\n  ")}`,
    );
  }

  // Success: the draft round-trips correctly.
  // (This function throws on any mismatch; the caller interprets silence as success.)
}

/**
 * RFC 2047 base64 encoded-word sequence decoder (shared with test suite).
 * Handles multi-word sequences by concatenating the decoded bytes before UTF-8 interpretation.
 */
function decodeRfc2047EncodedWordSequence(encoded: string): string {
  if (!encoded.includes("=?UTF-8?B?")) return encoded;
  const decodedChunks = encoded
    .split(" ")
    .map((word) => Buffer.from(word.replace(/^=\?UTF-8\?B\?/, "").replace(/\?=$/, ""), "base64"));
  return Buffer.concat(decodedChunks).toString("utf8");
}

// ── MIME validation (Layer 2: static validation before API call) ──
//
// After buildMime constructs the message, validate that when we decode what we're about to send,
// it round-trips correctly. This catches encoder bugs and MIME construction errors BEFORE they
// reach Gmail, preventing wasted API calls and stale drafts.
//
// WHY THIS MATTERS: Layer 1 (read-back verification) catches everything, but costs one API call.
// Layer 2 is cheaper (string parsing only) and prevents bad data from leaving this machine.
// Together, they form a seal on the encoder: if Layer 2 passes, we're safe to send; if Layer 1
// also passes, we're safe to use.

/**
 * Parse MIME headers from a raw MIME string and return them as a lowercase-keyed object.
 * Stops at the first blank line (which terminates the header block).
 */
function parseMimeHeaders(mimeString: string): Record<string, string> {
  const headerBlock = mimeString.split(/\r?\n\r?\n/)[0] ?? "";
  const headers: Record<string, string> = {};
  for (const line of headerBlock.split(/\r?\n/)) {
    const match = line.match(/^([^:]+):\s*(.*)$/);
    if (match) {
      const [, name, value] = match;
      headers[name.toLowerCase()] = value.trim();
    }
  }
  return headers;
}

/**
 * Validate that the MIME message we built can be decoded back to its original values.
 * This is Layer 2 verification: catch encoder and MIME construction bugs before sending.
 * Fail loud if encoding is broken, so the operator can investigate immediately.
 */
export function validateMimeBeforeUpload(mimeString: string, originalSubject: string): void {
  // Extract and validate the Subject header.
  const headers = parseMimeHeaders(mimeString);
  const subjectHeader = headers.subject ?? "";
  const decodedSubject = decodeRfc2047EncodedWordSequence(subjectHeader);

  if (decodedSubject !== originalSubject) {
    throw new Error(
      `LAYER 2 VALIDATION FAILED: Subject header encoding is broken before upload.\n` +
        `  Original:  "${originalSubject}"\n` +
        `  Header:    "${subjectHeader}"\n` +
        `  Decoded:   "${decodedSubject}"`,
    );
  }

  // Sanity-check: MIME structure should have a boundary declaration.
  if (!mimeString.includes("Content-Type: multipart/alternative; boundary=")) {
    throw new Error(
      `LAYER 2 VALIDATION FAILED: MIME structure missing multipart/alternative boundary.`,
    );
  }
}

// ── main ──
//
// Guarded so the module can be IMPORTED for unit tests. Without this, `import { … }` executed
// parseArgs() at import time and exited with a usage error — which is why the header encoder had no
// test until 2026-07-29. A script whose functions cannot be imported cannot be proven correct.
if (import.meta.main) {


  const args = parseArgs();
  const at = await accessToken(args.account);

  let threadId: string | undefined;
  let subject = args.subject;
  let inReplyTo: string | undefined;
  let references: string | undefined;
  let inheritedTo: string | undefined;
  if (args.replyTo) {
    const m = await api(
      at,
      `messages/${args.replyTo}?format=metadata&metadataHeaders=Message-ID&metadataHeaders=References&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Reply-To`,
    );
    const hs = Object.fromEntries(((m.payload as { headers: Array<{ name: string; value: string }> }).headers ?? []).map((h) => [h.name.toLowerCase(), h.value]));
    threadId = m.threadId as string;
    inReplyTo = hs["message-id"];
    references = `${hs.references ?? ""} ${hs["message-id"] ?? ""}`.trim() || undefined;
    subject = subject ?? (hs.subject?.startsWith("Re:") ? hs.subject : `Re: ${hs.subject}`);
    // A reply with no --to produced a draft addressed to NOBODY: `To` defaulted to "" and was then
    // dropped by buildMime's empty-value filter, so the operator got a clean success line and a draft
    // that could never be sent. Inherit the parent's Reply-To/From, which is what a reply means.
    inheritedTo = hs["reply-to"] ?? hs.from;
  }
  if (!subject) throw new Error("no --subject and no --reply-to to derive it from");

  const to = args.to ?? inheritedTo;
  if (!to && !args.cc) {
    throw new Error("draft would have no recipient: pass --to (or --cc), or --reply-to a message whose sender can be inherited");
  }

  const md = await Bun.file(args.body).text();
  const blocks = splitBodyIntoBlocks(md);
  const mime = buildMime(
    {
      From: args.from,
      To: to ?? "",
      Cc: args.cc ?? "",
      Subject: subject,
      "In-Reply-To": inReplyTo ?? "",
      References: references ?? "",
    },
    blocksToPlainText(blocks),
    blocksToHtml(blocks),
  );

  // ── LAYER 2: Validate the MIME before sending ──
  try {
    validateMimeBeforeUpload(mime, subject);
  } catch (e) {
    console.error((e as Error).message);
    process.exit(1);
  }

  const message = { raw: b64url(mime), ...(threadId ? { threadId } : {}) };

  // REPLACING A DRAFT: create the new one, delete the old one, then PROVE only one is left.
  //
  // The old path did the first two and swallowed a delete failure with `.catch()`, so a failed
  // delete left TWO drafts in the account and still printed a success line on stdout with exit 0.
  // For an operator whose standing rule is "everything aggregates into ONE draft, never split",
  // that is the worst available failure mode, and it is silent.
  //
  // `drafts.update` (PUT) looks like the better answer — it revises in place, so no window exists in
  // which zero or two drafts live, and the id stays stable across revisions. It was tried and
  // MEASURED against the live account on 2026-07-30, and it does not work for the case that matters:
  //
  //   standalone draft  → HTTP 200, body updated, id unchanged
  //   threaded REPLY    → HTTP 400 "Message not a draft", for all four request shapes
  //                       (message only / +threadId / +id / +id+threadId)
  //
  // Almost every client draft is a threaded reply, so PUT would fail exactly where it is needed.
  // Create-then-delete therefore stays. What changes is that the outcome is VERIFIED rather than
  // assumed: the delete failure is fatal, and afterwards the thread is listed and must contain
  // exactly one draft. The guarantee comes from the check, not from which endpoint was called.
  const draft = await api(at, "drafts", "POST", { message });

  // ── LAYER 1: Verify the draft round-trips correctly ──
  const createdDraftId = draft.id as string;
  const createdThreadId = ((draft.message as Record<string, unknown>)?.threadId as string) ?? threadId;
  try {
    await assertCreatedDraftMatchesWhatWeSent(at, createdDraftId, subject);
  } catch (e) {
    // The draft was created but round-trip verification failed. Report it clearly and exit non-zero.
    console.error(`LAYER 1 VERIFICATION FAILED on draft ${createdDraftId}:`);
    console.error((e as Error).message);
    process.exit(1);
  }

  if (args.replace) {
    // NOT swallowed. If the stale draft survives, the operator has two drafts of the same message
    // and no way to know which one they are about to send.
    try {
      await api(at, `drafts/${args.replace}`, "DELETE");
    } catch (e) {
      console.error(
        `FAILED to delete the superseded draft ${args.replace} after creating ${createdDraftId}: ${(e as Error).message}\n` +
          `TWO drafts of this message now exist. Delete ${args.replace} before sending anything.`,
      );
      process.exit(1);
    }
  }

  // ── LAYER 5 (2026-07-30): prove the one-draft invariant instead of assuming it ──
  //
  // Both steps above can report success and still leave the account in the wrong state — a delete
  // that 204s against an id that was never the live draft, or an earlier revision nobody cleaned up.
  // The only claim worth making is about what is actually there NOW, so ask.
  if (createdThreadId) {
    const listed = (await api(at, "drafts?maxResults=100")) as {
      drafts?: Array<{ id: string; message?: { threadId?: string } }>;
    };
    const inThread = (listed.drafts ?? []).filter((d) => d.message?.threadId === createdThreadId);
    if (inThread.length > 1) {
      console.error(
        `ONE-DRAFT INVARIANT VIOLATED: thread ${createdThreadId} now holds ${inThread.length} drafts ` +
          `(${inThread.map((d) => d.id).join(", ")}). Exactly one was expected — a message must not be ` +
          `split across drafts. Delete the superseded ones before sending.`,
      );
      process.exit(1);
    }
  }

  const out = {
    draftId: createdDraftId,
    threadId: createdThreadId ?? null,
    account: args.account,
    replaced: args.replace ?? null,
  };
  console.log(JSON.stringify(out));
}
