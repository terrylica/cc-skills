#!/usr/bin/env bun
/**
 * tg-cli.ts — Telegram personal-account CLI via MTProto (GramJS).
 *
 * Ported from tg-cli.py (Telethon). The MTProto engine changed (Telethon →
 * GramJS), so the on-disk session format changed too: sessions are now GramJS
 * StringSessions at ~/.local/share/gramjs/<profile>.session (the old Telethon
 * ~/.local/share/telethon/<profile>.session files are NOT reused — each account
 * logs in once more via the non-interactive 3-step flow: send-code → sign-in).
 *
 * Credentials (Telegram API id/hash) come from 1Password at runtime, same items
 * as before — the API app is library-independent. Multi-profile via --profile.
 *
 * Function-driven + enum-driven by design (see plugin convention): Command/
 * ExitCode/EnvVar are enums and commands dispatch through an enum-keyed
 * Record<Command, Handler> table — adding a command forces a handler.
 */

// FILE-SIZE-OK — single-file CLI mirroring tg-cli.py's 22-command surface;
// splitting would scatter the GramJS client setup across files for no benefit.
// INVENTED-FALLBACK-OK — the display placeholders below are ported VERBATIM from
// tg-cli.py (the behavioural SSoT) so output is identical across the migration:
//   "Unknown" / "?"  → message sender whose entity didn't resolve (read/search)
// Listings are rendered by message-format.ts (2026-11): a non-text body shows its kind ("[photo]",
// "[service: …]", from the MessageMedia*/MessageAction* class name) instead of the old "[media/service]" / "[media]".
// Non-display `??`/`||` here are argparse-equivalent defaults (--type supergroup,
// -o ".", --about "", --search ""), not invented tokens.

import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, extname, join } from "node:path";
import process from "node:process";
import { Api, TelegramClient } from "./vendor/telegram.js";
import { Logger, LogLevel } from "./vendor/telegram.js";
import { StringSession } from "./vendor/telegram.js";
import { OP_SA_TOKEN_UNCONFIGURED_HINT, resolveOpSaToken } from "./op-sa-token.ts";
import { PROFILES_RELATIVE_PATH, unknownProfileMessage } from "./profile-hint.ts";
import { applyFooter } from "./session-footer.ts";
import { badLinks, describeBadLinks, exactLinks } from "./safe-links.ts";
import { climb, formatLine, type LineOptions, recordOf, viewOf } from "./message-format.ts";
import { editableEntities, inputUserFromPeer, relinkedEntities, withExactLinkEntities } from "./link-entities.ts";

// ── Enums ─────────────────────────────────────────────────

enum Command {
  Send = "send",
  Draft = "draft",
  SendFile = "send-file",
  Forward = "forward",
  Edit = "edit",
  Relink = "relink",
  Delete = "delete",
  Pin = "pin",
  Read = "read",
  Thread = "thread",
  Search = "search",
  MarkRead = "mark-read",
  Dialogs = "dialogs",
  Whoami = "whoami",
  FindUser = "find-user",
  Download = "download",
  Dump = "dump",
  CreateGroup = "create-group",
  Invite = "invite",
  Kick = "kick",
  Members = "members",
  CheckAuth = "check-auth",
  SendCode = "send-code",
  SignIn = "sign-in",
}

enum ExitCode {
  Ok = 0,
  Failure = 1,
  Usage = 2,
}

enum EnvVar {
  ApiId = "TELEGRAM_API_ID",
  ApiHash = "TELEGRAM_API_HASH",
  OpUuid = "TELETHON_OP_UUID",
  OpVault = "TELETHON_OP_VAULT",
}

// ── Constants ─────────────────────────────────────────────

/**
 * Profile name -> 1Password item ID. Machine-local, never committed (both the profile names and
 * the item IDs identify accounts): ~/.config/cc-skills/tlg-profiles.json, shaped
 *   { "default": "<profile>", "profiles": { "<profile>": "<1password-item-id>" } }
 * TELETHON_OP_UUID still overrides the item for one run.
 */
function loadProfiles(): { profiles: Record<string, string>; defaultProfile: string } {
  try {
    const raw = JSON.parse(readFileSync(join(homedir(), PROFILES_RELATIVE_PATH), "utf8"));
    const profiles: Record<string, string> = raw.profiles ?? {};
    return { profiles, defaultProfile: raw.default ?? Object.keys(profiles)[0] ?? "default" };
  } catch {
    return { profiles: {}, defaultProfile: "default" };
  }
}
const LOADED_PROFILES = loadProfiles();
export const PROFILES: Record<string, string> = LOADED_PROFILES.profiles;
const DEFAULT_PROFILE = LOADED_PROFILES.defaultProfile;
const SESSION_DIR = join(homedir(), ".local/share/gramjs");
const DEFAULT_OP_VAULT = "Claude Automation";

// Telegram's hard limit is 4096 post-parse chars; 3900 leaves margin for a
// "(Part i/n)" header prepended to continuation chunks.
const TELEGRAM_MAX_PLAIN_CHARS = 3900;
// A media caption's limit without Premium, and with it (Telegram's caption_length_limit_default / _premium).
const TELEGRAM_MAX_CAPTION_CHARS = 1024;
const TELEGRAM_MAX_CAPTION_CHARS_PREMIUM = 4096;

function captionTooLong(length: number, max: number): string {
  return (
    `caption is ${length} characters with the session footer; this account may send ${max}. Send the text as its ` +
    "own message (send --reply-to the file's id) or shorten the caption."
  );
}
const SPLIT_SEPARATORS = [
  "\n\n━━━━━━━━━━━━━━\n\n",
  "\n━━━━━━━━━━━━━━\n",
  "\n\n",
  "\n",
] as const;

// ── Errors ────────────────────────────────────────────────

/** Caller-fixable input problem → exit code 2. */
class UsageError extends Error {}
/** Session not authorized → exit 1 with a re-login hint. */
class AuthError extends Error {}

// ── 1Password credential resolution ───────────────────────

function opVault(): string {
  return process.env[EnvVar.OpVault] ?? DEFAULT_OP_VAULT;
}

/** Read a single field from a 1Password item, non-interactively when possible. */
function opGet(itemId: string, field: string, reveal = false): string {
  const args = ["item", "get", itemId, "--vault", opVault(), "--fields", field];
  if (reveal) {
    args.push("--reveal");
  }
  // Proxy MUST be bypassed (the OAuth proxy 502s on api.1password.com); prefer
  // a service-account token (no biometric prompt) when the user configured one —
  // see op-sa-token.ts. It goes into op's environment, never its argv.
  const env: Record<string, string> = { ...process.env } as Record<string, string>;
  delete env.HTTPS_PROXY;
  delete env.HTTP_PROXY;
  const sa = resolveOpSaToken(process.env);
  if (sa.kind === "failed") {
    throw new UsageError(`1Password service-account token: ${sa.reason}`);
  }
  if (sa.kind === "token") {
    env.OP_SERVICE_ACCOUNT_TOKEN = sa.token;
  }
  const proc = Bun.spawnSync(["op", ...args], { env, stdout: "pipe", stderr: "pipe" });
  if (proc.exitCode !== 0) {
    // Without a token `op` falls back to the 1Password app, which needs a desktop session.
    const hint = sa.kind === "unconfigured" ? ` (${OP_SA_TOKEN_UNCONFIGURED_HINT})` : "";
    throw new UsageError(
      `1Password lookup failed for '${field}' (item ${itemId}): ${proc.stderr.toString().trim()}${hint}`,
    );
  }
  return proc.stdout.toString().trim();
}

