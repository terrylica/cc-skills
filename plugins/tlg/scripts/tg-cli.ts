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
//   "[media/service]" / "[media]" → a non-text message body in a listing
// Non-display `??`/`||` here are argparse-equivalent defaults (--type supergroup,
// -o ".", --about "", --search ""), not invented tokens.

import { existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, extname, join } from "node:path";
import process from "node:process";
import { Api, TelegramClient } from "telegram";
import { Logger, LogLevel } from "telegram/extensions/Logger";
import { StringSession } from "telegram/sessions";

// ── Enums ─────────────────────────────────────────────────

enum Command {
  Send = "send",
  Draft = "draft",
  SendFile = "send-file",
  Forward = "forward",
  Edit = "edit",
  Delete = "delete",
  Pin = "pin",
  Read = "read",
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

export const PROFILES: Record<string, string> = {
  eon: "iqwxow2iidycaethycub7agfmm",
  missterryli: "dk456cs3v2fjilppernryoro5a",
};
const DEFAULT_PROFILE = "eon";
const SESSION_DIR = join(homedir(), ".local/share/gramjs");
const DEFAULT_OP_VAULT = "Claude Automation";
const SA_TOKEN_FILE = join(homedir(), ".claude/.secrets/op-service-account-token");

// Telegram's hard limit is 4096 post-parse chars; 3900 leaves margin for a
// "(Part i/n)" header prepended to continuation chunks.
const TELEGRAM_MAX_PLAIN_CHARS = 3900;
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
  // the service-account token (no biometric prompt) when it is available.
  const env: Record<string, string> = { ...process.env } as Record<string, string>;
  delete env.HTTPS_PROXY;
  delete env.HTTP_PROXY;
  if (existsSync(SA_TOKEN_FILE)) {
    env.OP_SERVICE_ACCOUNT_TOKEN = readFileSync(SA_TOKEN_FILE, "utf8").trim();
  }
  const proc = Bun.spawnSync(["op", ...args], { env, stdout: "pipe", stderr: "pipe" });
  if (proc.exitCode !== 0) {
    throw new UsageError(
      `1Password lookup failed for '${field}' (item ${itemId}): ${proc.stderr.toString().trim()}`,
    );
  }
  return proc.stdout.toString().trim();
}

