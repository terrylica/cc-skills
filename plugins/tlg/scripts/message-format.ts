// message-format.ts — one view of a Telegram message for every listing (read, search, thread, dump, read --json).
//
// Why: `read` used to print only "[date] (id:N) Name: text", so which earlier message a reply answered, the text it
// quoted, a forward's origin, a media item's kind beside its caption, an album, an edit or a forum topic were invisible.
// Tracing one reply then took a full `dump` of the chat and following `reply_to_msg_id` by hand (2026-11-26). This
// module reads those fields once from GramJS's message object (duck-typed, so tests need no network) and renders them
// as one line or one JSON record.
//
// Telegram's fields (layer 198, Api.Message): `replyTo` is a MessageReplyHeader with `replyToMsgId` (the parent),
// `replyToTopId` and `forumTopic` (the forum topic the message sits in), `replyToPeerId` (the parent's chat when it is
// another chat), `quote` + `quoteText` (the part of the parent the sender selected and quoted), and `replyFrom` (the
// parent's origin when it is not in this chat). `fwdFrom` is a MessageFwdHeader (`fromName`, `fromId`, `date`,
// `channelPost`). `media` is a MessageMedia* (its className names the kind); `action` makes a service message;
// `groupedId` ties the items of an album; `editDate` marks an edit; `out` an outgoing message.
//
// INVENTED-FALLBACK-OK — the listing's markers, each derived from a field above and absent when the field is:
//   ↩N / ↩N@channel:C → replyTo.replyToMsgId (+ replyToPeerId)   topic:T → replyToTopId   album:G → groupedId
//   (edited) → editDate   [fwd from X] → fwdFrom.fromName or fromId; [fwd] when Telegram gives neither
//   [photo], [document], … → media's MessageMedia* class name   [service: …] → action's MessageAction* class name
//   ❝…❞ → replyTo.quoteText (the quoted part of the parent)

import { zoneAbbrev } from "./session-footer.ts";

/** The fields of a message every listing shows. */
export interface MsgView {
  readonly id: number;
  readonly date: number | undefined; // unix seconds
  readonly sender: string;
  readonly senderId: number | undefined;
  readonly text: string;
  readonly out: boolean;
  readonly replyToId: number | undefined; // the real parent: a forum topic's root is not one
  readonly replyToRaw: number | undefined; // replyTo.replyToMsgId as Telegram stored it
  readonly replyToPeer: string | undefined; // set when the parent is in another chat
  readonly topicId: number | undefined; // forum topic root, when the message sits in a topic
  readonly quote: string | undefined; // the quoted part of the parent
  readonly fwdFrom: string | undefined; // the origin's name or peer; "" when Telegram gives neither
  readonly media: string | undefined; // "photo", "document", "web page", ...
  readonly album: string | undefined;
  readonly edited: number | undefined; // unix seconds
  readonly action: string | undefined; // service message kind
}

/** "MessageMediaPhoto" -> "photo", "MessageActionChatAddUser" -> "chat add user". */
function kindOf(className: unknown, prefix: string): string | undefined {
  if (typeof className !== "string" || !className.startsWith(prefix)) {
    return undefined;
  }
  return className
    .slice(prefix.length)
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .toLowerCase();
}

/** A peer (PeerUser / PeerChat / PeerChannel) as "user:N", "chat:N" or "channel:N". */
export function peerLabel(peer: any): string | undefined {
  if (!peer) {
    return undefined;
  }
  if (peer.userId !== undefined) {
    return `user:${peer.userId}`;
  }
  if (peer.chatId !== undefined) {
    return `chat:${peer.chatId}`;
  }
  if (peer.channelId !== undefined) {
    return `channel:${peer.channelId}`;
  }
  return undefined;
}

function num(v: unknown): number | undefined {
  if (v === undefined || v === null) {
    return undefined;
  }
  const n = Number(v);
  return Number.isFinite(n) ? n : undefined;
}