function itemForProfile(profile: string): string {
  const itemId = process.env[EnvVar.OpUuid] ?? PROFILES[profile];
  if (!itemId) {
    throw new UsageError(unknownProfileMessage(profile, Object.keys(PROFILES)));
  }
  return itemId;
}

interface Credentials {
  readonly apiId: number;
  readonly apiHash: string;
}

function getCredentials(profile: string): Credentials {
  const envId = process.env[EnvVar.ApiId];
  const envHash = process.env[EnvVar.ApiHash];
  if (envId && envHash) {
    return { apiId: Number(envId), apiHash: envHash };
  }
  const itemId = itemForProfile(profile);
  return { apiId: Number(opGet(itemId, "App ID")), apiHash: opGet(itemId, "App API Hash", true) };
}

function getPhone(profile: string): string {
  return opGet(itemForProfile(profile), "Phone Number");
}

// ── Session storage (GramJS StringSession on disk) ─────────

function sessionFile(profile: string): string {
  return join(SESSION_DIR, `${profile}.session`);
}

function loadSession(profile: string): StringSession {
  const file = sessionFile(profile);
  const saved = existsSync(file) ? readFileSync(file, "utf8").trim() : "";
  return new StringSession(saved);
}

function persistSession(profile: string, client: TelegramClient): void {
  mkdirSync(SESSION_DIR, { recursive: true });
  writeFileSync(sessionFile(profile), (client.session as StringSession).save(), { mode: 0o600 });
}

const QUIET_LOGGER = new Logger(LogLevel.NONE);

function newClient(profile: string): TelegramClient {
  const { apiId, apiHash } = getCredentials(profile);
  return new TelegramClient(loadSession(profile), apiId, apiHash, {
    connectionRetries: 5,
    baseLogger: QUIET_LOGGER,
  });
}

/** Connect and require an authorized session, or throw a re-login hint. */
export async function connectAuthed(profile: string): Promise<TelegramClient> {
  const client = newClient(profile);
  await client.connect();
  if (!(await client.checkAuthorization())) {
    await client.disconnect();
    throw new AuthError(
      `Telegram session for profile '${profile}' is not authorized.\n` +
        `Re-login:  bun tg-cli.ts send-code ${profile}   then   bun tg-cli.ts sign-in ${profile} --code <code> --hash <hash>`,
    );
  }
  return client;
}

// ── Helpers ───────────────────────────────────────────────

type Json = Record<string, unknown>;

interface RunResult {
  readonly text: string;
  readonly exitCode?: ExitCode;
}

const jsonResult = (value: unknown): RunResult => ({ text: JSON.stringify(value, null, 2) });

/** numeric string → number (chat/user id), otherwise the raw @username/phone. */
function parseEntity(value: string): string | number {
  return /^-?\d+$/.test(value) ? Number(value) : value;
}

/** Approximate Telegram's post-parse char count for an HTML message. */
function plainLen(html: string): number {
  return html
    .replace(/<[^>]+>/g, "")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&").length;
}

function effectiveLen(text: string, parseMode: string | undefined): number {
  return parseMode === "html" ? plainLen(text) : text.length;
}

function trySplitAt(
  message: string,
  separator: string,
  parseMode: string | undefined,
  maxChars: number,
): string[] | null {
  const sections = message.split(separator);
  const chunks: string[] = [];
  let current: string[] = [];
  const size = (parts: string[]): number => effectiveLen(parts.join(separator), parseMode);
  for (const section of sections) {
    if (effectiveLen(section, parseMode) > maxChars) {
      return null;
    }
    if (current.length === 0) {
      current = [section];
    } else if (size([...current, section]) <= maxChars) {
      current.push(section);
    } else {
      chunks.push(current.join(separator));
      current = [section];
    }
  }
  if (current.length > 0) {
    chunks.push(current.join(separator));
  }
  return chunks;
}

/** Split a long message into Telegram-sendable chunks, preserving formatting. */
function splitLongMessage(message: string, parseMode: string | undefined): string[] {
  if (effectiveLen(message, parseMode) <= TELEGRAM_MAX_PLAIN_CHARS) {
    return [message];
  }
  for (const sep of SPLIT_SEPARATORS) {
    if (!message.includes(sep)) {
      continue;
    }
    const chunks = trySplitAt(message, sep, parseMode, TELEGRAM_MAX_PLAIN_CHARS);
    if (chunks !== null) {
      return chunks;
    }
  }
  process.stderr.write(
    `Warning: no clean split boundary found; hard-chunking at ${TELEGRAM_MAX_PLAIN_CHARS} chars.\n`,
  );
  const out: string[] = [];
  for (let i = 0; i < message.length; i += TELEGRAM_MAX_PLAIN_CHARS) {
    out.push(message.slice(i, i + TELEGRAM_MAX_PLAIN_CHARS));
  }
  return out;
}

function annotatePart(chunk: string, index: number, total: number, parseMode: string | undefined): string {
  if (total === 1) {
    return chunk;
  }
  return parseMode === "html" ? `<i>(Part ${index}/${total})</i>\n\n${chunk}` : `(Part ${index}/${total})\n\n${chunk}`;
}

/** Append the session-reference footer (policy in session-footer.ts) unless opted out. */
function withFooter(message: string, flags: Flags): string {
  return applyFooter(message, {
    noFooter: flags.has("--no-footer"),
    context: flags.get("--context"),
  });
}

/** Text, parse mode and entities for one outgoing message, as sendMessage/sendFile/editMessage take them. */
export interface Outgoing {
  readonly message: string;
  readonly parseMode?: string;
  readonly formattingEntities?: Api.TypeMessageEntity[];
}

/**
 * Make every bare link in an outgoing text exact (safe-links.ts): Telegram's server would
 * otherwise extend a link over the full-width punctuation and CJK text after it. HTML gets an
 * explicit <a href> per link; plain text keeps the client's own parse (GramJS markdown) and gains
 * one exact TextUrl entity per link. A text with no bare link is returned unchanged.
 */
export function exactOutgoing(client: TelegramClient, text: string, mode: string | undefined): Outgoing {
  if (mode === "html") {
    return { message: exactLinks(text, { html: true }), parseMode: "html" };
  }
  const parser: any = (client as any).parseMode;
  const [raw, entities]: [string, Api.TypeMessageEntity[]] = parser ? parser.parse(text) : [text, []];
  const formattingEntities = withExactLinkEntities(raw, entities);
  return formattingEntities === undefined
    ? { message: text, ...(mode ? { parseMode: mode } : {}) }
    : { message: raw, formattingEntities };
}

