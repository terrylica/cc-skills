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
 *     --account amonic-gmail                  # token base name in ~/.claude/tools/gmail-tokens/
 *     --body /path/to/body.md                 # the body text (markdown-ish; see conversion rules)
 *     --from 'Ricky Chan <rickychanbc@gmail.com>' \
 *     [--reply-to <messageId>]                # thread as a reply to this Gmail message id
 *     [--to a@b] [--cc c@d] [--subject '…']   # required unless --reply-to supplies them
 *     [--replace <draftId>]                   # delete this stale draft after creating the new one
 *
 * BODY CONVERSION (deliberately minimal + predictable, not a full markdown renderer):
 *   - Blank-line-separated blocks become paragraphs; single newlines INSIDE a block are unwrapped
 *     to spaces (this is what defeats formatter-wrapped sources).
 *   - HTML部分: paragraphs → <p>; http(s) URLs auto-linked; everything entity-escaped first.
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
  const account = get("account") ?? "amonic-gmail";
  const body = get("body");
  const from = get("from");
  if (!body || !from) {
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

/** Blank-line blocks with internal newlines unwrapped to spaces — formatter-wrap immunity. */
function paragraphs(md: string): string[] {
  return md
    .replaceAll("\r\n", "\n")
    .split(/\n{2,}/)
    .map((b) => b.trim().replaceAll(/\s*\n\s*/g, " "))
    .filter(Boolean);
}

const escapeHtml = (s: string): string => s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
const linkify = (s: string): string => s.replaceAll(/(https?:\/\/[^\s<>"()]+[^\s<>"().,;:!?])/g, '<a href="$1">$1</a>');

function toHtml(paras: string[]): string {
  const body = paras.map((p) => `<p>${linkify(escapeHtml(p))}</p>`).join("\n");
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
 * encoded-word inside an address specification: encoding `Ricky <rickychanbc@gmail.com>` wholesale
 * would produce `=?UTF-8?B?...?=` where a parser expects an addr-spec, and the message would become
 * undeliverable rather than merely ugly. Only the display-name PART of an address may be encoded,
 * which needs a real address parser — out of scope here, and unnecessary while every sender identity
 * in this repo is ASCII. If a non-ASCII display name is ever needed, encode just that token; do not
 * add address headers to this set.
 */
const FREE_TEXT_HEADERS_SAFE_TO_ENCODE = new Set(["Subject"]);

function buildMime(headers: Record<string, string>, plain: string, html: string): string {
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
  if (args.replyTo) {
    const m = await api(at, `messages/${args.replyTo}?format=metadata&metadataHeaders=Message-ID&metadataHeaders=References&metadataHeaders=Subject`);
    const hs = Object.fromEntries(((m.payload as { headers: Array<{ name: string; value: string }> }).headers ?? []).map((h) => [h.name.toLowerCase(), h.value]));
    threadId = m.threadId as string;
    inReplyTo = hs["message-id"];
    references = `${hs.references ?? ""} ${hs["message-id"] ?? ""}`.trim() || undefined;
    subject = subject ?? (hs.subject?.startsWith("Re:") ? hs.subject : `Re: ${hs.subject}`);
  }
  if (!subject) throw new Error("no --subject and no --reply-to to derive it from");
  
  const md = await Bun.file(args.body).text();
  const paras = paragraphs(md);
  const mime = buildMime(
    {
      From: args.from,
      To: args.to ?? "",
      Cc: args.cc ?? "",
      Subject: subject,
      "In-Reply-To": inReplyTo ?? "",
      References: references ?? "",
    },
    paras.join("\n\n") + "\n",
    toHtml(paras),
  );
  
  const draft = await api(at, "drafts", "POST", { message: { raw: b64url(mime), ...(threadId ? { threadId } : {}) } });
  if (args.replace) {
    await api(at, `drafts/${args.replace}`, "DELETE").catch((e: unknown) => console.error(`(stale draft ${args.replace} delete failed: ${(e as Error).message})`));
  }
  const out = { draftId: draft.id as string, threadId: ((draft.message as Record<string, unknown>)?.threadId as string) ?? threadId ?? null, account: args.account };
  console.log(JSON.stringify(out));
}
