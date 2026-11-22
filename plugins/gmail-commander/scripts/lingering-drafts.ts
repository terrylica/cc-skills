/**
 * Lingering drafts: find the drafts a new draft makes stale, and audit an account for drafts that
 * are no longer in play. Shared by `gmail-draft.ts` (checked on every run) and
 * `gmail-drafts-audit.ts` (a standalone sweep). Pure logic plus one fetch helper that takes the
 * caller's API function, so this file has no imports and runs with bare `bun`.
 *
 * WHY (2026-11-21): a batch of emails to one person was re-ranked and redrafted. Each email is a
 * NEW message, not a reply, so each draft sat in its own thread and the one-draft-per-thread check
 * never saw the earlier copy. An outdated cover draft stayed in the Drafts folder next to its
 * replacement until a manual sweep found it. The operator's rule since then: every time a draft is
 * made, prove that no earlier version of it, and nothing the new edition replaced, is still waiting.
 *
 * TWO KINDS OF FINDING
 *   superseded  same sender, at least one shared To address, both replies or both new messages, and
 *               the same subject once Braille Tally cells, "Re:"/"Fwd:" prefixes, case and spacing
 *               are ignored. Almost certainly an earlier version of the same email (a re-ranked
 *               subject differs only in its tally).
 *   related     same sender and at least one shared To address, otherwise different. Possibly still
 *               in play (a batch to one person holds many drafts), possibly merged or withdrawn. Only
 *               a person, or a list of the drafts in play (`--keep`), can tell which.
 *
 * Only To counts, never Cc: when one person (an owner, a manager) is copied on everything, a shared
 * Cc would tie every draft to every other one, and a reply to a vendor would be "superseded" by a
 * new email to an assistant (review finding, 2026-11-21).
 */

/** What the checks need to know about one draft. `date` is Gmail's internalDate in ms. */
export interface DraftMeta {
  id: string;
  threadId?: string | undefined;
  from: string;
  to: string;
  cc: string;
  subject: string;
  date: number;
}

/** Braille Patterns block: the cells of a Braille Tally, which change when an item is re-ranked. */
const BRAILLE = /[⠀-⣿]/g;
const REPLY_PREFIX = /^(?:(?:re|fwd?|aw|sv|wg)\s*:\s*)+/i;

const untallied = (subject: string): string => subject.normalize("NFKC").replace(BRAILLE, " ").replace(/\s+/g, " ").trim();

/** A subject reduced to what identifies the email: no tally, no reply prefix, no case or spacing. */
export function subjectKey(subject: string): string {
  return untallied(subject).replace(REPLY_PREFIX, "").trim().toLowerCase();
}

/** Whether the subject carries a reply or forward prefix (after any tally). */
export const isReply = (subject: string): boolean => REPLY_PREFIX.test(untallied(subject));