/**
 * Read the messages back and describe every stored link that covers more than its URL
 * (badLinks in safe-links.ts), or return undefined when every link is exact.
 */
export async function linkProblems(client: TelegramClient, peer: unknown, ids: readonly number[]): Promise<string | undefined> {
  const back: any[] = await client.getMessages(peer as any, { ids: [...ids] });
  const lines: string[] = [];
  for (const msg of back) {
    const bad = msg ? badLinks(msg) : [];
    if (bad.length > 0) {
      lines.push(`message ${msg.id}:\n${describeBadLinks(bad)}`);
    }
  }
  return lines.length > 0 ? lines.join("\n") : undefined;
}

/** The handler's result, failed (exit 1) with the bad links on stderr when Telegram stored any. */
async function checkedResult(
  client: TelegramClient,
  peer: unknown,
  ids: readonly number[],
  result: RunResult,
): Promise<RunResult> {
  const problems = await linkProblems(client, peer, ids);
  if (problems === undefined) {
    return result;
  }
  process.stderr.write(`Error: Telegram stored a link that covers more than its URL; fix it with \`relink\`.\n${problems}\n`);
  return { ...result, exitCode: ExitCode.Failure };
}

function entityLabel(entity: any, fallback: string): string {
  return (
    entity?.title ||
    entity?.username ||
    [entity?.firstName, entity?.lastName].filter(Boolean).join(" ").trim() ||
    fallback
  );
}

/** A sender's label as listings have always printed it (first name, else title, else username): scripts match it. */
function personName(s: any, fallback = "Unknown"): string {
  return s?.firstName || s?.title || s?.username || fallback;
}

/** Resolve senders once per id (a listing repeats the same few people). */
function senderResolver(): (m: any) => Promise<{ name: string; id: number | undefined }> {
  const cache = new Map<string, string>();
  return async (m: any) => {
    const key = m?.senderId !== undefined && m?.senderId !== null ? String(m.senderId) : "";
    const id = key ? Number(key) : undefined;
    if (key && cache.has(key)) {
      return { name: cache.get(key) as string, id };
    }
    let name = "Unknown";
    try {
      name = personName(await m.getSender(), name);
    } catch {
      // sender unresolved
    }
    if (key) {
      cache.set(key, name);
    }
    return { name, id };
  };
}

function lineOptions(flags: Flags, preview: number | undefined): LineOptions {
  return { preview, utc: flags.has("--utc") };
}

function optNum(flags: Flags, name: string): number | undefined {
  const v = flags.get(name);
  if (v === undefined) {
    return undefined;
  }
  const n = Number(v);
  if (!Number.isInteger(n)) {
    throw new UsageError(`${name} needs a whole number, got "${v}"`);
  }
  return n;
}

/**
 * A count flag (--limit, --depth, --scan) as a whole number of at least 1. GramJS treats a limit of 0 or NaN as no
 * limit at all (RequestIter: `!limit ? Number.MAX_SAFE_INTEGER`), so `-n 0` or `-n abc` would walk a whole chat.
 */
function countFlag(flags: Flags, name: string, fallback: number): number {
  const n = optNum(flags, name) ?? fallback;
  if (n < 1) {
    throw new UsageError(`${name} must be at least 1, got ${n}`);
  }
  return n;
}

/** One message by id, or undefined when it is deleted or not in this chat. */
async function fetchMessage(client: TelegramClient, chat: string | number, id: number): Promise<any | undefined> {
  const r: any = await client.getMessages(chat as any, { ids: id });
  const m = Array.isArray(r) ? r[0] : r;
  return m && m.className !== "MessageEmpty" ? m : undefined;
}

// ── Arg parsing ───────────────────────────────────────────

const BOOLEAN_FLAGS = new Set([
  "--html",
  "--voice",
  "--video-note",
  "--document",
  "--unpin",
  "--silent",
  "--self-only",
  "--admins",
  "--no-media",
  "--no-footer",
  "--json",
  "--utc",
  "--replies",
]);
const FLAG_ALIASES: Record<string, string> = {
  "-c": "--caption",
  "-n": "--limit",
  "-o": "--output",
  "-p": "--profile",
};

class Flags {
  private readonly map = new Map<string, true | string | string[]>();
  set(name: string, value: true | string | string[]): void {
    this.map.set(name, value);
  }
  has(name: string): boolean {
    return this.map.get(name) === true;
  }
  get(name: string): string | undefined {
    const v = this.map.get(name);
    return typeof v === "string" ? v : undefined;
  }
  num(name: string, fallback: number): number {
    const v = this.get(name);
    return v === undefined ? fallback : Number(v);
  }
  list(name: string): string[] {
    const v = this.map.get(name);
    return Array.isArray(v) ? v : [];
  }
}

interface Parsed {
  readonly command: string | undefined;
  readonly profile: string;
  readonly pos: string[];
  readonly flags: Flags;
}

function parseArgs(argv: readonly string[]): Parsed {
  let profile = DEFAULT_PROFILE;
  let command: string | undefined;
  const pos: string[] = [];
  const flags = new Flags();
  for (let i = 0; i < argv.length; i += 1) {
    let token = argv[i] ?? "";
    // A "-" followed by digits is a negative chat id (e.g. -1004445659143 from
    // `dialogs`), not a flag — treat it as a positional.
    if (token.startsWith("-") && token !== "-" && !/^-\d+$/.test(token)) {
      token = FLAG_ALIASES[token] ?? token;
      if (token === "--profile") {
        profile = argv[++i] ?? profile;
      } else if (BOOLEAN_FLAGS.has(token)) {
        flags.set(token, true);
      } else if (token === "--users") {
        const arr: string[] = [];
        while (i + 1 < argv.length && !(argv[i + 1] ?? "").startsWith("-")) {
          arr.push(argv[++i] ?? "");
        }
        flags.set(token, arr);
      } else {
        flags.set(token, argv[++i] ?? "");
      }
    } else if (command === undefined) {
      command = token;
    } else {
      pos.push(token);
    }
  }
  return { command, profile, pos, flags };
}

function requirePos(pos: string[], index: number, name: string): string {
  const value = pos[index];
  if (value === undefined || value === "") {
    throw new UsageError(`missing required argument: ${name}`);
  }
  return value;
}

function htmlParseMode(flags: Flags): string | undefined {
  return flags.has("--html") ? "html" : undefined;
}

// ── Command handlers ──────────────────────────────────────

interface Ctx {
  readonly profile: string;
  readonly pos: string[];
  readonly flags: Flags;
}

