/**
 * link-entities.ts — exact links as GramJS entities, for sends that do not go through HTML.
 *
 * `safe-links.ts` works on text; this module applies the same cut to a raw message text plus
 * its entities (what GramJS sends after parsing), and prepares read-back entities for
 * messages.EditMessage.
 *
 * Measured 2026-11-22: when a message is edited with the entities it was read back with, every
 * MessageEntityMentionName must be sent as InputMessageEntityMentionName (userId an InputUser),
 * or Telegram silently drops the mention. `editableEntities` does that conversion.
 */

import { Api } from "./vendor/telegram.js";
import { badLinks, emailSpan, linkSpans } from "./safe-links.ts";

// Entities whose text must not get a link of its own: code, and anything Telegram already
// treats as a link or an address.
const PROTECTING = new Set([
  "MessageEntityCode",
  "MessageEntityPre",
  "MessageEntityUrl",
  "MessageEntityTextUrl",
  "MessageEntityEmail",
  "MessageEntityMention",
  "MessageEntityMentionName",
  "InputMessageEntityMentionName",
  "MessageEntityBotCommand",
  "MessageEntityPhone",
]);

type Entity = Api.TypeMessageEntity;

function overlaps(a: { offset: number; length: number }, b: { offset: number; length: number }): boolean {
  return a.offset < b.offset + b.length && b.offset < a.offset + a.length;
}

function byOffset(a: Entity, b: Entity): number {
  return a.offset - b.offset || b.length - a.length;
}

/**
 * The entities of `raw` plus one exact MessageEntityTextUrl for every bare link not already
 * inside a protecting entity, or undefined when there is no link to add (send unchanged).
 */
export function withExactLinkEntities(raw: string, entities: readonly Entity[]): Entity[] | undefined {
  const guards = entities.filter((e) => PROTECTING.has(e.className));
  const added = linkSpans(raw)
    .filter((s) => !guards.some((g) => overlaps(s, g)))
    .map((s) => new Api.MessageEntityTextUrl({ offset: s.offset, length: s.length, url: s.url }));
  if (added.length === 0) {
    return undefined;
  }
  return [...entities, ...added].toSorted(byOffset);
}

/**
 * Entities for re-sending a read-back message with its links made exact: every link entity that
 * `badLinks` flags is dropped (a greedy e-mail entity is replaced by one over the address alone), and
 * each bare link left uncovered gets an exact TextUrl.
 * `changed` is false when the message needs no edit.
 */
export function relinkedEntities(message: { message?: string; entities?: readonly Entity[] | null }): {
  readonly entities: Entity[];
  readonly changed: boolean;
} {
  const raw = message.message ?? "";
  const all = [...(message.entities ?? [])];
  const bad = badLinks({ message: raw, entities: all });
  const kept = all.filter(
    (e) => !bad.some((b) => b.type === e.className && b.offset === e.offset && b.length === e.length),
  );
  // A greedy e-mail entity is replaced by one over the address alone.
  for (const b of bad) {
    const span = b.type === "MessageEntityEmail" ? emailSpan(b.text) : undefined;
    const offset = span === undefined ? -1 : b.offset + span.offset;
    if (span !== undefined && !kept.some((e) => e.className === "MessageEntityEmail" && e.offset === offset && e.length === span.length)) {
      kept.push(new Api.MessageEntityEmail({ offset: b.offset + span.offset, length: span.length }));
    }
  }
  kept.sort(byOffset);
  const relinked = withExactLinkEntities(raw, kept);
  if (bad.length === 0 && relinked === undefined) {
    return { entities: all, changed: false };
  }
  return { entities: relinked ?? kept, changed: true };
}

/** InputUser for an input peer of a user (what client.getInputEntity returns). */
export function inputUserFromPeer(peer: unknown): Api.TypeInputUser {
  if (peer instanceof Api.InputPeerSelf) {
    return new Api.InputUserSelf();
  }
  if (peer instanceof Api.InputPeerUser) {
    return new Api.InputUser({ userId: peer.userId, accessHash: peer.accessHash });
  }
  if (peer instanceof Api.InputUser || peer instanceof Api.InputUserSelf) {
    return peer;
  }
  throw new Error(`mention target is not a user: ${(peer as { className?: string })?.className ?? String(peer)}`);
}

/**
 * Read-back entities made sendable with messages.EditMessage: each MessageEntityMentionName becomes
 * an InputMessageEntityMentionName whose userId is the InputUser `resolveUser` returns, so the
 * mention survives the edit. Every other entity is passed through unchanged.
 */
export async function editableEntities(
  entities: readonly Entity[],
  resolveUser: (userId: Api.long) => Promise<Api.TypeInputUser>,
): Promise<Entity[]> {
  const out: Entity[] = [];
  for (const e of entities) {
    if (e instanceof Api.MessageEntityMentionName) {
      out.push(
        new Api.InputMessageEntityMentionName({
          offset: e.offset,
          length: e.length,
          userId: await resolveUser(e.userId),
        }),
      );
    } else {
      out.push(e);
    }
  }
  return out;
}