/** Every email address in a header value, lowercased (`Name <a@b>, c@d` → {a@b, c@d}). */
export function addresses(header: string): Set<string> {
  return new Set((header.match(/[^\s<>,;:"'()[\]]+@[^\s<>,;:"'()[\]]+/g) ?? []).map((a) => a.toLowerCase()));
}

const sender = (d: DraftMeta): string => [...addresses(d.from)][0] ?? "";
const recipients = (d: DraftMeta): Set<string> => addresses(d.to);
const overlap = (a: Set<string>, b: Set<string>): boolean => [...a].some((x) => b.has(x));

export interface Lingering {
  superseded: DraftMeta[];
  related: DraftMeta[];
}

/**
 * The other drafts that `created` may have made stale. Drafts in the same thread are left out:
 * the one-draft-per-thread invariant in `gmail-draft.ts` already refuses those.
 */
export function findLingering(created: DraftMeta, others: DraftMeta[]): Lingering {
  const out: Lingering = { superseded: [], related: [] };
  const from = sender(created);
  const to = recipients(created);
  const key = subjectKey(created.subject);
  for (const d of others) {
    if (d.id === created.id) continue;
    if (created.threadId && d.threadId === created.threadId) continue;
    if (!from || sender(d) !== from || !overlap(to, recipients(d))) continue;
    if (key && subjectKey(d.subject) === key && isReply(d.subject) === isReply(created.subject)) out.superseded.push(d);
    else out.related.push(d);
  }
  return out;
}

export interface Audit {
  /** Each draft that a NEWER draft repeats (same sender, shared recipient, same subject key). */
  superseded: Array<{ draft: DraftMeta; by: DraftMeta }>;
  /** With a keep list: drafts from the same sender to the same people as a kept draft, not kept. */
  outOfPlay: DraftMeta[];
  /** Kept ids that no longer exist in the account. */
  missingKept: string[];
}

/**
 * Sweep a whole account. `keep` lists the draft ids still in play (for example the draft ids of a
 * batch manifest); a kept draft is never flagged. Without a keep list only `superseded` is reported,
 * because a different subject alone does not prove a draft is out of play.
 */
export function auditDrafts(drafts: DraftMeta[], keep: Set<string> = new Set()): Audit {
  const superseded: Audit["superseded"] = [];
  const flagged = new Set<string>();
  for (const d of drafts) {
    if (keep.has(d.id)) continue;
    const newer = drafts
      .filter((e) => e.id !== d.id && (e.date > d.date || (e.date === d.date && keep.has(e.id))))
      .find((e) => findLingering({ ...e, threadId: undefined }, [d]).superseded.length > 0);
    if (newer) {
      superseded.push({ draft: d, by: newer });
      flagged.add(d.id);
    }
  }
  const kept = drafts.filter((d) => keep.has(d.id));
  const outOfPlay = drafts.filter(
    (d) => !keep.has(d.id) && !flagged.has(d.id) && kept.some((k) => sender(k) === sender(d) && overlap(recipients(k), recipients(d))),
  );
  const present = new Set(drafts.map((d) => d.id));
  return { superseded, outOfPlay, missingKept: [...keep].filter((id) => !present.has(id)) };
}

type Api = (path: string) => Promise<Record<string, unknown>>;

/** Hard ceiling on drafts read per run, so a huge Drafts folder cannot turn one draft into minutes. */
export const MAX_DRAFTS_SCANNED = 500;

/** List every draft (paged) with the headers the checks need. Throws when Gmail cannot be read. */
export async function listDraftMeta(api: Api, concurrency = 8): Promise<DraftMeta[]> {
  const ids: string[] = [];
  let pageToken: string | undefined;
  do {
    const page = (await api(`drafts?maxResults=100${pageToken ? `&pageToken=${pageToken}` : ""}`)) as {
      drafts?: Array<{ id: string }>;
      nextPageToken?: string;
    };
    ids.push(...(page.drafts ?? []).map((d) => d.id));
    pageToken = page.nextPageToken;
  } while (pageToken && ids.length < MAX_DRAFTS_SCANNED);
  // A partial read must never pass as clean: the earlier versions may be in the part not read.
  if (pageToken) throw new Error(`more than ${MAX_DRAFTS_SCANNED} drafts; only part of the Drafts folder could be checked`);
  const out: DraftMeta[] = [];
  const headers = ["From", "To", "Cc", "Subject"].map((h) => `metadataHeaders=${h}`).join("&");
  for (let i = 0; i < Math.min(ids.length, MAX_DRAFTS_SCANNED); i += concurrency) {
    const batch = ids.slice(i, i + concurrency);
    const got = await Promise.all(batch.map((id) => api(`drafts/${id}?format=metadata&${headers}`)));
    for (const d of got) {
      const m = (d.message ?? {}) as { threadId?: string; internalDate?: string; payload?: { headers?: Array<{ name: string; value: string }> } };
      const h = Object.fromEntries((m.payload?.headers ?? []).map((x) => [x.name.toLowerCase(), x.value]));
      out.push({ id: d.id as string, threadId: m.threadId, from: h.from ?? "", to: h.to ?? "", cc: h.cc ?? "", subject: h.subject ?? "", date: Number(m.internalDate ?? 0) });
    }
  }
  return out;
}

/** One line per draft for a person to read: id, date, recipients, subject. */
export function describe(d: DraftMeta): string {
  const when = d.date ? new Date(d.date).toISOString().slice(0, 16).replace("T", " ") : "?";
  return `${d.id}  ${when}  to ${d.to || d.cc || "(nobody)"}  "${d.subject}"`;
}