function itemForProfile(profile: string): string {
  const itemId = process.env[EnvVar.OpUuid] ?? PROFILES[profile];
  if (!itemId) {
    throw new UsageError(
      `unknown profile '${profile}'. Available: ${Object.keys(PROFILES).join(", ")}`,
    );
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

function fmtDate(unix: number | undefined, withSeconds = true): string {
  if (!unix) {
    return "";
  }
  const iso = new Date(unix * 1000).toISOString().replace("T", " ").replace("Z", "");
  return withSeconds ? iso.slice(0, 19) : iso.slice(0, 16);
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

function entityLabel(entity: any, fallback: string): string {
  return (
    entity?.title ||
    entity?.username ||
    [entity?.firstName, entity?.lastName].filter(Boolean).join(" ").trim() ||
    fallback
  );
}

function formatBody(text: string, previewChars: number | undefined): string {
  if (previewChars !== undefined) {
    const flat = text.replace(/\n/g, " ⏎ ");
    return flat.length > previewChars ? `${flat.slice(0, previewChars)}…` : flat;
  }
  if (!text.includes("\n")) {
    return text;
  }
  const lines = text.split("\n");
  return `${lines[0]}\n${lines.slice(1).map((l) => `    ${l}`).join("\n")}`;
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
    if (token.startsWith("-") && token !== "-") {
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
  const message = requirePos(pos, 1, "message");
  const mode = htmlParseMode(flags);
  const replyTo = flags.get("--reply-to") ? Number(flags.get("--reply-to")) : undefined;
  const client = await connectAuthed(profile);
  try {
    const chunks = splitLongMessage(message, mode);
    const ids: number[] = [];
    for (let i = 0; i < chunks.length; i += 1) {
      const body = annotatePart(chunks[i] ?? "", i + 1, chunks.length, mode);
      const sent: any = await client.sendMessage(recipient as any, {
        message: body,
        parseMode: mode as any,
        replyTo,
      });
      ids.push(Number(sent.id));
    }
    const replyNote = replyTo ? ` reply_to=${replyTo}` : "";
    return {
      text:
        chunks.length === 1
          ? `[${profile}] Sent to ${recipient}${replyNote}: id=${ids[0]}`
          : `[${profile}] Sent to ${recipient}${replyNote} in ${chunks.length} parts: ids=[${ids.join(", ")}]`,
    };
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
    await client.sendMessage(me.id, { message: `<b>Draft → ${label}</b>`, parseMode: "html" as any });
    const chunks = splitLongMessage(message, mode);
    for (let i = 0; i < chunks.length; i += 1) {
      await client.sendMessage(me.id, {
        message: annotatePart(chunks[i] ?? "", i + 1, chunks.length, mode),
        parseMode: mode as any,
      });
    }
    const partsNote = chunks.length > 1 ? ` in ${chunks.length} parts` : "";
    return {
      text: `[${profile}] Draft for '${label}' saved to Saved Messages${partsNote} (${message.length} chars). Open Saved Messages → copy → paste into the target chat.`,
    };
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
  const client = await connectAuthed(profile);
  try {
    await client.sendFile(recipient as any, {
      file,
      caption: flags.get("--caption"),
      voiceNote: flags.has("--voice"),
      videoNote: flags.has("--video-note"),
      forceDocument: flags.has("--document"),
    });
    return { text: `[${profile}] Sent file to ${recipient}: ${basename(file)}` };
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
    await client.editMessage(chat as any, { message: msgId, text: newText, parseMode: htmlParseMode(flags) as any });
    return { text: `[${profile}] Edited message ${msgId} in ${chat}` };
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
  const limit = flags.num("--limit", 10);
  const preview = flags.get("--preview") ? Number(flags.get("--preview")) : undefined;
  const client = await connectAuthed(profile);
  const lines: string[] = [];
  try {
    for await (const msg of client.iterMessages(chat as any, { limit })) {
      const m: any = msg;
      let name = "Unknown";
      try {
        const sender: any = await m.getSender();
        name = sender?.firstName || sender?.title || sender?.username || "Unknown";
      } catch {
        // sender unresolved
      }
      const text = formatBody(m.message || "[media/service]", preview);
      lines.push(`[${fmtDate(m.date)}] (id:${m.id}) ${name}: ${text}`);
    }
  } finally {
    await client.disconnect();
  }
  return { text: lines.join("\n") };
}

async function handleSearch({ profile, pos, flags }: Ctx): Promise<RunResult> {
  const query = requirePos(pos, 0, "query");
  const chat = flags.get("--chat") ? parseEntity(flags.get("--chat") as string) : undefined;
  const fromUser = flags.get("--from") ? parseEntity(flags.get("--from") as string) : undefined;
  const limit = flags.num("--limit", 20);
  const preview = flags.get("--preview") ? Number(flags.get("--preview")) : undefined;
  const client = await connectAuthed(profile);
  const lines: string[] = [];
  try {
    if (chat !== undefined) {
      for await (const msg of client.iterMessages(chat as any, { search: query, limit, fromUser: fromUser as any })) {
        const m: any = msg;
        let name = "?";
        try {
          const s: any = await m.getSender();
          name = s?.firstName || s?.title || s?.username || "?";
        } catch {
          // ignore
        }
        lines.push(`[${fmtDate(m.date, false)}] (id:${m.id}) ${name}: ${formatBody(m.message || "[media]", preview)}`);
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
      for (const m of res.messages ?? []) {
        lines.push(`[${fmtDate(m.date, false)}] (id:${m.id}): ${formatBody(m.message || "[media]", preview)}`);
      }
    }
  } finally {
    await client.disconnect();
  }
  return { text: lines.join("\n") };
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
  const ndjsonPath = join(outDir, "messages.ndjson");
  const mediaDir = join(outDir, "media");
  mkdirSync(mediaDir, { recursive: true });
  const client = await connectAuthed(profile);
  const senderCache = new Map<string, any>();
  let msgCount = 0;
  let mediaCount = 0;
  let skipCount = 0;
  const records: string[] = [];
  try {
    for await (const msg of client.iterMessages(chat as any, { reverse: true })) {
      const m: any = msg;
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
          grouped_id: m.groupedId ? Number(m.groupedId) : null,
          edit_date: m.editDate ? new Date(m.editDate * 1000).toISOString() : null,
          sender,
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

async function handleCheckAuth({ profile }: Ctx): Promise<RunResult> {
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

async function handleSendCode({ profile }: Ctx): Promise<RunResult> {
  const { apiId, apiHash } = getCredentials(profile);
  const phone = getPhone(profile);
  const client = newClient(profile);
  await client.connect();
  try {
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

async function handleSignIn({ profile, flags }: Ctx): Promise<RunResult> {
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
  [Command.Delete]: handleDelete,
  [Command.Pin]: handlePin,
  [Command.Read]: handleRead,
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
             delete <chat> <ids> [--self-only] | pin <chat> [id] [--unpin] [--silent]
Reading:     read <chat> [-n N] [--preview C] | search <q> [--chat C] [--from U] [-n N]
             mark-read <chat> | dialogs | whoami | find-user <q>
Media:       download <chat> <id> [-o DIR] | dump <chat> <out_dir> [--no-media]
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