async function handleSend({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const recipient = parseEntity(requirePos(pos, 0, "recipient"));
  const message = withFooter(requirePos(pos, 1, "message"), flags);
  const mode = htmlParseMode(flags);
  const replyTo = optNum(flags, "--reply-to");
  const client = await connectAuthed(profile);
  try {
    const chunks = splitLongMessage(message, mode);
    const ids: number[] = [];
    for (let i = 0; i < chunks.length; i += 1) {
      const body = annotatePart(chunks[i] ?? "", i + 1, chunks.length, mode);
      const sent: any = await client.sendMessage(recipient as any, {
        ...(exactOutgoing(client, body, mode) as any),
        ...(replyTo !== undefined ? { replyTo } : {}),
      });
      ids.push(Number(sent.id));
    }
    const replyNote = replyTo ? ` reply_to=${replyTo}` : "";
    return await checkedResult(client, recipient, ids, {
      text:
        chunks.length === 1
          ? `[${profile}] Sent to ${recipient}${replyNote}: id=${ids[0]}`
          : `[${profile}] Sent to ${recipient}${replyNote} in ${chunks.length} parts: ids=[${ids.join(", ")}]`,
    });
  } finally {
    await client.disconnect();
  }
}

async function handleDraft({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const recipient = parseEntity(requirePos(pos, 0, "recipient"));
  const message = requirePos(pos, 1, "message");
  const mode = htmlParseMode(flags);
  const client = await connectAuthed(profile);
  try {
    let label = String(recipient);
    try {
      label = entityLabel(await client.getEntity(recipient as any), String(recipient));
    } catch {
      // entity not resolvable; keep raw label
    }
    const me: any = await client.getMe();
    const header: any = await client.sendMessage(me.id, {
      ...(exactOutgoing(client, `<b>Draft → ${label}</b>`, "html") as any),
    });
    const ids: number[] = [Number(header.id)];
    const chunks = splitLongMessage(withFooter(message, flags), mode);
    for (let i = 0; i < chunks.length; i += 1) {
      const sent: any = await client.sendMessage(me.id, {
        ...(exactOutgoing(client, annotatePart(chunks[i] ?? "", i + 1, chunks.length, mode), mode) as any),
      });
      ids.push(Number(sent.id));
    }
    const partsNote = chunks.length > 1 ? ` in ${chunks.length} parts` : "";
    return await checkedResult(client, me.id, ids, {
      text: `[${profile}] Draft for '${label}' saved to Saved Messages${partsNote} (${message.length} chars). Open Saved Messages → copy → paste into the target chat.`,
    });
  } finally {
    await client.disconnect();
  }
}

async function handleSendFile({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const recipient = parseEntity(requirePos(pos, 0, "recipient"));
  const file = requirePos(pos, 1, "file");
  if (!existsSync(file) || !statSync(file).isFile()) {
    throw new UsageError(`file not found: ${file}`);
  }
  // Policy: a file send is a message too, so its caption carries the session footer.
  // No caption → the footer becomes the caption (unless --no-footer).
  const caption = flags.has("--no-footer")
    ? flags.get("--caption")
    : withFooter(flags.get("--caption") ?? "", flags).replace(/^\n+/, "");
  // Telegram cuts nothing silently here: it refuses a caption over its limit (MEDIA_CAPTION_TOO_LONG) after the
  // upload. Check first, with the footer counted.
  if (caption && caption.length > TELEGRAM_MAX_CAPTION_CHARS_PREMIUM) {
    throw new UsageError(captionTooLong(caption.length, TELEGRAM_MAX_CAPTION_CHARS_PREMIUM));
  }
  const client = await connectAuthed(profile);
  try {
    if (caption && caption.length > TELEGRAM_MAX_CAPTION_CHARS) {
      const me: any = await client.getMe();
      if (!me?.premium) {
        throw new UsageError(captionTooLong(caption.length, TELEGRAM_MAX_CAPTION_CHARS));
      }
    }
    const out = caption ? exactOutgoing(client, caption, undefined) : undefined;
    const sent: any = await client.sendFile(recipient as any, {
      file,
      ...(out ? { caption: out.message, ...(out.formattingEntities ? { formattingEntities: out.formattingEntities } : {}) } : {}),
      voiceNote: flags.has("--voice"),
      videoNote: flags.has("--video-note"),
      forceDocument: flags.has("--document"),
    });
    return await checkedResult(client, recipient, [Number(sent.id)], {
      text: `[${profile}] Sent file to ${recipient}: ${basename(file)}`,
    });
  } finally {
    await client.disconnect();
  }
}

async function handleForward({ profile, pos }: Ctx): Promise<RunResult> {
  const fromChat = parseEntity(requirePos(pos, 0, "from_chat"));
  const ids = requirePos(pos, 1, "message_ids").split(",").map((x) => Number(x.trim()));
  const toChat = parseEntity(requirePos(pos, 2, "to_chat"));
  const client = await connectAuthed(profile);
  try {
    await client.forwardMessages(toChat as any, { messages: ids, fromPeer: fromChat as any });
    return { text: `[${profile}] Forwarded ${ids.length} message(s) → ${toChat}` };
  } finally {
    await client.disconnect();
  }
}

async function handleEdit({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const chat = parseEntity(requirePos(pos, 0, "chat"));
  const msgId = Number(requirePos(pos, 1, "message_id"));
  const newText = requirePos(pos, 2, "new_text");
  const client = await connectAuthed(profile);
  try {
    const out = exactOutgoing(client, newText, htmlParseMode(flags));
    await client.editMessage(chat as any, {
      message: msgId,
      text: out.message,
      ...(out.parseMode ? { parseMode: out.parseMode as any } : {}),
      ...(out.formattingEntities ? { formattingEntities: out.formattingEntities } : {}),
    });
    return await checkedResult(client, chat, [msgId], { text: `[${profile}] Edited message ${msgId} in ${chat}` });
  } finally {
    await client.disconnect();
  }
}

/** Re-edit sent messages so each link covers exactly its URL; the text and other entities stay. */
async function handleRelink({ profile, pos }: Ctx): Promise<RunResult> {
  const chat = parseEntity(requirePos(pos, 0, "chat"));
  const ids = requirePos(pos, 1, "message_ids").split(",").map((x) => Number(x.trim()));
  const client = await connectAuthed(profile);
  try {
    const msgs: any[] = await client.getMessages(chat as any, { ids });
    const lines: string[] = [];
    for (let i = 0; i < ids.length; i += 1) {
      const msg = msgs[i];
      if (!msg) {
        lines.push(`${ids[i]}: not found`);
        continue;
      }
      const { entities, changed } = relinkedEntities(msg);
      if (!changed) {
        lines.push(`${msg.id}: links already exact`);
        continue;
      }
      // Read-back mentions must go out as InputMessageEntityMentionName, or the edit drops them.
      const sendable = await editableEntities(entities, async (userId) =>
        inputUserFromPeer(await client.getInputEntity(userId as any)),
      );
      await client.editMessage(chat as any, {
        message: msg.id,
        text: msg.message ?? "",
        formattingEntities: sendable,
        linkPreview: msg.media instanceof Api.MessageMediaWebPage,
      });
      lines.push(`${msg.id}: relinked`);
    }
    return await checkedResult(client, chat, ids, { text: `[${profile}] relink ${chat}\n${lines.join("\n")}` });
  } finally {
    await client.disconnect();
  }
}

async function handleDelete({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const chat = parseEntity(requirePos(pos, 0, "chat"));
  const ids = requirePos(pos, 1, "message_ids").split(",").map((x) => Number(x.trim()));
  const revoke = !flags.has("--self-only");
  const client = await connectAuthed(profile);
  try {
    await client.deleteMessages(chat as any, ids, { revoke });
    return { text: `[${profile}] Deleted ${ids.length} message(s) from ${chat} (for ${revoke ? "everyone" : "self"})` };
  } finally {
    await client.disconnect();
  }
}

async function handlePin({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const chat = parseEntity(requirePos(pos, 0, "chat"));
  const msgId = pos[1] ? Number(pos[1]) : 0;
  const client = await connectAuthed(profile);
  try {
    if (flags.has("--unpin")) {
      await client.unpinMessage(chat as any, (msgId || undefined) as any);
      return { text: `[${profile}] Unpinned ${msgId ? `message ${msgId}` : "all"} in ${chat}` };
    }
    await client.pinMessage(chat as any, msgId, { notify: !flags.has("--silent") });
    return { text: `[${profile}] Pinned message ${msgId} in ${chat}` };
  } finally {
    await client.disconnect();
  }
}

async function handleRead({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const chat = parseEntity(requirePos(pos, 0, "chat"));
  const limit = countFlag(flags, "--limit", 10);
  const preview = optNum(flags, "--preview");
  const around = optNum(flags, "--around");
  const after = optNum(flags, "--after");
  const before = optNum(flags, "--before");
  const topic = optNum(flags, "--topic");
  if (around !== undefined && (after !== undefined || before !== undefined)) {
    throw new UsageError("--around cannot be combined with --after/--before");
  }
  const client = await connectAuthed(profile);
  const name = senderResolver();
  const msgs: any[] = [];
  try {
    const base = topic !== undefined ? { replyTo: topic } : {};
    if (around !== undefined) {
      // The target and the older half (offsetId lists ids below it), then the newer half in order.
      const older = Math.floor(limit / 2) + 1;
      for await (const m of client.iterMessages(chat as any, { ...base, offsetId: around + 1, limit: older })) {
        msgs.push(m);
      }
      const newer: any[] = [];
      for await (const m of client.iterMessages(chat as any, { ...base, minId: around, reverse: true, limit: limit - older + 1 })) {
        newer.push(m);
      }
      msgs.unshift(...newer.reverse());
    } else if (after !== undefined) {
      // The first N messages after the id, shown newest first like every listing.
      for await (const m of client.iterMessages(chat as any, {
        ...base,
        minId: after,
        ...(before !== undefined ? { maxId: before } : {}),
        reverse: true,
        limit,
      })) {
        msgs.unshift(m);
      }
    } else {
      for await (const m of client.iterMessages(chat as any, { ...base, ...(before !== undefined ? { maxId: before } : {}), limit })) {
        msgs.push(m);
      }
    }
    const rows: { m: any; who: { name: string; id: number | undefined } }[] = [];
    for (const m of msgs) {
      rows.push({ m, who: await name(m) });
    }
    if (flags.has("--json")) {
      return jsonResult(rows.map(({ m, who }) => recordOf(viewOf(m, who.name, who.id))));
    }
    const opts = lineOptions(flags, preview);
    return {
      text: rows
        .map(({ m, who }) => formatLine(viewOf(m, who.name, who.id), { ...opts, mark: Number(m.id) === around ? "▶ " : undefined }))
        .join("\n"),
    };
  } finally {
    await client.disconnect();
  }
}

/**
 * thread <chat> <id>: the reply chain a message answers, oldest first, ending at the message itself (▶).
 * Climbs replyTo.replyToMsgId one message at a time and stops at the first message that replies to nothing, a
 * forum topic's root, a deleted parent, a parent in another chat, a cycle, or --depth. --replies also lists the
 * later messages that reply to the message or to one of those replies, scanning the next --scan messages.
 */
async function handleThread({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const chat = parseEntity(requirePos(pos, 0, "chat"));
  const start = Number(requirePos(pos, 1, "message_id"));
  if (!Number.isInteger(start)) {
    throw new UsageError(`message_id must be a whole number, got "${pos[1]}"`);
  }
  const depth = countFlag(flags, "--depth", 20);
  const scan = countFlag(flags, "--scan", 300);
  const preview = optNum(flags, "--preview");
  const client = await connectAuthed(profile);
  const name = senderResolver();
  try {
    const { chain, stop } = await climb(start, (id) => fetchMessage(client, chat, id), depth);
    const replies: any[] = [];
    if (flags.has("--replies") && chain.length) {
      const inThread = new Set<number>([start]);
      for await (const m of client.iterMessages(chat as any, { minId: start, reverse: true, limit: scan })) {
        const v = viewOf(m, "");
        // A reply to message N of another chat is not a reply to our N.
        if (v.replyToPeer === undefined && v.replyToId !== undefined && inThread.has(v.replyToId)) {
          inThread.add(Number((m as any).id));
          replies.push(m);
        }
      }
    }
    const ordered = [...chain].reverse();
    if (flags.has("--json")) {
      const out: unknown[] = [];
      for (const m of [...ordered, ...replies]) {
        const who = await name(m);
        out.push(recordOf(viewOf(m, who.name, who.id), { in_chain: ordered.includes(m), is_start: Number(m.id) === start }));
      }
      return jsonResult({ start, stop, messages: out });
    }
    const opts = lineOptions(flags, preview);
    if (chain.length === 0) {
      return { text: `(${stop})`, exitCode: ExitCode.Failure };
    }
    const lines = [`(chain of ${chain.length}; climbed to: ${stop})`];
    for (const [i, m] of ordered.entries()) {
      const who = await name(m);
      const mark = Number(m.id) === start ? "▶ " : undefined;
      lines.push(formatLine(viewOf(m, who.name, who.id), { ...opts, indent: "  ".repeat(i), mark }));
    }
    if (replies.length) {
      lines.push(`(replies found in the next ${scan} messages: ${replies.length})`);
      for (const m of replies) {
        const who = await name(m);
        lines.push(formatLine(viewOf(m, who.name, who.id), { ...opts, indent: `${"  ".repeat(ordered.length)}` }));
      }
    } else if (flags.has("--replies")) {
      lines.push(`(no replies in the next ${scan} messages)`);
    }
    return { text: lines.join("\n") };
  } finally {
    await client.disconnect();
  }
}

async function handleSearch({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const query = requirePos(pos, 0, "query");
  const chat = flags.get("--chat") ? parseEntity(flags.get("--chat") as string) : undefined;
  const fromUser = flags.get("--from") ? parseEntity(flags.get("--from") as string) : undefined;
  const limit = countFlag(flags, "--limit", 20);
  const preview = optNum(flags, "--preview");
  const opts = lineOptions(flags, preview);
  const client = await connectAuthed(profile);
  const lines: string[] = [];
  const records: unknown[] = [];
  try {
    if (chat !== undefined) {
      const name = senderResolver();
      for await (const m of client.iterMessages(chat as any, { search: query, limit, fromUser: fromUser as any })) {
        const who = await name(m);
        const v = viewOf(m, who.name, who.id);
        lines.push(formatLine(v, opts));
        records.push(recordOf(v));
      }
    } else {
      const res: any = await client.invoke(
        new Api.messages.SearchGlobal({
          q: query,
          filter: new Api.InputMessagesFilterEmpty(),
          minDate: 0,
          maxDate: 0,
          offsetRate: 0,
          offsetPeer: new Api.InputPeerEmpty(),
          offsetId: 0,
          limit,
        }) as any,
      );
      // The result carries the users and chats it mentions: name each message's chat and sender from them.
      const users = new Map<string, any>((res.users ?? []).map((u: any) => [String(u.id), u]));
      const chats = new Map<string, any>((res.chats ?? []).map((c: any) => [String(c.id), c]));
      const label = (peer: any): { name: string; id: string } | undefined => {
        if (!peer) {
          return undefined;
        }
        const id = String(peer.userId ?? peer.chatId ?? peer.channelId ?? "");
        const e = peer.userId !== undefined ? users.get(id) : chats.get(id);
        return { name: personName(e, id), id: peer.channelId !== undefined ? `-100${id}` : peer.chatId !== undefined ? `-${id}` : id };
      };
      // A private chat's messages carry no fromId: the sender is the account itself (out) or the chat's user.
      const me: any = (res.messages ?? []).some((m: any) => m.out && !m.fromId) ? await client.getMe() : undefined;
      for (const m of res.messages ?? []) {
        const where = label(m.peerId);
        // A channel post without fromId is the channel's own, even when this account wrote it.
        const own = m.out && m.peerId?.channelId === undefined;
        const from = label(m.fromId) ?? (own ? { name: personName(me), id: String(me?.id ?? "") } : where);
        const v = viewOf(m, from?.name ?? "Unknown", from?.id ? Number(from.id) : undefined);
        lines.push(formatLine(v, { ...opts, chat: where ? `${where.name} ${where.id}` : undefined }));
        records.push(recordOf(v, { chat_id: where ? Number(where.id) : null, chat_name: where?.name ?? null }));
      }
    }
  } finally {
    await client.disconnect();
  }
  return flags.has("--json") ? jsonResult(records) : { text: lines.join("\n") };
}

async function handleMarkRead({ profile, pos }: Ctx): Promise<RunResult> {
  const chat = parseEntity(requirePos(pos, 0, "chat"));
  const client = await connectAuthed(profile);
  try {
    await client.markAsRead(chat as any);
    return { text: `[${profile}] Marked ${chat} as read` };
  } finally {
    await client.disconnect();
  }
}

async function handleDialogs({ profile }: Ctx): Promise<RunResult> {
  const client = await connectAuthed(profile);
  const lines: string[] = [];
  try {
    for await (const dialog of client.iterDialogs({})) {
      const d: any = dialog;
      lines.push(`${String(d.name ?? "").padEnd(40)}  (id: ${d.id})`);
    }
  } finally {
    await client.disconnect();
  }
  return { text: lines.join("\n") };
}

async function handleWhoami({ profile }: Ctx): Promise<RunResult> {
  const client = await connectAuthed(profile);
  try {
    const me: any = await client.getMe();
    return jsonResult({
      profile,
      user_id: Number(me.id),
      first_name: me.firstName,
      last_name: me.lastName,
      username: me.username,
      phone: me.phone,
    });
  } finally {
    await client.disconnect();
  }
}

async function handleFindUser({ profile, pos }: Ctx): Promise<RunResult> {
  const query = requirePos(pos, 0, "query");
  const client = await connectAuthed(profile);
  try {
    const e: any = await client.getEntity(parseEntity(query) as any);
    const info: Json = { type: e.className ?? e.constructor?.name, id: Number(e.id) };
    if ("firstName" in e) {
      info.first_name = e.firstName;
      info.last_name = e.lastName;
      info.username = e.username;
      info.phone = e.phone ?? null;
      info.bot = e.bot ?? false;
    } else if ("title" in e) {
      info.title = e.title;
      info.username = e.username ?? null;
      info.participants_count = e.participantsCount ?? null;
    }
    return jsonResult(info);
  } finally {
    await client.disconnect();
  }
}

async function handleDownload({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const chat = parseEntity(requirePos(pos, 0, "chat"));
  const msgId = Number(requirePos(pos, 1, "message_id"));
  const outDir = flags.get("--output") ?? ".";
  mkdirSync(outDir, { recursive: true });
  const client = await connectAuthed(profile);
  try {
    const msgs: any = await client.getMessages(chat as any, { ids: msgId });
    const msg = Array.isArray(msgs) ? msgs[0] : msgs;
    if (!msg) {
      throw new UsageError(`message ${msgId} not found in ${chat}`);
    }
    if (!msg.media) {
      throw new UsageError(`message ${msgId} has no media`);
    }
    const path = await client.downloadMedia(msg, { outputFile: outDir });
    return { text: `[${profile}] Downloaded: ${path}` };
  } finally {
    await client.disconnect();
  }
}

function mediaExtension(media: any): string | null {
  if (media instanceof Api.MessageMediaPhoto) {
    return ".jpg";
  }
  if (media instanceof Api.MessageMediaDocument) {
    const doc: any = media.document;
    if (doc) {
      for (const attr of doc.attributes ?? []) {
        const name: string | undefined = attr.fileName;
        if (name?.includes(".")) {
          return extname(name);
        }
      }
      const mimeMap: Record<string, string> = {
        "video/mp4": ".mp4",
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/webp": ".webp",
        "audio/ogg": ".ogg",
        "application/pdf": ".pdf",
        "video/quicktime": ".mov",
        "image/gif": ".gif",
      };
      return mimeMap[doc.mimeType ?? ""] ?? ".bin";
    }
  }
  return null;
}

async function handleDump({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const chat = parseEntity(requirePos(pos, 0, "chat"));
  const outDir = requirePos(pos, 1, "output");
  const wantMedia = !flags.has("--no-media");
  // --after writes beside the full archive, never over it: messages.ndjson is rewritten on every run.
  const after = optNum(flags, "--after");
  const ndjsonPath = join(outDir, after === undefined ? "messages.ndjson" : `messages-after-${after}.ndjson`);
  const mediaDir = join(outDir, "media");
  mkdirSync(mediaDir, { recursive: true });
  const client = await connectAuthed(profile);
  const senderCache = new Map<string, any>();
  let msgCount = 0;
  let mediaCount = 0;
  let skipCount = 0;
  const records: string[] = [];
  try {
    for await (const msg of client.iterMessages(chat as any, { reverse: true, ...(after !== undefined ? { minId: after } : {}) })) {
      const m: any = msg;
      const v = viewOf(m, "");
      const ext = m.media ? mediaExtension(m.media) : null;
      const mediaFile = ext ? `${m.id}${ext}` : null;
      let sender: any = null;
      if (m.senderId) {
        const key = String(m.senderId);
        if (!senderCache.has(key)) {
          try {
            senderCache.set(key, await m.getSender());
          } catch {
            senderCache.set(key, null);
          }
        }
        const s = senderCache.get(key);
        sender = s
          ? { id: Number(s.id), name: s.title || s.firstName || "", username: s.username ?? null }
          : null;
      }
      records.push(
        JSON.stringify({
          id: m.id,
          date: m.date ? new Date(m.date * 1000).toISOString() : null,
          text: m.message ?? null,
          has_media: m.media != null,
          media_type: m.media?.className ?? null,
          media_file: mediaFile,
          views: m.views ?? null,
          forwards: m.forwards ?? null,
          reply_to_msg_id: m.replyTo?.replyToMsgId ?? null,
          // A string: album ids exceed 2^53, so a JSON number lost their last digits (before 2026-11).
          grouped_id: v.album ?? null,
          edit_date: m.editDate ? new Date(m.editDate * 1000).toISOString() : null,
          sender,
          // Added 2026-11: the parent once a forum topic's root is set aside, the quoted part of the parent,
          // a parent in another chat, the topic, a forward's origin, direction, and a service action.
          reply_parent: v.replyToId ?? null,
          quote_text: v.quote ?? null,
          reply_to_peer: v.replyToPeer ?? null,
          forum_topic_id: v.topicId ?? null,
          fwd_from: v.fwdFrom ?? null,
          out: v.out,
          action: v.action ?? null,
        }),
      );
      if (wantMedia && mediaFile) {
        const dest = join(mediaDir, mediaFile);
        if (existsSync(dest)) {
          skipCount += 1;
        } else {
          try {
            await client.downloadMedia(m, { outputFile: dest });
            mediaCount += 1;
          } catch (error) {
            process.stderr.write(`  WARN: msg ${m.id} download failed: ${String(error)}\n`);
          }
        }
      }
      msgCount += 1;
      if (msgCount % 500 === 0) {
        process.stderr.write(`  ... ${msgCount} msgs, ${mediaCount} media, ${skipCount} skipped\n`);
      }
    }
  } finally {
    await client.disconnect();
  }
  writeFileSync(ndjsonPath, records.length ? `${records.join("\n")}\n` : "");
  process.stderr.write(`Done: ${msgCount} messages, ${mediaCount} media → ${outDir}\n`);
  if (skipCount) {
    process.stderr.write(`  (${skipCount} already existed — skipped)\n`);
  }
  return { text: ndjsonPath };
}

async function handleCreateGroup({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const title = requirePos(pos, 0, "title");
  const groupType = flags.get("--type") ?? "supergroup";
  const about = flags.get("--about") ?? "";
  const users = flags.list("--users");
  const client = await connectAuthed(profile);
  try {
    if (groupType === "group") {
      const userEntities = await Promise.all(users.map((u) => client.getInputEntity(parseEntity(u) as any)));
      const result: any = await client.invoke(
        new Api.messages.CreateChat({ users: userEntities as any, title }) as any,
      );
      const chat = result.updates?.chats?.[0] ?? result.chats?.[0];
      return { text: `[${profile}] Created group '${title}' (id: ${chat?.id})` };
    }
    const isChannel = groupType === "channel";
    const result: any = await client.invoke(
      new Api.channels.CreateChannel({ title, about, broadcast: isChannel, megagroup: !isChannel }) as any,
    );
    const ch = result.chats?.[0];
    let note = `[${profile}] Created ${groupType} '${title}' (id: ${ch?.id})`;
    if (users.length > 0) {
      const userEntities = await Promise.all(users.map((u) => client.getInputEntity(parseEntity(u) as any)));
      await client.invoke(new Api.channels.InviteToChannel({ channel: ch, users: userEntities as any }) as any);
      note += `\n[${profile}] Invited ${users.length} user(s)`;
    }
    return { text: note };
  } finally {
    await client.disconnect();
  }
}

async function handleInvite({ profile, pos }: Ctx): Promise<RunResult> {
  const group = parseEntity(requirePos(pos, 0, "group"));
  const users = pos.slice(1);
  if (users.length === 0) {
    throw new UsageError("invite requires at least one user");
  }
  const client = await connectAuthed(profile);
  try {
    const entity: any = await client.getEntity(group as any);
    const userEntities = await Promise.all(users.map((u) => client.getInputEntity(parseEntity(u) as any)));
    if ("megagroup" in entity || "broadcast" in entity) {
      await client.invoke(new Api.channels.InviteToChannel({ channel: entity, users: userEntities as any }) as any);
    } else {
      for (const u of userEntities) {
        await client.invoke(new Api.messages.AddChatUser({ chatId: entity.id, userId: u as any, fwdLimit: 50 }) as any);
      }
    }
    return { text: `[${profile}] Invited ${users.length} user(s) to ${group}` };
  } finally {
    await client.disconnect();
  }
}

async function handleKick({ profile, pos }: Ctx): Promise<RunResult> {
  const group = parseEntity(requirePos(pos, 0, "group"));
  const user = requirePos(pos, 1, "user");
  const client = await connectAuthed(profile);
  try {
    await client.kickParticipant(group as any, parseEntity(user) as any);
    return { text: `[${profile}] Kicked ${user} from ${group}` };
  } finally {
    await client.disconnect();
  }
}

async function handleMembers({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const group = parseEntity(requirePos(pos, 0, "group"));
  const limit = flags.num("--limit", 200);
  const search = flags.get("--search") ?? "";
  const client = await connectAuthed(profile);
  const lines: string[] = [];
  let count = 0;
  try {
    const opts: any = { limit, search };
    if (flags.has("--admins")) {
      opts.filter = new Api.ChannelParticipantsAdmins();
    }
    for await (const user of client.iterParticipants(group as any, opts)) {
      const u: any = user;
      const p = u.participant;
      const ptype = p?.className ?? "";
      const role = ptype.includes("Admin") ? " [admin]" : ptype.includes("Creator") ? " [creator]" : "";
      const username = u.username ? ` @${u.username}` : "";
      lines.push(`${u.firstName ?? ""} ${u.lastName ?? ""}${username} (id: ${u.id})${role}`);
      count += 1;
    }
  } finally {
    await client.disconnect();
  }
  lines.push(`\n— ${count} member(s) listed`);
  return { text: lines.join("\n") };
}

async function handleCheckAuth({ profile, pos }: Ctx): Promise<RunResult> {
  profile = pos[0] ?? profile;
  const client = newClient(profile);
  await client.connect();
  try {
    const authorized = await client.checkAuthorization();
    if (authorized) {
      const me: any = await client.getMe();
      return {
        text: JSON.stringify(
          {
            authorized: true,
            profile,
            user_id: Number(me.id),
            username: me.username,
            phone: me.phone,
            session_file: sessionFile(profile),
          },
          null,
          2,
        ),
        exitCode: ExitCode.Ok,
      };
    }
    return {
      text: JSON.stringify(
        {
          authorized: false,
          profile,
          session_file: sessionFile(profile),
          action: `Run: bun tg-cli.ts send-code ${profile}`,
        },
        null,
        2,
      ),
      exitCode: ExitCode.Failure,
    };
  } finally {
    await client.disconnect();
  }
}

async function handleSendCode({ profile, pos }: Ctx): Promise<RunResult> {
  profile = pos[0] ?? profile;
  const { apiId, apiHash } = getCredentials(profile);
  const phone = getPhone(profile);
  const client = newClient(profile);
  await client.connect();
  try {
    // Guard: sending a code starts a fresh login that would overwrite an
    // existing authorized session. Refuse rather than clobber it.
    if (await client.checkAuthorization()) {
      return jsonResult({
        status: "already_authorized",
        profile,
        note: "session is already valid; send-code skipped to avoid overwriting it. Use check-auth to inspect.",
      });
    }
    const result: any = await client.sendCode({ apiId, apiHash }, phone);
    persistSession(profile, client); // keep DC + auth key for sign-in
    return jsonResult({
      status: "code_sent",
      profile,
      phone,
      phone_code_hash: result.phoneCodeHash,
      next: `bun tg-cli.ts sign-in ${profile} --code <code> --hash ${result.phoneCodeHash}`,
    });
  } finally {
    await client.disconnect();
  }
}

async function handleSignIn({ profile, pos, flags }: Ctx): Promise<RunResult> {
  profile = pos[0] ?? profile;
  const code = flags.get("--code");
  const hash = flags.get("--hash");
  if (!code || !hash) {
    throw new UsageError("sign-in requires --code <code> and --hash <phone_code_hash> (from send-code)");
  }
  const password = flags.get("--password");
  const { apiId, apiHash } = getCredentials(profile);
  const phone = getPhone(profile);
  const client = newClient(profile);
  await client.connect();
  try {
    try {
      await client.invoke(
        new Api.auth.SignIn({ phoneNumber: phone, phoneCodeHash: hash, phoneCode: code }) as any,
      );
    } catch (error) {
      if (String((error as any)?.errorMessage) === "SESSION_PASSWORD_NEEDED") {
        if (!password) {
          throw new UsageError("two-factor auth enabled — re-run sign-in with --password <your 2FA password>");
        }
        await client.signInWithPassword(
          { apiId, apiHash },
          { password: async () => password, onError: (e: Error) => { throw e; } },
        );
      } else {
        throw error;
      }
    }
    persistSession(profile, client);
    const me: any = await client.getMe();
    return jsonResult({
      authorized: true,
      profile,
      user_id: Number(me.id),
      username: me.username,
      first_name: me.firstName,
      session_file: sessionFile(profile),
    });
  } finally {
    await client.disconnect();
  }
}

/** Enum-keyed dispatch table — adding a Command forces a handler here. */
const HANDLERS: Record<Command, (ctx: Ctx) => Promise<RunResult>> = {
  [Command.Send]: handleSend,
  [Command.Draft]: handleDraft,
  [Command.SendFile]: handleSendFile,
  [Command.Forward]: handleForward,
  [Command.Edit]: handleEdit,
  [Command.Relink]: handleRelink,
  [Command.Delete]: handleDelete,
  [Command.Pin]: handlePin,
  [Command.Read]: handleRead,
  [Command.Thread]: handleThread,
  [Command.Search]: handleSearch,
  [Command.MarkRead]: handleMarkRead,
  [Command.Dialogs]: handleDialogs,
  [Command.Whoami]: handleWhoami,
  [Command.FindUser]: handleFindUser,
  [Command.Download]: handleDownload,
  [Command.Dump]: handleDump,
  [Command.CreateGroup]: handleCreateGroup,
  [Command.Invite]: handleInvite,
  [Command.Kick]: handleKick,
  [Command.Members]: handleMembers,
  [Command.CheckAuth]: handleCheckAuth,
  [Command.SendCode]: handleSendCode,
  [Command.SignIn]: handleSignIn,
};

const USAGE = `tg-cli.ts — Telegram personal-account CLI (MTProto via GramJS)

Usage: bun tg-cli.ts [-p <profile>] <command> [args]

Profiles: ${Object.keys(PROFILES).join(", ")} (default: ${DEFAULT_PROFILE})

Messaging:   send <to> <text> [--html] [--reply-to ID] | draft <to> <text> [--html]
             send-file <to> <path> [-c CAP] [--voice|--video-note|--document]
             forward <from> <ids> <to> | edit <chat> <id> <text> [--html]
             relink <chat> <ids>   (make every link in sent messages cover exactly its URL)
             delete <chat> <ids> [--self-only] | pin <chat> [id] [--unpin] [--silent]
Reading:     read <chat> [-n N] [--preview C] [--around ID | --after ID | --before ID] [--topic ID] [--json] [--utc]
             thread <chat> <id> [--depth N] [--replies] [--scan N] [--preview C] [--json] [--utc]
             search <q> [--chat C] [--from U] [-n N] [--preview C] [--json] [--utc]
             mark-read <chat> | dialogs | whoami | find-user <q>
             A listed line: [2026-11-26 11:59:51 PCT] (id:812) Name: ↩805 topic:T album:G (edited) [fwd from X] [photo] text
             ↩N = the message it replies to; a quoted part of that message follows on its own line as ❝…❞;
             times are local (--utc for UTC); "thread" climbs the ↩ chain to where the conversation began.
Media:       download <chat> <id> [-o DIR] | dump <chat> <out_dir> [--no-media] [--after ID]
Groups:      create-group <title> [--type group|supergroup|channel] [--about A] [--users ...]
             invite <group> <users...> | kick <group> <user> | members <group> [--admins] [-n N]
Auth:        check-auth | send-code | sign-in --code <c> --hash <h> [--password <pw>]
`;

function parseCommand(value: string | undefined): Command {
  for (const candidate of Object.values(Command)) {
    if (candidate === value) {
      return candidate;
    }
  }
  throw new UsageError(`unknown command "${value ?? ""}" — see: bun tg-cli.ts --help`);
}

async function main(): Promise<ExitCode> {
  const argv = process.argv.slice(2);
  if (argv.length === 0 || argv[0] === "-h" || argv[0] === "--help") {
    process.stdout.write(USAGE);
    return ExitCode.Ok;
  }
  const { command, profile, pos, flags } = parseArgs(argv);
  const resolved = parseCommand(command);
  const result = await HANDLERS[resolved]({ profile, pos, flags });
  if (result.text) {
    process.stdout.write(`${result.text}\n`);
  }
  return result.exitCode ?? ExitCode.Ok;
}

if (import.meta.main) {
  main()
    .then((code) => process.exit(code))
    .catch((error: unknown) => {
      const message = error instanceof Error ? error.message : String(error);
      process.stderr.write(`Error: ${message}\n`);
      const code = error instanceof UsageError ? ExitCode.Usage : ExitCode.Failure;
      process.exit(code);
    });
}