/** Read the view from a GramJS message (or any object with the same fields). */
export function viewOf(m: any, sender: string, senderId?: number): MsgView {
  const rt = m?.replyTo;
  const isReply = rt && (rt.className === undefined || rt.className === "MessageReplyHeader");
  const topic = isReply && rt.forumTopic ? (num(rt.replyToTopId) ?? num(rt.replyToMsgId)) : undefined;
  // In a forum topic, a message that replies to nothing else has replyToMsgId = the topic root: not a reply.
  const parent = isReply ? num(rt.replyToMsgId) : undefined;
  const replyToId = topic !== undefined && rt.replyToTopId === undefined && parent === topic ? undefined : parent;
  const fwd = m?.fwdFrom;
  const fwdFrom = fwd ? (fwd.fromName ?? peerLabel(fwd.fromId) ?? "") : undefined;
  return {
    id: Number(m?.id),
    date: num(m?.date),
    sender,
    senderId,
    text: typeof m?.message === "string" ? m.message : "",
    out: Boolean(m?.out),
    replyToId,
    replyToRaw: parent,
    replyToPeer: isReply ? peerLabel(rt.replyToPeerId) : undefined,
    topicId: topic,
    quote: isReply && rt.quote && typeof rt.quoteText === "string" && rt.quoteText ? rt.quoteText : undefined,
    fwdFrom,
    media: kindOf(m?.media?.className, "MessageMedia"),
    album: m?.groupedId !== undefined && m?.groupedId !== null ? String(m.groupedId) : undefined,
    edited: num(m?.editDate),
    action: kindOf(m?.action?.className, "MessageAction"),
  };
}

/** "2026-11-26 11:59:51 PCT" in `zone` (default: the process's zone), or UTC with "UTC". */
export function stamp(unix: number | undefined, opts: { zone?: string | undefined; utc?: boolean | undefined; seconds?: boolean | undefined } = {}): string {
  if (!unix) {
    return "";
  }
  const d = new Date(unix * 1000);
  const zone = opts.utc ? "UTC" : (opts.zone ?? Intl.DateTimeFormat().resolvedOptions().timeZone);
  const date = d.toLocaleDateString("en-CA", { timeZone: zone });
  const time = d.toLocaleTimeString("en-GB", {
    timeZone: zone,
    hour: "2-digit",
    minute: "2-digit",
    second: opts.seconds === false ? undefined : "2-digit",
    hour12: false,
  });
  return `${date} ${time} ${opts.utc ? "UTC" : zoneAbbrev(d, zone)}`.trim();
}

export interface LineOptions {
  readonly preview?: number | undefined; // flatten to one line and cut at this many characters
  readonly zone?: string | undefined;
  readonly utc?: boolean | undefined;
  readonly seconds?: boolean | undefined;
  readonly chat?: string | undefined; // shown first, for listings across chats (global search)
  readonly mark?: string | undefined; // prefix for the first line only, after the indent (e.g. "▶ ")
  readonly indent?: string | undefined; // prefix for every line (thread)
}

function body(text: string, preview: number | undefined, indent: string): string {
  if (preview !== undefined) {
    const flat = text.replace(/\n/g, " ⏎ ");
    return flat.length > preview ? `${flat.slice(0, preview)}…` : flat;
  }
  if (!text.includes("\n")) {
    return text;
  }
  const lines = text.split("\n");
  return `${lines[0]}\n${lines
    .slice(1)
    .map((l) => `${indent}    ${l}`)
    .join("\n")}`;
}

/**
 * One listing line:
 *   [2026-11-26 11:59:51 PCT] (id:812) ↩805 Ann Lee: text
 * with, when present: "↩N@channel:C" for a parent in another chat, "topic:T", "album:G", "(edited)",
 * "[fwd from X]" ("[fwd]" when Telegram names no origin), "[photo]" (beside a caption too), "[service: chat add user]", and the quoted part of the parent
 * on its own line as  ❝quote❞ .
 */
