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
  replyTo?: string;
  to?: string;
  cc?: string;
  subject?: string;
  replace?: string;
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

function buildMime(headers: Record<string, string>, plain: string, html: string): string {
  const boundary = `b${crypto.randomUUID().replaceAll("-", "")}`;
  const head = Object.entries(headers)
    .filter(([, v]) => v)
    .map(([k, v]) => `${k}: ${v}`)
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