export function formatLine(v: MsgView, opts: LineOptions = {}): string {
  const indent = opts.indent ?? "";
  // "(id:N)" keeps its old exact form, since scripts match it (e.g. a reply watcher polling `read`); the new markers
  // follow it.
  const tags: string[] = [];
  if (v.replyToId !== undefined) {
    tags.push(`↩${v.replyToId}${v.replyToPeer ? `@${v.replyToPeer}` : ""}`);
  }
  if (v.topicId !== undefined) {
    tags.push(`topic:${v.topicId}`);
  }
  if (v.album !== undefined) {
    tags.push(`album:${v.album}`);
  }
  const marks: string[] = [];
  if (v.edited !== undefined) {
    marks.push("(edited)");
  }
  if (v.fwdFrom !== undefined) {
    marks.push(v.fwdFrom ? `[fwd from ${v.fwdFrom}]` : "[fwd]");
  }
  if (v.action !== undefined) {
    marks.push(`[service: ${v.action}]`);
  } else if (v.media !== undefined) {
    marks.push(`[${v.media}]`);
  }
  const text = v.text;
  const head = [
    `${indent}${opts.mark ?? ""}[${stamp(v.date, { zone: opts.zone, utc: opts.utc, seconds: opts.seconds })}]`,
    opts.chat ? `{${opts.chat}}` : "",
    `(id:${v.id})`,
    ...tags,
    `${v.sender}:`,
    ...marks,
  ]
    .filter(Boolean)
    .join(" ");
  const quote = v.quote !== undefined ? `\n${indent}    ❝${body(v.quote, opts.preview ?? 200, "")}❞` : "";
  return `${head}${text ? ` ${body(text, opts.preview, indent)}` : ""}${quote}`;
}

/**
 * The JSON record of `read --json`, `search --json` and `thread --json`. Its keys mean what `dump`'s same-named keys
 * mean (reply_to_msg_id as stored, reply_parent with topic roots set aside); grouped_id is a string here because album
 * ids exceed 2^53 (dump's older numeric grouped_id is lossy and kept only for compatibility).
 */
export function recordOf(v: MsgView, extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: v.id,
    date: v.date ? new Date(v.date * 1000).toISOString() : null,
    text: v.text || null,
    reply_to_msg_id: v.replyToRaw ?? null,
    reply_parent: v.replyToId ?? null,
    reply_to_peer: v.replyToPeer ?? null,
    forum_topic_id: v.topicId ?? null,
    quote_text: v.quote ?? null,
    fwd_from: v.fwdFrom ?? null,
    media_kind: v.media ?? null,
    grouped_id: v.album ?? null,
    edit_date: v.edited ? new Date(v.edited * 1000).toISOString() : null,
    out: v.out,
    action: v.action ?? null,
    sender_name: v.sender,
    sender_id: v.senderId ?? null,
    ...extra,
  };
}

/** Walk a reply chain upward. `fetch(id)` returns the message or undefined (deleted or not in this chat). */
export async function climb(
  start: number,
  fetch: (id: number) => Promise<any | undefined>,
  maxDepth = 20,
): Promise<{ chain: any[]; stop: string }> {
  const chain: any[] = [];
  const seen = new Set<number>();
  let id: number | undefined = start;
  while (id !== undefined) {
    if (seen.has(id)) {
      return { chain, stop: `cycle at ${id}` };
    }
    if (chain.length >= maxDepth) {
      return { chain, stop: `depth ${maxDepth} reached (--depth to go further)` };
    }
    seen.add(id);
    const m = await fetch(id);
    if (!m) {
      return { chain, stop: chain.length ? `message ${id} is deleted or not in this chat` : `message ${id} not found` };
    }
    chain.push(m);
    const v = viewOf(m, "");
    if (v.replyToPeer !== undefined) {
      return { chain, stop: `parent ${v.replyToId} is in ${v.replyToPeer}` };
    }
    id = v.replyToId;
  }
  const last = chain.length ? viewOf(chain[chain.length - 1], "") : undefined;
  return { chain, stop: last?.topicId !== undefined ? `topic ${last.topicId} root` : "start of the conversation" };
}
